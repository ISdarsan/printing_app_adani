import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'sync_status.dart';

/// Watches the signed-in user's own staff document with metadata changes to
/// learn whether the Firestore SERVER is reachable. Firestore's local cache
/// answers instantly, so `isFromCache == false` is the proof of a live
/// connection; a listener that stays cache-only past the grace period means
/// offline. Reconnection produces a fresh server snapshot, which flips the
/// state back to online by itself.
///
/// Persistence is untouched: queued writes keep flushing on their own.
class ConnectionProbe {
  ConnectionProbe._();

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static Timer? _tick;
  static DateTime? _since;
  static bool _lastFromCache = true;

  static void start(String uid, {SyncTracker? tracker}) {
    stop();
    final t = tracker ?? SyncTracker.instance;
    _since = DateTime.now();
    _lastFromCache = true;

    void evaluate() {
      final since = DateTime.now().difference(_since ?? DateTime.now());
      t.setConnection(
          connectionFromMetadata(isFromCache: _lastFromCache, sinceListen: since));
    }

    _sub = FirebaseFirestore.instance
        .collection('canteenStaff')
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      _lastFromCache = snap.metadata.isFromCache;
      if (!_lastFromCache) _since = DateTime.now();
      evaluate();
    }, onError: (_) {
      // Permission/other errors say nothing about connectivity.
    });
    // A silent (offline) listener produces no events, so re-check on a timer.
    _tick = Timer.periodic(const Duration(seconds: 3), (_) => evaluate());

    // Writes queued by an earlier session are flushed by Firestore itself.
    // Only surface them if they are still unconfirmed after a moment, so a
    // normal start does not flash a banner.
    final pending = FirebaseFirestore.instance.waitForPendingWrites();
    var done = false;
    pending.whenComplete(() => done = true);
    Timer(const Duration(milliseconds: 1500), () {
      if (!done) t.trackRestoredPending(pending);
    });
  }

  static void stop({SyncTracker? tracker}) {
    _sub?.cancel();
    _sub = null;
    _tick?.cancel();
    _tick = null;
    (tracker ?? SyncTracker.instance).reset();
  }
}
