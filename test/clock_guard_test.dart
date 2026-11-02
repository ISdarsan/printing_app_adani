import 'dart:async';

import 'package:canteen_adani/clock_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Server instants chosen around the IST business-day boundary:
// IST day changes at 18:30 UTC.
DateTime utc(int d, int h, int m, [int s = 0]) => DateTime.utc(2026, 11, d, h, m, s);

void main() {
  tearDown(ClockGuard.resetForTest);

  group('evaluateClock', () {
    test('a correct clock: no skew, same business day', () {
      final c = evaluateClock(deviceNow: utc(2, 10, 0), serverNow: utc(2, 10, 0, 1));
      expect(c.skew.inSeconds.abs(), lessThan(5));
      expect(c.wrongBusinessDay, isFalse);
      expect(c.blocksWrites, isFalse);
    });

    test('phone a day ahead: wrong business day, blocks', () {
      final c = evaluateClock(deviceNow: utc(3, 10, 0), serverNow: utc(2, 10, 0));
      expect(c.skew, const Duration(days: 1));
      expect(c.wrongBusinessDay, isTrue);
      expect(c.blocksWrites, isTrue);
      expect(c.describeSkew, 'about 1 day ahead');
    });

    test('phone a day behind blocks too', () {
      final c = evaluateClock(deviceNow: utc(1, 10, 0), serverNow: utc(2, 10, 0));
      expect(c.blocksWrites, isTrue);
      expect(c.describeSkew, 'about 1 day behind');
    });

    test('phone 3 hours off but the SAME business day does not block', () {
      final c = evaluateClock(deviceNow: utc(2, 10, 0), serverNow: utc(2, 7, 0));
      expect(c.wrongBusinessDay, isFalse);
      expect(c.blocksWrites, isFalse);
      expect(c.describeSkew, 'about 3 hours ahead');
    });

    test('uses the IST day, not the UTC day: 17:00 UTC and 19:00 UTC are different IST days', () {
      final c = evaluateClock(deviceNow: utc(2, 19, 0), serverNow: utc(2, 17, 0));
      expect(c.wrongBusinessDay, isTrue); // 18:30 UTC is the IST midnight
      expect(c.blocksWrites, isTrue);
    });

    test('a few seconds across midnight is tolerated (not worth stopping a sale)', () {
      final c = evaluateClock(deviceNow: utc(2, 18, 30, 5), serverNow: utc(2, 18, 29, 55));
      expect(c.wrongBusinessDay, isTrue);
      expect(c.skew.inSeconds, 10);
      expect(c.blocksWrites, isFalse);
    });

    test('10 minutes across midnight is NOT tolerated', () {
      final c = evaluateClock(deviceNow: utc(2, 18, 35), serverNow: utc(2, 18, 25));
      expect(c.blocksWrites, isTrue);
    });
  });

  group('ClockGuard.current', () {
    test('cannot tell (offline) never blocks', () async {
      ClockGuard.fetchServerTime = () async => null;
      expect(await ClockGuard.current(), isNull);
    });

    test('a failing lookup never blocks and never throws', () async {
      ClockGuard.fetchServerTime = () async => throw const FormatException('x');
      expect(await ClockGuard.current(), isNull);
    });

    test('a slow lookup is abandoned quickly so billing is not delayed', () async {
      final never = Completer<DateTime?>();
      ClockGuard.fetchServerTime = () => never.future;
      final sw = Stopwatch()..start();
      final c = await ClockGuard.current(wait: const Duration(milliseconds: 50));
      expect(c, isNull);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('a fresh result is reused: one lookup, not one per bill', () async {
      var calls = 0;
      var clock = utc(2, 10, 0);
      ClockGuard.now = () => clock;
      ClockGuard.fetchServerTime = () async {
        calls++;
        return utc(3, 10, 0); // phone is a day behind
      };
      final a = await ClockGuard.current();
      clock = clock.add(const Duration(minutes: 5));
      final b = await ClockGuard.current();
      expect(calls, 1);
      expect(a!.blocksWrites, isTrue);
      expect(identical(a, b), isTrue);
    });

    test('a stale result is looked up again (the user fixed the clock)', () async {
      var calls = 0;
      var clock = utc(2, 10, 0);
      var server = utc(3, 10, 0);
      ClockGuard.now = () => clock;
      ClockGuard.fetchServerTime = () async {
        calls++;
        return server;
      };
      expect((await ClockGuard.current())!.blocksWrites, isTrue);
      clock = clock.add(const Duration(minutes: 11));
      server = clock; // the phone is now correct
      final fixed = await ClockGuard.current();
      expect(calls, 2);
      expect(fixed!.blocksWrites, isFalse);
    });

    test('concurrent callers share one lookup', () async {
      var calls = 0;
      ClockGuard.fetchServerTime = () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return DateTime.now().toUtc();
      };
      await Future.wait([ClockGuard.current(), ClockGuard.current(), ClockGuard.current()]);
      expect(calls, 1);
    });
  });

  group('ClockGuard.confirmSafe (dialog)', () {
    Widget host(void Function(BuildContext) onReady) => MaterialApp(
          home: Builder(builder: (context) {
            onReady(context);
            return const Scaffold(body: SizedBox());
          }),
        );

    testWidgets('a correct clock lets the save continue with no dialog', (t) async {
      ClockGuard.fetchServerTime = () async => DateTime.now().toUtc();
      late BuildContext ctx;
      await t.pumpWidget(host((c) => ctx = c));
      final ok = await t.runAsync(() => ClockGuard.confirmSafe(ctx));
      expect(ok, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('an unknown clock (offline) lets the save continue', (t) async {
      ClockGuard.fetchServerTime = () async => null;
      late BuildContext ctx;
      await t.pumpWidget(host((c) => ctx = c));
      expect(await t.runAsync(() => ClockGuard.confirmSafe(ctx)), isTrue);
    });

    testWidgets('a wrong date stops the save, explains it in plain words and says nothing was saved', (t) async {
      ClockGuard.fetchServerTime = () async => DateTime.now().toUtc().add(const Duration(days: 2));
      late BuildContext ctx;
      await t.pumpWidget(host((c) => ctx = c));
      bool? result;
      // no runAsync: the lookup resolves through microtasks, which pump() flushes
      unawaited(ClockGuard.confirmSafe(ctx).then((v) => result = v));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text("This phone's date is wrong"), findsOneWidget);
      expect(find.textContaining('about 2 days behind'), findsOneWidget);
      expect(find.textContaining('Nothing was saved'), findsOneWidget);
      expect(find.textContaining('Automatic date & time'), findsOneWidget);
      expect(result, isNull, reason: 'still waiting for the user to read it');
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(result, isFalse);
    });
  });
}
