import 'dart:async';
import 'dart:math';

import 'package:canteen_adani/sync_banner.dart';
import 'package:canteen_adani/sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SyncTracker t;
  setUp(() => t = SyncTracker());

  group('states', () {
    test('starts as connecting, never "synced" before the server has answered', () {
      expect(t.state, SyncState.connecting);
      expect(t.message, isEmpty);
    });

    test('online and idle = synced; nothing shown', () {
      t.setConnection(SyncConnection.online);
      expect(t.state, SyncState.synced);
      expect(t.message, isEmpty);
    });

    test('offline without pending work warns that data is cached', () {
      t.setConnection(SyncConnection.offline);
      expect(t.state, SyncState.offline);
      expect(t.message, contains('saved data'));
      expect(t.message, contains('out of date'));
    });
  });

  group('success is claimed only after the write completes', () {
    test('pending until the future completes, then synced and removed', () async {
      t.setConnection(SyncConnection.online);
      final gate = Completer<int>();
      final f = t.track<int>(key: 'a', label: 'Expense', run: () => gate.future);
      expect(t.state, SyncState.pending);
      expect(t.message, 'Saving 1 change...');
      expect(t.inFlightCount, 1);

      gate.complete(7);
      expect(await f, 7);
      expect(t.state, SyncState.synced);
      expect(t.operations, isEmpty);
    });

    test('an unacknowledged write stays pending no matter how long it takes', () async {
      t.setConnection(SyncConnection.online);
      final never = Completer<void>();
      // ignore: unawaited_futures
      t.track<void>(key: 'slow', label: 'x', run: () => never.future);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(t.state, SyncState.pending);
    });
  });

  group('offline and reconnection', () {
    test('offline with queued writes, then reconnect, then server confirms', () async {
      t.setConnection(SyncConnection.online);
      final ack = Completer<void>();
      // ignore: unawaited_futures
      final f = t.track<void>(key: 'e1', label: 'Expense ₹120', run: () => ack.future);
      expect(t.state, SyncState.pending);

      t.setConnection(SyncConnection.offline);
      expect(t.state, SyncState.offline);
      expect(t.message, 'Offline. 1 change will sync when you reconnect.');

      t.setConnection(SyncConnection.online); // reconnected: SDK is flushing
      expect(t.state, SyncState.pending, reason: 'not synced until acknowledged');

      ack.complete(); // server acknowledges the queued write
      await f;
      expect(t.state, SyncState.synced);
    });

    test('two queued writes are counted and plural is used', () {
      t.setConnection(SyncConnection.offline);
      final c = Completer<void>();
      // ignore: unawaited_futures
      t.track<void>(key: '1', label: 'a', run: () => c.future);
      // ignore: unawaited_futures
      t.track<void>(key: '2', label: 'b', run: () => c.future);
      expect(t.message, 'Offline. 2 changes will sync when you reconnect.');
    });

    test('flapping connection does not lose or confirm anything', () {
      final c = Completer<void>();
      // ignore: unawaited_futures
      t.track<void>(key: '1', label: 'a', run: () => c.future);
      for (final s in [SyncConnection.online, SyncConnection.offline, SyncConnection.online, SyncConnection.offline]) {
        t.setConnection(s);
        expect(t.inFlightCount, 1);
      }
    });

    test('writes queued by an earlier session show as pending until flushed', () async {
      t.setConnection(SyncConnection.online);
      final flushed = Completer<void>();
      t.trackRestoredPending(flushed.future);
      expect(t.state, SyncState.pending);
      flushed.complete();
      await Future<void>.delayed(Duration.zero);
      expect(t.state, SyncState.synced);
    });

    test('a failing background flush does not leave the banner stuck', () async {
      t.setConnection(SyncConnection.online);
      final flushed = Completer<void>();
      t.trackRestoredPending(flushed.future);
      flushed.completeError('boom');
      await Future<void>.delayed(Duration.zero);
      expect(t.inFlightCount, 0);
    });
  });

  group('connection from Firestore metadata', () {
    test('a server snapshot proves online at any time', () {
      expect(connectionFromMetadata(isFromCache: false, sinceListen: const Duration(seconds: 90)),
          SyncConnection.online);
    });
    test('cache-only is unknown during the grace period, offline after it', () {
      expect(connectionFromMetadata(isFromCache: true, sinceListen: const Duration(seconds: 2)),
          SyncConnection.unknown);
      expect(connectionFromMetadata(isFromCache: true, sinceListen: const Duration(seconds: 5)),
          SyncConnection.offline);
    });
  });

  group('failed writes and retry', () {
    test('a failure is recorded, rethrown, and shown as failed', () async {
      t.setConnection(SyncConnection.online);
      await expectLater(
          t.track<void>(key: 'x', label: 'Expense', run: () async => throw StateError('denied')),
          throwsStateError);
      expect(t.state, SyncState.failed);
      expect(t.failedCount, 1);
      expect(t.message, '1 change not saved. Tap to review.');
      expect(t.operations.single.error, isA<StateError>());
    });

    test('failed beats offline: the user must see what was not saved', () async {
      t.setConnection(SyncConnection.offline);
      await expectLater(
          t.track<void>(key: 'x', label: 'a', run: () async => throw 'e'), throwsA(anything));
      expect(t.state, SyncState.failed);
    });

    test('a retry-safe operation can be retried and then clears', () async {
      t.setConnection(SyncConnection.online);
      var calls = 0;
      Future<void> run() async {
        calls++;
        if (calls == 1) throw StateError('network');
      }

      await expectLater(t.track<void>(key: 'e', label: 'Expense', safeToRetry: true, run: run),
          throwsStateError);
      expect(t.state, SyncState.failed);
      await t.retry('e');
      expect(calls, 2);
      expect(t.state, SyncState.synced);
      expect(t.operations, isEmpty);
    });

    test('a failed retry stays failed (no silent success)', () async {
      t.setConnection(SyncConnection.online);
      await expectLater(
          t.track<void>(key: 'e', label: 'x', safeToRetry: true, run: () async => throw 'a'),
          throwsA(anything));
      await expectLater(t.retry('e'), throwsA(anything));
      expect(t.state, SyncState.failed);
    });

    test('an unsafe (financial) operation is NEVER retried by the tracker', () async {
      t.setConnection(SyncConnection.online);
      var calls = 0;
      await expectLater(
          t.track<void>(key: 'bill', label: 'Bill', safeToRetry: false, run: () async {
            calls++;
            throw StateError('timeout during commit');
          }),
          throwsStateError);
      await expectLater(t.retry('bill'), throwsStateError);
      expect(calls, 1, reason: 'the money operation must not be re-run blindly');
      expect(t.state, SyncState.failed);
    });

    test('dismiss removes only failed operations', () async {
      t.setConnection(SyncConnection.online);
      final c = Completer<void>();
      // ignore: unawaited_futures
      t.track<void>(key: 'live', label: 'a', run: () => c.future);
      await expectLater(
          t.track<void>(key: 'bad', label: 'b', run: () async => throw 'e'), throwsA(anything));
      t.dismiss('live'); // in flight: ignored
      expect(t.operations.length, 2);
      t.dismiss('bad');
      expect(t.operations.length, 1);
    });
  });

  group('duplicate submission prevention', () {
    test('the same key cannot be started twice while in flight', () async {
      t.setConnection(SyncConnection.online);
      var runs = 0;
      final gate = Completer<void>();
      // ignore: unawaited_futures
      final first = t.track<void>(key: 'dup', label: 'a', run: () {
        runs++;
        return gate.future;
      });
      await expectLater(
          t.track<void>(key: 'dup', label: 'a', run: () async => runs++),
          throwsA(isA<DuplicateOperationException>()));
      expect(runs, 1);
      gate.complete();
      await first;
    });

    test('after it finished the key can be used again', () async {
      await t.track<void>(key: 'k', label: 'a', run: () async {});
      await t.track<void>(key: 'k', label: 'a', run: () async {});
      expect(t.operations, isEmpty);
    });

    test('re-submitting a failed key replaces the failed entry', () async {
      await expectLater(
          t.track<void>(key: 'k', label: 'a', run: () async => throw 'e'), throwsA(anything));
      await t.track<void>(key: 'k', label: 'a', run: () async {});
      expect(t.operations, isEmpty);
    });
  });

  group('create-once protocol for financial writes', () {
    test('success: one create, request id cleared so the next identical sale is new', () async {
      final a = AttemptTracker(Random(1));
      var creates = 0;
      final id1 = a.idFor('sale-A');
      await createOnce<String>(
          attempts: a, findExisting: () async => null, create: () async => 'b${++creates}');
      final id2 = a.idFor('sale-A');
      expect(creates, 1);
      expect(id2, isNot(id1), reason: 'a repeat after success is a new sale');
    });

    test('lost acknowledgement: second tap finds the first bill and creates nothing', () async {
      final a = AttemptTracker(Random(2));
      var creates = 0;
      final requestId = a.idFor('sale-A');
      // first tap: the commit happened on the server but the client saw an error
      await expectLater(
          createOnce<String>(
              attempts: a,
              findExisting: () async => null,
              create: () async {
                creates++;
                throw StateError('deadline exceeded after commit');
              }),
          throwsStateError);
      expect(a.needsServerCheck, isTrue);
      expect(a.idFor('sale-A'), requestId, reason: 'same attempt, same id');

      // second tap: server already holds the bill with that request id
      final r = await createOnce<String>(
          attempts: a,
          findExisting: () async => 'BILL-123',
          create: () async {
            creates++;
            return 'DUPLICATE';
          });
      expect(r, 'BILL-123');
      expect(creates, 1, reason: 'no second bill was created');
      expect(a.needsServerCheck, isFalse);
    });

    test('genuine failure (nothing on the server): the retry creates, with the same id', () async {
      final a = AttemptTracker(Random(3));
      var creates = 0;
      final id = a.idFor('sale-B');
      await expectLater(
          createOnce<String>(
              attempts: a,
              findExisting: () async => null,
              create: () async {
                creates++;
                throw StateError('offline');
              }),
          throwsStateError);
      final r = await createOnce<String>(
          attempts: a, findExisting: () async => null, create: () async => 'new${++creates}');
      expect(r, 'new2');
      expect(creates, 2);
      expect(id, isNotEmpty);
    });

    test('changing the cart starts a fresh attempt: no server check, new id', () async {
      final a = AttemptTracker(Random(4));
      final id1 = a.idFor('cart-1');
      await expectLater(
          createOnce<String>(
              attempts: a,
              findExisting: () async => null,
              create: () async => throw StateError('x')),
          throwsStateError);
      final id2 = a.idFor('cart-2');
      expect(id2, isNot(id1));
      expect(a.needsServerCheck, isFalse);
    });

    test('the server check itself failing aborts instead of risking a duplicate', () async {
      final a = AttemptTracker(Random(5));
      a.idFor('c');
      a.markAttempted();
      var creates = 0;
      await expectLater(
          createOnce<String>(
              attempts: a,
              findExisting: () async => throw StateError('cannot reach server'),
              create: () async => 'b${++creates}'),
          throwsStateError);
      expect(creates, 0);
    });

    test('request ids are unique and well formed', () {
      final a = AttemptTracker(Random(6));
      final ids = {for (var i = 0; i < 500; i++) (AttemptTracker(Random(i))..idFor('k')).idFor('k')};
      expect(ids.length, greaterThan(490));
      expect(a.idFor('z'), startsWith('req_'));
    });
  });

  group('confirmedSet (idempotent writes with a client-chosen id)', () {
    test('plain success', () async {
      var reads = 0;
      await confirmedSet(write: () async {}, existsOnServer: () async {
        reads++;
        return true;
      });
      expect(reads, 0);
    });
    test('repeat denied as an update but the record exists on the server = saved', () async {
      await confirmedSet(
          write: () async => throw 'permission-denied: update',
          existsOnServer: () async => true);
    });
    test('denied and NOT on the server = a real failure', () async {
      await expectLater(
          confirmedSet(
              write: () async => throw 'permission-denied',
              existsOnServer: () async => false),
          throwsA(anything));
    });
    test('unrelated errors are rethrown without touching the server', () async {
      var reads = 0;
      await expectLater(
          confirmedSet(write: () async => throw 'unavailable', existsOnServer: () async {
            reads++;
            return true;
          }),
          throwsA(anything));
      expect(reads, 0);
    });
  });

  group('trackedConfirmedWrite (expenses, notices)', () {
    test('confirmed quickly: returns true and nothing stays pending', () async {
      t.setConnection(SyncConnection.online);
      final ok = await trackedConfirmedWrite(
          key: 'expenses:1', label: 'Expense', write: () async {}, existsOnServer: () async => false, tracker: t);
      expect(ok, isTrue);
      expect(t.state, SyncState.synced);
    });

    test('offline: returns false after the wait, stays pending, confirms later', () async {
      t.setConnection(SyncConnection.offline);
      final ack = Completer<void>();
      final ok = await trackedConfirmedWrite(
          key: 'expenses:2',
          label: 'Expense ₹50',
          wait: const Duration(milliseconds: 30),
          write: () => ack.future,
          existsOnServer: () async => false,
          tracker: t);
      expect(ok, isFalse, reason: 'caller must not say "saved"');
      expect(t.inFlightCount, 1);
      expect(t.message, contains('Offline'));

      t.setConnection(SyncConnection.online);
      ack.complete(); // reconnect: SDK delivers the queued write
      await Future<void>.delayed(Duration.zero);
      expect(t.state, SyncState.synced);
    });

    test('a late failure after the caller moved on is recorded, not lost', () async {
      t.setConnection(SyncConnection.online);
      final gate = Completer<void>();
      final ok = await trackedConfirmedWrite(
          key: 'expenses:3',
          label: 'Expense',
          wait: const Duration(milliseconds: 20),
          write: () => gate.future,
          existsOnServer: () async => false,
          tracker: t);
      expect(ok, isFalse);
      gate.completeError('unavailable');
      await Future<void>.delayed(Duration.zero);
      expect(t.state, SyncState.failed);
      expect(t.operations.single.safeToRetry, isTrue);
    });

    test('immediate failure is thrown to the caller and retry works', () async {
      t.setConnection(SyncConnection.online);
      var n = 0;
      await expectLater(
          trackedConfirmedWrite(
              key: 'expenses:4',
              label: 'Expense',
              write: () async {
                if (++n == 1) throw 'unavailable';
              },
              existsOnServer: () async => false,
              tracker: t),
          throwsA(anything));
      expect(t.state, SyncState.failed);
      await t.retry('expenses:4');
      expect(t.state, SyncState.synced);
      expect(n, 2);
    });

    test('double tap on the same record is refused', () async {
      t.setConnection(SyncConnection.online);
      final gate = Completer<void>();
      final first = trackedConfirmedWrite(
          key: 'expenses:5', label: 'E', write: () => gate.future, existsOnServer: () async => false, tracker: t);
      await expectLater(
          trackedConfirmedWrite(
              key: 'expenses:5', label: 'E', write: () async {}, existsOnServer: () async => false, tracker: t),
          throwsA(isA<DuplicateOperationException>()));
      gate.complete();
      expect(await first, isTrue);
    });
  });

  group('banner UI', () {
    Widget host(SyncTracker tracker) => MaterialApp(
          navigatorKey: appNavigatorKey,
          builder: (c, child) => SyncShell(tracker: tracker, child: child!),
          home: const Scaffold(body: Text('SCREEN')),
        );

    testWidgets('nothing is shown when everything is saved', (w) async {
      t.setConnection(SyncConnection.online);
      await w.pumpWidget(host(t));
      expect(find.byKey(const Key('sync-banner-text')), findsNothing);
      expect(find.text('SCREEN'), findsOneWidget);
    });

    testWidgets('offline shows the cached-data warning; reconnect hides it', (w) async {
      t.setConnection(SyncConnection.offline);
      await w.pumpWidget(host(t));
      expect(find.textContaining('saved data'), findsOneWidget);
      t.setConnection(SyncConnection.online);
      await w.pump();
      expect(find.byKey(const Key('sync-banner-text')), findsNothing);
    });

    testWidgets('failed write: details sheet offers Retry for a safe op and works', (w) async {
      t.setConnection(SyncConnection.online);
      var n = 0;
      await expectLater(
          t.track<void>(key: 'expenses:9', label: 'Expense ₹80', safeToRetry: true, run: () async {
            if (++n == 1) throw 'unavailable';
          }),
          throwsA(anything));
      await w.pumpWidget(host(t));
      expect(find.text('1 change not saved. Tap to review.'), findsOneWidget);
      await w.tap(find.byKey(const Key('sync-banner-text')));
      await w.pumpAndSettle();
      expect(find.text('Expense ₹80'), findsOneWidget);
      await w.tap(find.byKey(const Key('retry-expenses:9')));
      await w.pumpAndSettle();
      expect(n, 2);
      expect(t.state, SyncState.synced);
    });

    testWidgets('failed financial write: no Retry button, guidance to check first', (w) async {
      t.setConnection(SyncConnection.online);
      await expectLater(
          t.track<void>(key: 'bill:r1', label: 'Bill ₹250', safeToRetry: false, run: () async => throw 'timeout'),
          throwsA(anything));
      await w.pumpWidget(host(t));
      await w.tap(find.byKey(const Key('sync-banner-text')));
      await w.pumpAndSettle();
      expect(find.byKey(const Key('retry-bill:r1')), findsNothing);
      expect(find.byKey(const Key('dismiss-bill:r1')), findsOneWidget);
      expect(find.textContaining('Check whether it was recorded'), findsOneWidget);
    });
  });
}
