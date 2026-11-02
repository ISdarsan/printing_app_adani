import 'dart:io';

import 'package:canteen_adani/canteen_provider.dart';
import 'package:canteen_adani/credit_ledger_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// Admin "choose a canteen" behaviour on Manage Menu, Master Credit Ledger,
/// Cash Reconciliation Logs and Analytics, plus the pure logic behind them.
void main() {
  String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

  group('CanteenProvider.matchesCanteen (any canteen, not only the signed-in one)', () {
    test('records without a canteen id belong to main', () {
      expect(CanteenProvider.matchesCanteen(<String, dynamic>{}, 'main'), isTrue);
      expect(CanteenProvider.matchesCanteen({'canteenId': ''}, 'main'), isTrue);
      expect(CanteenProvider.matchesCanteen(<String, dynamic>{}, 'north'), isFalse);
    });
    test('a record matches only its own canteen', () {
      expect(CanteenProvider.matchesCanteen({'canteenId': 'north'}, 'north'), isTrue);
      expect(CanteenProvider.matchesCanteen({'canteenId': 'north'}, 'south'), isFalse);
      expect(CanteenProvider.matchesCanteen({'canteenId': 'north'}, 'main'), isFalse);
      expect(CanteenProvider.matchesCanteen({'canteenId': 'main'}, 'north'), isFalse);
    });
    test('the signed-in canteen helper still behaves as before', () {
      CanteenProvider.applyStaffData({'role': 'cashier', 'canteenId': 'north', 'canteenName': 'North'});
      expect(CanteenProvider.matchesSelectedCanteen({'canteenId': 'north'}), isTrue);
      expect(CanteenProvider.matchesSelectedCanteen({'canteenId': 'south'}), isFalse);
      expect(CanteenProvider.matchesSelectedCanteen(<String, dynamic>{}), isFalse);
      CanteenProvider.applyStaffData({'role': 'cashier', 'canteenId': 'main'});
      expect(CanteenProvider.matchesSelectedCanteen(<String, dynamic>{}), isTrue);
    });
  });

  group('credit ledger totals', () {
    test('only unpaid bills are due; a missing pending amount means the whole total', () {
      final bills = [
        {'totalAmount': 100.0, 'pendingAmount': 40.5, 'creditStatus': 'Pending'},
        {'totalAmount': 80.0}, // no pendingAmount: all 80 due
        {'totalAmount': 60.0, 'pendingAmount': 0.0, 'creditStatus': 'Paid'},
        {'totalAmount': 70.0, 'pendingAmount': 0.0}, // zero pending counts as paid
        {'totalAmount': 90.0, 'pendingAmount': 90.0, 'creditStatus': 'Paid'}, // status wins
      ];
      expect(creditDuePaise(bills), 12050);
      expect(creditBillIsPaid(bills[2]), isTrue);
      expect(creditBillIsPaid(bills[3]), isTrue);
      expect(creditBillIsPaid(bills[1]), isFalse);
    });
    test('many odd amounts add up exactly (no floating-point drift)', () {
      final bills = List.generate(1000, (_) => {'totalAmount': 0.1, 'pendingAmount': 0.1});
      expect(creditDuePaise(bills), 10000); // exactly Rs 100.00
    });
    test('no bills: nothing due', () {
      expect(creditDuePaise(const []), 0);
    });
  });

  group('screens (source guards, confirmed to fail on the code before this change)', () {
    test('Manage Menu: an admin works on one chosen canteen; "All" asks to choose one', () {
      final s = read('lib/add_item_page.dart');
      expect(s, contains('CanteenSelector('));
      expect(s, contains('String? get _canteenId'));
      expect(s, contains('_canteenId == null\n                    ? _choosePrompt()'));
      expect(s, contains('Select a canteen above to view and edit its menu.'));
      // saving uses the chosen canteen, not the admin's own
      expect(s, contains("'canteenId': canteenId"));
      expect(s.contains("final canteenId = CanteenProvider.selectedCanteenId;"), isFalse);
      expect(s, contains("Choose a canteen first."));
      // a half-edited item is never carried into another canteen
      expect(s, contains('_clearForm();\n    _searchController.clear();'));
    });

    test('Manage Menu: cashiers stay on their own canteen and cannot delete', () {
      final s = read('lib/add_item_page.dart');
      expect(s, contains('CanteenProvider.selectedCanteenId;\n'));
      expect(s, contains('if (!CanteenProvider.isAdmin) return; // admin-only action'));
      expect(s, contains('if (_isAdmin)\n            CanteenSelector('));
    });

    test('Master Credit Ledger: canteen chooser with All, canteen shown on each bill, total due', () {
      final s = read('lib/admin_master_credit_ledger_page.dart');
      expect(s, contains('CanteenSelector('));
      expect(s, contains("q = q.where('canteenId', isEqualTo: _canteen);"));
      expect(s, contains('signature: _canteen'));
      expect(s, contains('creditDuePaise('));
      expect(s, contains("still due"));
    });

    test('Cash Reconciliation: admin logs have a canteen filter and show the canteen; closing handles midnight', () {
      final s = read('lib/cash_reconciliation_page.dart');
      expect(s, contains('CanteenSelector('));
      expect(s, contains("historyQuery.where('canteenId', isEqualTo: _adminCanteen)"));
      expect(s, contains('closingDayChanged('));
      expect(s, contains('_dayWatch'));
      expect(s, contains('closingChipText(discrepancy)'));
      expect(s, contains('closingDay(data[\'date\'], docs[i].id)'));
      // the crash and the rounding of the old admin log
      expect(s.contains("DateFormat('yyyy-MM-dd').parse(dateStr)"), isFalse);
      expect(s.contains("discrepancy.abs().toStringAsFixed(0)"), isFalse);
    });

    test('Analytics: canteen chooser, and the loader is told which canteen (not always the admin\'s own)', () {
      final page = read('lib/admin_analytics_page.dart');
      final loader = read('lib/analytics_loader.dart');
      expect(page, contains('CanteenSelector('));
      expect(page, contains('canteenId: canteenId'));
      expect(loader, contains('String? canteenId'));
      expect(loader, contains('inScope(data)'));
      expect(loader.contains('CanteenProvider.matchesSelectedCanteen(data)'), isFalse);
    });

    test('Monthly Budget (admin): explains that budgets are set per canteen when All is selected', () {
      final s = read('lib/admin_expense_report_page.dart');
      expect(s, contains('Budgets are set per canteen. Choose a canteen above'));
      expect(s, contains('Choose a canteen above to set its monthly budget.'));
    });

    test('SMS Broadcast shows Coming soon for both roles', () {
      for (final f in ['lib/admin_dashboard_page.dart', 'lib/billing_dashboard_page.dart']) {
        final s = read(f);
        expect(s, contains("showComingSoonDialog(context, feature: 'SMS Broadcast Specials')"), reason: f);
        expect(s.contains('showSMSBroadcastDialog'), isFalse, reason: f);
      }
    });
  });
}
