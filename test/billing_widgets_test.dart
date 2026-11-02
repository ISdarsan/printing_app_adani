import 'package:canteen_adani/print_bill_page.dart';
import 'package:canteen_adani/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {Size size = const Size(360, 640), double scale = 1}) =>
    MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child)),
    );

BillItem item(String name, int qty, double price, {String type = 'Full'}) =>
    BillItem(code: name, name: name, type: type, quantity: qty, price: price);

void main() {
  group('quantity stepper', () {
    testWidgets('shows the quantity and reports + and -', (t) async {
      var inc = 0, dec = 0;
      await t.pumpWidget(
          host(QtyStepper(value: 3, onInc: () => inc++, onDec: () => dec++)));
      expect(find.text('3'), findsOneWidget);
      await t.tap(find.byIcon(Icons.add));
      await t.tap(find.byIcon(Icons.remove));
      expect((inc, dec), (1, 1));
    });

    testWidgets('buttons are labelled for screen readers', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(
          host(QtyStepper(value: 1, onInc: () {}, onDec: () {})));
      expect(find.bySemanticsLabel('Increase quantity'), findsOneWidget);
      expect(find.bySemanticsLabel('Decrease quantity'), findsOneWidget);
      h.dispose();
    });
  });

  group('full / half price toggle', () {
    testWidgets('choosing Half then Full reports the choice', (t) async {
      final picked = <bool>[];
      await t.pumpWidget(host(PriceToggle(isFull: true, onToggle: picked.add)));
      await t.tap(find.text('Half'));
      await t.tap(find.text('Full'));
      expect(picked, [false, true]);
    });

    testWidgets('the tappable area is the full row height, not the small pill',
        (t) async {
      final picked = <bool>[];
      await t.pumpWidget(host(PriceToggle(isFull: true, onToggle: picked.add)));
      final c = t.getCenter(find.text('Half'));
      // 18 px above the text centre is outside the ~28 px pill but inside
      // the 46 px row.
      await t.tapAt(c - const Offset(0, 18));
      expect(picked, [false]);
    });
  });

  group('cart', () {
    testWidgets('empty cart explains what to do', (t) async {
      await t.pumpWidget(host(const EmptyCart()));
      expect(find.text('No items added yet'), findsOneWidget);
      expect(find.text('Search and add items above'), findsOneWidget);
    });

    testWidgets('lists items with quantity x price and the exact subtotal',
        (t) async {
      await t.pumpWidget(host(CartList(items: [
        item('Tea', 2, 10),
        item('Samosa', 3, 12.5, type: 'Half'),
      ], onRemove: (_) {})));
      expect(find.text('Tea'), findsOneWidget);
      expect(find.text('2 × ₹10.0'), findsOneWidget);
      expect(find.text('₹20.0'), findsOneWidget);
      expect(find.text('₹37.5'), findsOneWidget); // 3 x 12.5
      expect(find.text('½'), findsOneWidget); // only the half-price line
    });

    testWidgets('removing reports the index of the tapped line', (t) async {
      final removed = <int>[];
      await t.pumpWidget(host(CartList(
          items: [item('Tea', 1, 10), item('Coffee', 1, 15)],
          onRemove: removed.add)));
      await t.tap(find.byIcon(Icons.delete_outline_rounded).last);
      expect(removed, [1]);
    });

    testWidgets('remove target is at least 44 x 44 and labelled', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(
          host(CartList(items: [item('Tea', 1, 10)], onRemove: (_) {})));
      final box = t.getSize(find
          .ancestor(
              of: find.byIcon(Icons.delete_outline_rounded),
              matching: find.byType(SizedBox))
          .first);
      expect(box.width, greaterThanOrEqualTo(44));
      expect(box.height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel(RegExp('Remove Tea')), findsOneWidget);
      h.dispose();
    });

    for (final c in [
      (name: 'small phone', size: const Size(320, 480), scale: 1.0),
      (name: '200% text', size: const Size(360, 640), scale: 2.0),
      (name: 'tablet', size: const Size(900, 1200), scale: 1.0),
    ]) {
      testWidgets('cart does not overflow: ${c.name}', (t) async {
        await t.pumpWidget(host(
            CartList(items: [
              item('Special Masala Dosa with Extra Chutney and Sambar', 12,
                  1234.5,
                  type: 'Half'),
              item('Tea', 1, 10),
            ], onRemove: (_) {}),
            size: c.size,
            scale: c.scale));
        expect(t.takeException(), isNull);
      });
    }
  });

  group('payment selection and saving', () {
    Widget panel({
      String method = 'Cash',
      bool hasItems = true,
      bool saving = false,
      required void Function(String) onPay,
      required VoidCallback onSave,
    }) =>
        BillBottomPanel(
          total: 1234.5,
          paymentMethod: method,
          isSaving: saving,
          hasItems: hasItems,
          printerConnected: true,
          onPaymentChanged: onPay,
          onSave: onSave,
          onClear: () {},
        );

    testWidgets('shows the total with two decimals', (t) async {
      await t.pumpWidget(host(panel(onPay: (_) {}, onSave: () {})));
      expect(find.text('₹ 1234.50'), findsOneWidget);
    });

    testWidgets('Cash, UPI and Credit report exactly the stored mode names',
        (t) async {
      final modes = <String>[];
      await t.pumpWidget(host(panel(onPay: modes.add, onSave: () {})));
      await t.tap(find.text('Cash'));
      await t.tap(find.text('UPI'));
      await t.tap(find.text('Credit'));
      expect(modes, ['Cash', 'UPI', 'Credit']);
    });

    testWidgets('Save & Print works when there are items', (t) async {
      var saved = 0;
      await t.pumpWidget(host(panel(onPay: (_) {}, onSave: () => saved++)));
      await t.tap(find.text('Save & Print Bill'));
      expect(saved, 1);
    });

    testWidgets('Save is blocked with an empty cart', (t) async {
      var saved = 0;
      await t.pumpWidget(
          host(panel(hasItems: false, onPay: (_) {}, onSave: () => saved++)));
      await t.tap(find.text('Save & Print Bill'), warnIfMissed: false);
      expect(saved, 0);
    });

    testWidgets('Save is blocked while a save is running (no double bill)',
        (t) async {
      var saved = 0;
      await t.pumpWidget(
          host(panel(saving: true, onPay: (_) {}, onSave: () => saved++)));
      expect(find.text('Save & Print Bill'), findsNothing); // spinner instead
      await t.tap(find.byType(CircularProgressIndicator), warnIfMissed: false);
      expect(saved, 0);
    });

    testWidgets('panel does not overflow on a small phone with large text',
        (t) async {
      await t.pumpWidget(host(panel(onPay: (_) {}, onSave: () {}),
          size: const Size(320, 480), scale: 1.6));
      expect(t.takeException(), isNull);
    });
  });
}
