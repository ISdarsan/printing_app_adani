import 'package:canteen_adani/canteen_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fonts.dart';

Widget host(Widget child, {Size size = const Size(360, 640), double scale = 1}) => MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        builder: (c, w) => Center(child: SizedBox(width: size.width, height: size.height, child: w)),
        home: Scaffold(body: Column(children: [child])),
      ),
    );

void main() {
  setUpAll(loadInterFont);

  group('buildCanteenChoices', () {
    test('All first, then Main, then the others sorted by name, main never twice', () {
      final c = buildCanteenChoices([
        const MapEntry('zeta_cafe', {'name': 'Zeta Cafe'}),
        const MapEntry('main', {'name': 'Main Canteen'}),
        const MapEntry('alpha', {'name': 'alpha block'}),
      ]);
      expect(c.map((x) => x.id), ['all', 'main', 'alpha', 'zeta_cafe']);
      expect(c.where((x) => x.id == 'main').length, 1);
    });

    test('without "All" the list starts at Main', () {
      final c = buildCanteenChoices(const [], all: false);
      expect(c.map((x) => x.id), ['main']);
    });

    test('a canteen with no name uses its id', () {
      final c = buildCanteenChoices([const MapEntry('north', <String, dynamic>{})]);
      expect(c.last, const CanteenChoice('north', 'north'));
    });
  });

  group('CanteenSelector', () {
    // a fresh single-use stream per test
    Stream<List<CanteenChoice>> fresh() => Stream.value(buildCanteenChoices([
          const MapEntry('north', {'name': 'North Canteen'}),
          const MapEntry('south', {'name': 'South Canteen'}),
        ]));

    testWidgets('shows the current choice and reports a new one', (t) async {
      CanteenChoice? picked;
      await t.pumpWidget(host(CanteenSelector(
        value: kAllCanteens,
        choicesStream: fresh(),
        onChanged: (c) => picked = c,
      )));
      await t.pump();
      expect(find.text('All canteens'), findsOneWidget);
      await t.tap(find.byType(DropdownButton<String>));
      await t.pumpAndSettle();
      expect(find.text('North Canteen'), findsOneWidget);
      expect(find.text('South Canteen'), findsOneWidget);
      await t.tap(find.text('North Canteen').last);
      await t.pumpAndSettle();
      expect(picked, const CanteenChoice('north', 'North Canteen'));
      expect(picked!.isAll, isFalse);
    });

    testWidgets('an unknown current value falls back to the first choice instead of crashing', (t) async {
      await t.pumpWidget(host(CanteenSelector(
        value: 'deleted_canteen',
        choicesStream: fresh(),
        onChanged: (_) {},
      )));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('All canteens'), findsOneWidget);
    });

    testWidgets('while loading it still offers All and Main (never an empty control)', (t) async {
      await t.pumpWidget(host(CanteenSelector(
        value: kAllCanteens,
        choicesStream: const Stream.empty(),
        onChanged: (_) {},
      )));
      await t.pump();
      expect(find.text('All canteens'), findsOneWidget);
    });

    for (final c in [
      (name: 'small phone', size: const Size(320, 480), scale: 1.0),
      (name: '200% text', size: const Size(360, 640), scale: 2.0),
    ]) {
      testWidgets('no overflow with a long canteen name: ${c.name}', (t) async {
        final long = Stream.value(buildCanteenChoices([
          const MapEntry('x', {'name': 'The Very Long Named Corporate Canteen Block B Third Floor'}),
        ]));
        await t.pumpWidget(host(
            CanteenSelector(value: 'x', choicesStream: long, onChanged: (_) {}),
            size: c.size,
            scale: c.scale));
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('ChooseCanteenPrompt', () {
    testWidgets('tells the admin to choose a canteen', (t) async {
      await t.pumpWidget(host(const Expanded(
          child: ChooseCanteenPrompt(message: 'Select a canteen above to view and edit its menu.'))));
      expect(find.text('Choose a canteen'), findsOneWidget);
      expect(find.textContaining('view and edit its menu'), findsOneWidget);
    });
  });
}
