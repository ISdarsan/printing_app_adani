import 'dart:async';

import 'package:canteen_adani/state_views.dart';
import 'package:canteen_adani/theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {Size size = const Size(360, 640), double scale = 1}) {
  return MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
    child: MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('friendlyErrorMessage', () {
    test('permission problems are explained in business language', () {
      final m = friendlyErrorMessage(
          FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
      expect(m, contains('do not have access'));
    });
    test('connection problems tell the user to check the internet', () {
      for (final code in ['unavailable', 'deadline-exceeded']) {
        final m = friendlyErrorMessage(
            FirebaseException(plugin: 'cloud_firestore', code: code));
        expect(m, contains('internet'));
      }
    });
    test('a missing database index is explained as a one-time setup for the admin', () {
      final m = friendlyErrorMessage(FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
          message: 'The query requires an index. https://console.firebase.google.com/...'));
      expect(m, contains('one-time database setup'));
      expect(m, contains('tell the admin'));
      expect(m, isNot(contains('http')));
      expect(m.toLowerCase(), isNot(contains('index')));
    });
    test('saving failures say saving, not loading', () {
      final m = friendlyErrorMessage(StateError('x'), action: 'saving');
      expect(m, contains('saving'));
      expect(m, isNot(contains('loading')));
    });
    test('unknown errors never leak technical text', () {
      final m = friendlyErrorMessage(StateError('boom: stack trace here'));
      expect(m, isNot(contains('boom')));
      expect(m.toLowerCase(), isNot(contains('firebase')));
      expect(m.toLowerCase(), isNot(contains('firestore')));
    });
  });

  group('state views', () {
    testWidgets('loading shows a spinner and the message', (t) async {
      await t.pumpWidget(host(const AppLoading(message: 'Loading bills')));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading bills'), findsOneWidget);
    });

    testWidgets('a loading view that takes too long tells the user to check the internet', (t) async {
      await t.pumpWidget(host(const AppLoading()));
      expect(find.textContaining('Still loading'), findsNothing);
      await t.pump(const Duration(seconds: 9));
      expect(find.text('Still loading. Check your internet connection.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('removing the loading view before the timeout leaves no pending timer', (t) async {
      await t.pumpWidget(host(const AppLoading()));
      await t.pumpWidget(host(const SizedBox()));
      await t.pump(const Duration(seconds: 20)); // would throw if a timer fired on a dead state
    });

    testWidgets('empty state shows title and hint', (t) async {
      await t.pumpWidget(host(const AppEmptyState(
          title: 'No bills yet', message: 'Bills made today appear here.')));
      expect(find.text('No bills yet'), findsOneWidget);
      expect(find.text('Bills made today appear here.'), findsOneWidget);
    });

    testWidgets('error state offers Try again and calls the callback', (t) async {
      var retried = 0;
      await t.pumpWidget(host(AppErrorState(
          error: FirebaseException(plugin: 'x', code: 'unavailable'),
          onRetry: () => retried++)));
      expect(find.text('Could not load'), findsOneWidget);
      expect(find.textContaining('internet'), findsOneWidget);
      await t.tap(find.text('Try again'));
      expect(retried, 1);
    });

    testWidgets('error state without a callback has no button', (t) async {
      await t.pumpWidget(host(const AppErrorState()));
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('Try again is a comfortable touch target (>= 48 px high)', (t) async {
      await t.pumpWidget(host(AppErrorState(onRetry: () {})));
      final size = t.getSize(find.byType(OutlinedButton));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    for (final c in [
      (name: 'small phone', size: const Size(320, 480), scale: 1.0),
      (name: 'small phone, 200% text', size: const Size(320, 480), scale: 2.0),
      (name: 'landscape phone', size: const Size(640, 320), scale: 1.0),
      (name: 'tablet', size: const Size(900, 1200), scale: 1.0),
    ]) {
      testWidgets('no overflow: ${c.name}', (t) async {
        for (final w in <Widget>[
          const AppLoading(message: 'Loading'),
          const AppEmptyState(title: 'No bills yet', message: 'Nothing here.'),
          AppErrorState(onRetry: () {}),
        ]) {
          await t.pumpWidget(host(w, size: c.size, scale: c.scale));
          expect(t.takeException(), isNull);
        }
      });
    }

    testWidgets('inline error works inside a scrolling Column (unbounded height)', (t) async {
      await t.pumpWidget(host(SingleChildScrollView(
        child: Column(children: [
          const Text('Header'),
          AppErrorState(inline: true, onRetry: () {}),
          const Text('Footer'),
        ]),
      )));
      expect(t.takeException(), isNull);
      expect(find.text('Could not load'), findsOneWidget);
      expect(find.text('Footer'), findsOneWidget);
    });
  });

  group('asyncStateView', () {
    test('error beats everything', () {
      final w = asyncStateView(
          const AsyncSnapshot<int>.withError(ConnectionState.active, 'x'));
      expect(w, isA<AppErrorState>());
    });
    test('no data yet shows loading', () {
      expect(asyncStateView(const AsyncSnapshot<int>.waiting()),
          isA<AppLoading>());
    });
    test('data present returns null so the caller renders it', () {
      expect(
          asyncStateView(
              const AsyncSnapshot<int>.withData(ConnectionState.active, 1)),
          isNull);
    });
  });

  group('RetryScope', () {
    testWidgets('Retry re-creates the builder so a fresh stream is opened', (t) async {
      var opened = 0;
      await t.pumpWidget(host(RetryScope(
        builder: (context, attempt, retry) => StreamBuilder<int>(
          key: ValueKey(attempt),
          stream: () {
            opened++;
            return Stream<int>.error(StateError('x'));
          }(),
          builder: (context, snap) => snap.hasError
              ? AppErrorState(onRetry: retry)
              : const AppLoading(),
        ),
      )));
      await t.pump();
      expect(find.text('Try again'), findsOneWidget);
      final before = opened;

      await t.tap(find.text('Try again'));
      await t.pump();
      expect(opened, greaterThan(before));
    });
  });
}
