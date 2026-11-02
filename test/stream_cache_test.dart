import 'dart:async';

import 'package:canteen_adani/stream_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  listenerMeasurement();

  test('same name and signature returns the very same stream (no new listener)', () {
    final cache = StreamCache();
    var made = 0;
    Stream<int> make() {
      made++;
      return StreamController<int>.broadcast().stream;
    }

    final a = cache.get<int>('x', make, signature: 's');
    final b = cache.get<int>('x', make, signature: 's');
    expect(identical(a, b), isTrue);
    expect(made, 1);
  });

  test('a different name is a different stream (one listener per builder)', () {
    final cache = StreamCache();
    final a = cache.get<int>('a', () => StreamController<int>.broadcast().stream);
    final b = cache.get<int>('b', () => StreamController<int>.broadcast().stream);
    expect(identical(a, b), isFalse);
    expect(cache.length, 2);
  });

  test('changing the signature (branch / day / month) opens a fresh stream', () {
    final cache = StreamCache();
    var made = 0;
    Stream<int> make() {
      made++;
      return StreamController<int>.broadcast().stream;
    }

    cache.get<int>('x', make, signature: 'main|2027-01-01');
    cache.get<int>('x', make, signature: 'main|2027-01-02');
    expect(made, 2);
  });

  test('reset (Retry) discards cached streams', () {
    final cache = StreamCache();
    var made = 0;
    Stream<int> make() {
      made++;
      return StreamController<int>.broadcast().stream;
    }

    cache.get<int>('x', make);
    cache.reset();
    cache.get<int>('x', make);
    expect(made, 2);
    expect(cache.length, 1);
  });

  test('a removed builder can listen again without a "already listened" error', () async {
    final cache = StreamCache();
    final ctrl = StreamController<int>.broadcast(); // like Firestore snapshots()
    final stream = cache.get<int>('x', () => ctrl.stream);
    expect(stream.isBroadcast, isTrue);

    final first = <int>[];
    final sub1 = stream.listen(first.add);
    ctrl.add(1);
    await Future<void>.delayed(Duration.zero);
    await sub1.cancel();

    // A second builder listening later must not throw.
    expect(() => stream.listen((_) {}), returnsNormally);
    expect(first, [1]);
  });

  test('the upstream (Firestore) listener is cancelled when nobody listens', () async {
    final cache = StreamCache();
    // Broadcast source (what Firestore gives us).
    var cancelledB = false;
    final b = StreamController<int>.broadcast(onCancel: () => cancelledB = true);
    final sb = cache.get<int>('b', () => b.stream).listen((_) {});
    await sb.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(cancelledB, isTrue);

    // Single-subscription source: wrapped, but must not leak either.
    var cancelledS = false;
    final s = StreamController<int>(onCancel: () => cancelledS = true);
    final ss = cache.get<int>('s', () => s.stream).listen((_) {});
    await ss.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(cancelledS, isTrue);
  });
}

// Measurement: how many Firestore listeners does a screen open when it is
// rebuilt 10 times (e.g. by a filter change, keyboard, theme or parent update)?
class _Probe extends StatefulWidget {
  final bool cached;
  final void Function(VoidCallback rebuild) onReady;
  final void Function() onListenerOpened;
  const _Probe(
      {super.key,
      required this.cached,
      required this.onReady,
      required this.onListenerOpened});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final StreamCache _cache = StreamCache();

  Stream<int> _makeStream() {
    // Same shape as Firestore snapshots(): broadcast, native listener opened
    // in onListen.
    late final StreamController<int> c;
    c = StreamController<int>.broadcast(onListen: widget.onListenerOpened);
    return c.stream;
  }

  @override
  void initState() {
    super.initState();
    widget.onReady(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
        stream: widget.cached
            ? _cache.get<int>('x', _makeStream, signature: 'main|day')
            : _makeStream(),
        builder: (_, __) => const SizedBox(),
      );
}

Future<int> listenersAfterRebuilds(WidgetTester t, {required bool cached}) async {
  var opened = 0;
  late VoidCallback rebuild;
  await t.pumpWidget(MaterialApp(
      home: _Probe(
          key: UniqueKey(),
          cached: cached,
          onReady: (r) => rebuild = r,
          onListenerOpened: () => opened++)));
  for (var i = 0; i < 10; i++) {
    rebuild();
    await t.pump();
  }
  return opened;
}

void listenerMeasurement() {
  testWidgets('MEASURED: 10 rebuilds open 11 listeners without the cache, 1 with it',
      (t) async {
    final before = await listenersAfterRebuilds(t, cached: false);
    final after = await listenersAfterRebuilds(t, cached: true);
    // ignore: avoid_print
    print('listeners opened over 1 build + 10 rebuilds: '
        'without cache=$before, with cache=$after');
    expect(before, 11);
    expect(after, 1);
  });
}
