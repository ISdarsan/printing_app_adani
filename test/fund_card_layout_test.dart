import 'package:canteen_adani/funds_received_page.dart';
import 'package:canteen_adani/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fonts.dart';

// Regression: on a real phone the cashier fund card showed
// "RIGHT OVERFLOWED BY 68 PIXELS" and its three labels ran together.
Widget host(Widget child, {Size size = const Size(360, 800), double scale = 1}) =>
    MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        // Constrain the REAL layout to the requested size. MediaQuery alone only
        // changes the reported size, not the width the widgets are laid out in.
        builder: (ctx, c) => Center(
            child: SizedBox(width: size.width, height: size.height, child: c)),
        theme: buildAppTheme(),
        // the page wraps the card in Padding(all: 16)
        home: Scaffold(
            body: SingleChildScrollView(
                child: Padding(padding: const EdgeInsets.all(16), child: child))),
      ),
    );

FundSummaryCard card({bool admin = false, String amount = '₹0', bool negative = false}) =>
    FundSummaryCard(
      isAdmin: admin,
      monthLabel: 'November 2026',
      allocatedStr: amount,
      spentStr: amount,
      availableStr: amount,
      isNegative: negative,
      lastUpdated: 'Not set yet',
    );

void main() {
  setUpAll(loadInterFont);

  final cases = [
    (name: 'phone 360 wide (the reported screen)', size: const Size(360, 800), scale: 1.0),
    (name: 'small phone 320 wide', size: const Size(320, 568), scale: 1.0),
    (name: 'small phone, 150% text', size: const Size(320, 568), scale: 1.5),
    (name: 'phone, 200% text', size: const Size(360, 800), scale: 2.0),
    (name: 'tablet', size: const Size(900, 1200), scale: 1.0),
  ];
  for (final admin in [false, true]) {
    for (final c in cases) {
      testWidgets('${admin ? 'admin' : 'cashier'} card does not overflow: ${c.name}', (t) async {
        await t.pumpWidget(host(card(admin: admin), size: c.size, scale: c.scale));
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('large amounts shrink to fit instead of overflowing', (t) async {
    await t.pumpWidget(host(card(amount: '₹12,34,56,789'), size: const Size(320, 568)));
    expect(t.takeException(), isNull);
    await t.pumpWidget(host(card(amount: '-₹12,34,56,789', negative: true), size: const Size(320, 568), scale: 1.5));
    expect(t.takeException(), isNull);
  });

  testWidgets('cashier labels are all shown, each in its own column', (t) async {
    await t.pumpWidget(host(card()));
    expect(find.text('Organisation Fund'), findsOneWidget);
    expect(find.text('Spent by this canteen'), findsOneWidget);
    expect(find.text("Fund minus this canteen's spending"), findsOneWidget);
    // three separate label boxes that do not overlap horizontally
    final r = [
      t.getRect(find.text('Organisation Fund')),
      t.getRect(find.text('Spent by this canteen')),
      t.getRect(find.text("Fund minus this canteen's spending")),
    ];
    expect(r[0].right, lessThanOrEqualTo(r[1].left + 0.5));
    expect(r[1].right, lessThanOrEqualTo(r[2].left + 0.5));
  });

  testWidgets('admin labels are unchanged and the Edit chip shows', (t) async {
    await t.pumpWidget(host(card(admin: true)));
    expect(find.text('Allocated Fund'), findsOneWidget);
    expect(find.text('Total Spent'), findsOneWidget);
    expect(find.text('Available Balance'), findsOneWidget);
    expect(find.text('Monthly Budget Console'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('cashiers do not see the Edit chip', (t) async {
    await t.pumpWidget(host(card()));
    expect(find.text('Edit'), findsNothing);
  });
}
