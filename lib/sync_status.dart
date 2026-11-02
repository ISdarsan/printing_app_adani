import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Synchronisation status, built so the UI never claims more than is known.
///
/// * An operation counts as saved ONLY when the Future of the Firestore call
///   completes. For `add/set/update` that Future completes when the SERVER has
///   acknowledged the write (not when it is queued locally), so an offline
///   write correctly stays "pending". Transactions fail offline and are
///   reported as failed.
/// * Cached screens are flagged by the offline banner: values shown while
///   offline are saved data, not current server data.
/// * Retrying is offered only for operations that are safe to repeat
///   (idempotent by document id, or verified against the server first).

enum SyncState { connecting, synced, pending, offline, failed }

enum SyncConnection { unknown, online, offline }

enum OpStatus { inFlight, failed }

class SyncOperation {
  final String key;
  final String label;
  final bool safeToRetry;
  final DateTime startedAt;
  OpStatus status = OpStatus.inFlight;
  Object? error;
  Future<void> Function()? _rerun;
  SyncOperation(this.key, this.label, this.safeToRetry, this.startedAt);
}

/// Thrown when the same operation is submitted while it is still in flight
/// (double tap, or a second screen submitting the same record).
class DuplicateOperationException implements Exception {
  final String key;
  const DuplicateOperationException(this.key);
  @override
  String toString() => 'This change is already being saved ($key).';
}

class SyncTracker extends ChangeNotifier {
  SyncTracker();

  /// App-wide instance used by the banner and the write paths.
  static final SyncTracker instance = SyncTracker();

  SyncConnection _connection = SyncConnection.unknown;
  final _ops = <String, SyncOperation>{};
  int _restored = 0;

  SyncConnection get connection => _connection;
  List<SyncOperation> get operations => List.unmodifiable(_ops.values);
  int get inFlightCount =>
      _ops.values.where((o) => o.status == OpStatus.inFlight).length + _restored;
  int get failedCount =>
      _ops.values.where((o) => o.status == OpStatus.failed).length;
  bool isInFlight(String key) => _ops[key]?.status == OpStatus.inFlight;

  SyncState get state {
    if (failedCount > 0) return SyncState.failed;
    if (_connection == SyncConnection.offline) return SyncState.offline;
    if (inFlightCount > 0) return SyncState.pending;
    if (_connection == SyncConnection.unknown) return SyncState.connecting;
    return SyncState.synced;
  }

  /// One-line text for the banner. Empty = nothing to show.
  String get message {
    switch (state) {
      case SyncState.synced:
      case SyncState.connecting:
        return '';
      case SyncState.pending:
        final n = inFlightCount;
        return 'Saving $n change${n == 1 ? '' : 's'}...';
      case SyncState.offline:
        final n = inFlightCount;
        return n == 0
            ? 'Offline. Showing saved data, which may be out of date.'
            : 'Offline. $n change${n == 1 ? '' : 's'} will sync when you reconnect.';
      case SyncState.failed:
        final n = failedCount;
        return '$n change${n == 1 ? '' : 's'} not saved. Tap to review.';
    }
  }

  void setConnection(SyncConnection c) {
    if (c == _connection) return;
    _connection = c;
    notifyListeners();
  }

  /// Writes queued in a previous session are flushed by Firestore on start;
  /// [done] completes when the server has acknowledged all of them.
  void trackRestoredPending(Future<void> done) {
    _restored++;
    notifyListeners();
    done.catchError((_) {}).whenComplete(() {
      _restored--;
      notifyListeners();
    });
  }

  /// Runs [run] and tracks it. Returns its result once it has completed, which
  /// for Firestore writes means server-acknowledged. Rethrows its error after
  /// recording it as failed.
  Future<T> track<T>({
    required String key,
    required String label,
    required Future<T> Function() run,
    bool safeToRetry = false,
    DateTime Function()? clock,
  }) async {
    if (isInFlight(key)) throw DuplicateOperationException(key);
    final op = SyncOperation(key, label, safeToRetry, (clock ?? DateTime.now)());
    _ops[key] = op;
    op._rerun = () async {
      await run();
    };
    notifyListeners();
    try {
      final result = await run();
      if (identical(_ops[key], op)) _ops.remove(key);
      notifyListeners();
      return result;
    } catch (e) {
      op.status = OpStatus.failed;
      op.error = e;
      notifyListeners();
      rethrow;
    }
  }

  /// Re-runs a failed operation. Refused unless it was registered as safe.
  Future<void> retry(String key) async {
    final op = _ops[key];
    if (op == null || op.status != OpStatus.failed) return;
    if (!op.safeToRetry) {
      throw StateError('"${op.label}" cannot be retried automatically. '
          'Check the record first, then enter it again if it is missing.');
    }
    op.status = OpStatus.inFlight;
    op.error = null;
    notifyListeners();
    try {
      await op._rerun!();
      if (identical(_ops[key], op)) _ops.remove(key);
      notifyListeners();
    } catch (e) {
      op.status = OpStatus.failed;
      op.error = e;
      notifyListeners();
      rethrow;
    }
  }

  void dismiss(String key) {
    if (_ops[key]?.status == OpStatus.failed) {
      _ops.remove(key);
      notifyListeners();
    }
  }

  /// Test helper / sign-out.
  void reset() {
    _ops.clear();
    _restored = 0;
    _connection = SyncConnection.unknown;
    notifyListeners();
  }
}

/// Maps a Firestore snapshot's metadata to a connection state.
///
/// A listener that has only ever delivered cached data after [grace] means the
/// server is unreachable; any snapshot with `isFromCache == false` proves the
/// server answered.
SyncConnection connectionFromMetadata({
  required bool isFromCache,
  required Duration sinceListen,
  Duration grace = const Duration(seconds: 5),
}) {
  if (!isFromCache) return SyncConnection.online;
  return sinceListen >= grace ? SyncConnection.offline : SyncConnection.unknown;
}

// ---------------------------------------------------------------------------
// Financial operations: never retried blindly
// ---------------------------------------------------------------------------

/// Stable request id per logical attempt. If a save fails with an unknown
/// outcome (the commit may or may not have happened) the SAME id is reused for
/// the next tap so the server can be asked "does a record with this id
/// exist?" before anything is created again.
class AttemptTracker {
  final Random _rnd;
  AttemptTracker([Random? rnd]) : _rnd = rnd ?? Random.secure();

  String? _key;
  String? _id;
  bool _attempted = false;

  /// Id for the operation described by [contentKey] (a digest of everything
  /// that makes this save "the same save": user, branch, items, amount...).
  String idFor(String contentKey) {
    if (_key != contentKey || _id == null) {
      _key = contentKey;
      _id = _newId();
      _attempted = false;
    }
    return _id!;
  }

  /// True when a previous attempt with this exact content did not end in a
  /// confirmed success, so the server must be checked before creating again.
  bool get needsServerCheck => _attempted;

  void markAttempted() => _attempted = true;

  /// Call after a confirmed success: the next identical content is a NEW sale.
  void succeeded() {
    _key = null;
    _id = null;
    _attempted = false;
  }

  String _newId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final r = List.generate(6, (_) => _rnd.nextInt(36).toRadixString(36)).join();
    return 'req_${t}_$r';
  }
}

/// Create-once protocol for non-idempotent financial writes.
///
/// 1. If an earlier attempt may have committed, [findExisting] asks the server.
///    A hit is returned as the result: nothing is created twice.
/// 2. Otherwise [create] runs; the attempt is recorded BEFORE it starts, so an
///    ambiguous failure (timeout/connection loss during commit) leads to the
///    check in step 1 next time.
Future<T> createOnce<T>({
  required AttemptTracker attempts,
  required Future<T?> Function() findExisting,
  required Future<T> Function() create,
}) async {
  if (attempts.needsServerCheck) {
    final existing = await findExisting();
    if (existing != null) {
      attempts.succeeded();
      return existing;
    }
  }
  attempts.markAttempted();
  final result = await create();
  attempts.succeeded();
  return result;
}

/// Idempotent `set` with a client-chosen document id.
///
/// If the first attempt actually committed but the acknowledgement was lost,
/// the repeat is evaluated by the rules as an UPDATE (cashiers may only create)
/// and is denied, or the doc already exists. Reading the document from the
/// server settles it: present = it was saved.
Future<void> confirmedSet({
  required Future<void> Function() write,
  required Future<bool> Function() existsOnServer,
  bool Function(Object error)? isDeniedOrExists,
}) async {
  try {
    await write();
  } catch (e) {
    final ambiguous = (isDeniedOrExists ?? _defaultAmbiguous)(e);
    if (ambiguous && await existsOnServer()) return;
    rethrow;
  }
}

bool _defaultAmbiguous(Object e) {
  final s = e.toString();
  return s.contains('permission-denied') || s.contains('already-exists');
}

/// Tracked, idempotent write for records with a client-chosen id (expenses,
/// notices). Returns `true` when the server confirmed within [wait], `false`
/// when it is still pending (typically offline): the write stays queued and
/// tracked, the screen is released, and the banner shows it as unconfirmed.
/// A failure is recorded (retryable, since the id makes a repeat safe) and
/// rethrown so the caller can say so.
Future<bool> trackedConfirmedWrite({
  required String key,
  required String label,
  required Future<void> Function() write,
  required Future<bool> Function() existsOnServer,
  Duration wait = const Duration(seconds: 8),
  SyncTracker? tracker,
}) async {
  final t = tracker ?? SyncTracker.instance;
  final saving = t.track<void>(
    key: key,
    label: label,
    safeToRetry: true,
    run: () => confirmedSet(write: write, existsOnServer: existsOnServer),
  );
  try {
    await saving.timeout(wait);
    return true;
  } on TimeoutException {
    // Keep tracking in the background; swallow its eventual error here (it is
    // already recorded on the operation).
    saving.then((_) {}, onError: (_) {});
    return false;
  }
}
