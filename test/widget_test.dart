import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:canteen_adani/admin_expense_report_page.dart';
import 'package:canteen_adani/main.dart';
import 'package:canteen_adani/print_bill_page.dart';
import 'package:canteen_adani/canteen_provider.dart';

void main() {
  group('Canteen-scoped document IDs', () {
    test('creates separate daily stats and closing IDs per canteen', () {
      // Fixed instant (11:30 IST on 4 Oct) so the test does not depend on the
      // timezone of the machine running it.
      final date = DateTime.utc(2026, 10, 4, 6, 0);

      expect(
        CanteenProvider.dailyStatsDocumentId(date, canteenId: 'main'),
        'main_2026-10-04',
      );
      expect(
        CanteenProvider.dailyStatsDocumentId(date, canteenId: 'branch_2'),
        'branch_2_2026-10-04',
      );
      expect(
        CanteenProvider.cashReconciliationDocumentId(date, canteenId: 'main'),
        'main_2026-10-04',
      );
    });

    test('creates separate credit accounts for the same phone per canteen', () {
      expect(
        CanteenProvider.creditCustomerDocumentId(' 5551234 ',
            canteenId: 'main'),
        'main_5551234',
      );
      expect(
        CanteenProvider.creditCustomerDocumentId('5551234',
            canteenId: 'branch_2'),
        'branch_2_5551234',
      );
    });

    test('extracts date suffixes while supporting legacy date-only IDs', () {
      expect(
        CanteenProvider.dateFromDailyStatsDocumentId('branch_2_2026-10-04'),
        '2026-10-04',
      );
      expect(
        CanteenProvider.dateFromDailyStatsDocumentId('2026-10-04'),
        '2026-10-04',
      );
    });

    test('treats untagged records as Main only', () {
      CanteenProvider.setSelectedCanteen(id: 'branch_2', name: 'Branch 2');
      expect(CanteenProvider.matchesSelectedCanteen({}), isFalse);
      expect(
        CanteenProvider.matchesSelectedCanteen({'canteenId': 'branch_2'}),
        isTrue,
      );

      CanteenProvider.setSelectedCanteen(id: 'main', name: 'Main Canteen');
      expect(CanteenProvider.matchesSelectedCanteen({}), isTrue);
      expect(
        CanteenProvider.matchesSelectedCanteen({'canteenId': 'branch_2'}),
        isFalse,
      );
    });

    test('keeps legacy notifications in Main and scopes new notifications', () {
      CanteenProvider.setSelectedCanteen(id: 'branch_2', name: 'Branch 2');
      expect(
        CanteenProvider.matchesNotificationCanteen({'title': 'Old notice'}),
        isFalse,
      );
      expect(
        CanteenProvider.matchesNotificationCanteen({'canteenId': 'branch_2'}),
        isTrue,
      );
      expect(
        CanteenProvider.matchesNotificationCanteen({'canteenId': 'main'}),
        isFalse,
      );

      CanteenProvider.setSelectedCanteen(id: 'main', name: 'Main Canteen');
      expect(
        CanteenProvider.matchesNotificationCanteen({'title': 'Old notice'}),
        isTrue,
      );
    });
  });

  group('Bill item helpers', () {
    test('normalizes null or invalid quantities to 1', () {
      expect(normalizeBillQuantity(null), 1);
      expect(normalizeBillQuantity(''), 1);
      expect(normalizeBillQuantity('0'), 1);
      expect(normalizeBillQuantity(-1), 1);
      expect(normalizeBillQuantity(3), 3);
    });

    test('merges duplicate bill items with the same code and type', () {
      final items = [
        BillItem(
            code: 'B1',
            name: 'Chicken Biryani',
            type: 'Full',
            quantity: 1,
            price: 120),
        BillItem(
            code: 'B1',
            name: 'Chicken Biryani',
            type: 'Full',
            quantity: 2,
            price: 120),
        BillItem(
            code: 'B1',
            name: 'Chicken Biryani',
            type: 'Half',
            quantity: 1,
            price: 70),
      ];

      final merged = mergeBillItems(items);

      expect(merged.length, 2);
      expect(merged.first.quantity, 3);
      expect(merged.where((item) => item.type == 'Half').single.quantity, 1);
    });
  });

  group('Receipt formatting', () {
    test('buildReceiptText includes bill summary and totals', () {
      final items = [
        BillItem(code: 'B1', name: 'Tea', type: 'Full', quantity: 2, price: 20),
        BillItem(
            code: 'C2', name: 'Sandwich', type: 'Full', quantity: 1, price: 80),
      ];

      final text = buildReceiptText(
        billNumber: 125,
        items: items,
        totalAmount: 120,
        paymentMode: 'Cash',
        canteenName: 'Main Canteen',
        customerName: null,
        customerPhone: null,
      );

      expect(text, contains('MAIN CANTEEN'));
      expect(text, contains('BILL #125'));
      expect(text, contains('Tea'));
      expect(text, contains('TOTAL'));
      expect(text, contains('₹120.00'));
      expect(text, contains('Cash'));
    });
  });

  group('App routing', () {
    testWidgets('admin expense route opens the expense report page',
        (tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final routes = materialApp.routes ?? const <String, WidgetBuilder>{};
      final builder = routes['/admin_expense_report'];

      expect(builder, isNotNull);
      final page = builder!(tester.element(find.byType(MaterialApp)));
      expect(page, isA<AdminExpenseReportPage>());
    });
  });
}
