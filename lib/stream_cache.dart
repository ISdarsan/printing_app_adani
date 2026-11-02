import 'dart:async';

/// Keeps ONE stream per call site for as long as its inputs (the "signature",
/// e.g. selected branch + day) do not change.
///
/// Why: a `StreamBuilder(stream: _makeStream())` inside `build` creates a new
/// stream on every rebuild. Flutter then cancels the old Firestore listener and
/// opens a new one, which re-reads the data (for a month of bills that is a
/// full re-read) every time the screen redraws.
///
/// Rules this class follows so that behaviour stays identical to a fresh stream:
///  * one entry per `name`, so two builders that previously had two listeners
///    still have two listeners (no late subscriber missing the first snapshot);
///  * Firestore `snapshots()` streams (and `.map()` of them) are already
///    broadcast streams: they can be listened to again after the last listener
///    left, and the native listener is closed when the last listener leaves.
///    They are cached as they are. Only a single-subscription source is wrapped
///    with `asBroadcastStream(onCancel: cancel)` so it never leaks, which means
///    such a source cannot be listened to again after its listener left;
///  * changing the signature, or calling [reset] (used by Retry), discards all
///    entries so the next build opens fresh listeners.
class StreamCache {
  final Map<String, Stream<dynamic>> _streams = {};
  String _signature = '';

  /// Number of cached entries (for tests / diagnostics).
  int get length => _streams.length;

  Stream<T> get<T>(String name, Stream<T> Function() make,
      {String signature = ''}) {
    if (signature != _signature) {
      _streams.clear();
      _signature = signature;
    }
    return (_streams[name] ??= _share(make())) as Stream<T>;
  }

  static Stream<T> _share<T>(Stream<T> source) => source.isBroadcast
      ? source
      : source.asBroadcastStream(onCancel: (sub) => sub.cancel());

  /// Forget everything; the next [get] creates new streams (Retry button).
  void reset() => _streams.clear();
}
