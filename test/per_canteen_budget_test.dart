import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Business decision (2026-11-02): monthly budgets are assigned PER CANTEEN.
/// There is no organisation-wide amount. These screens need Firestore to render,
/// so the wiring is guarded at source level (the same style as the other
/// source guards); the pure maths is in fund_budget_test.dart and the access
/// rules are in security-tests/candidate-rules.test.mjs.
void main() {
  String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
  final libFiles = Directory('lib')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('nothing in the app still treats the monthly fund as shared by all canteens', () {
    for (final f in libFiles) {
      final src = f.readAsStringSync();
      expect(src.contains('kSharedFundNote'), isFalse, reason: f.path);
      expect(src.contains('shared by all canteens'), isFalse, reason: f.path);
      expect(src.contains('Organisation Fund'), isFalse, reason: f.path);
      expect(src.contains('organisation-wide fund'), isFalse, reason: f.path);
    }
  });

  test('no screen reads or writes a month-only fund document (the old shared fund)', () {
    // `.collection('monthlyFunds').doc(monthId)` addressed the shared fund.
    final oldStyle = RegExp(r"collection\('monthlyFunds'\)\s*\.doc\((_?monthId)\)");
    for (final f in libFiles) {
      expect(oldStyle.hasMatch(f.readAsStringSync()), isFalse,
          reason: '${f.path} addresses the shared (month-only) fund document');
    }
  });

  test('every place that touches one budget document uses the canteen-specific id', () {
    for (final f in [
      'lib/funds_received_page.dart',
      'lib/billing_dashboard_page.dart',
      'lib/admin_monthly_cashflow_page.dart',
      'lib/admin_expense_report_page.dart',
    ]) {
      expect(read(f), contains('monthlyFundDocId('), reason: f);
    }
  });

  test('budget writes carry the canteen and month so the document and the rules agree', () {
    for (final f in [
      'lib/funds_received_page.dart',
      'lib/admin_expense_report_page.dart',
      'lib/admin_monthly_cashflow_page.dart',
    ]) {
      final s = read(f);
      expect(s, contains("'canteenId':"), reason: f);
      expect(s, contains("'monthYear':"), reason: f);
      expect(s, contains("'fundAmount':"), reason: f);
    }
  });

  test('cashier fund screen reads THIS canteen only and shows no shared-fund note', () {
    final s = read('lib/funds_received_page.dart');
    expect(s, contains('monthlyFundDocId(CanteenProvider.selectedCanteenId, _monthId)'));
    expect(s.contains('shared-fund-note'), isFalse);
    expect(s, contains("'Allocated Budget'"));
    expect(s, contains("'Total Spent'"));
    expect(s, contains("'Available Balance'"));
  });

  test('cashier budget alert compares THIS canteen with its own budget', () {
    final s = read('lib/billing_dashboard_page.dart');
    expect(s, contains('CanteenBudget.of('));
    expect(s, contains('budget.needsAlert'));
    expect(s, contains('Monthly budget exceeded'));
  });

  test('admin dashboard alert judges each canteen against its own budget', () {
    final s = read('lib/admin_dashboard_page.dart');
    expect(s, contains('budgetsNeedingAlert('));
    expect(s, contains("where('monthYear', isEqualTo: monthId)"));
  });

  test('admin can only set a budget for one chosen canteen (not for "all")', () {
    final s = read('lib/admin_expense_report_page.dart');
    expect(s, contains('Choose a canteen above to set its monthly budget.'));
    expect(s, contains('_updateFund(\n                          canteen.id'));
  });

  test('Add Item: the delete action is admin-only in the app', () {
    final src = read('lib/add_item_page.dart');
    expect(src, contains('if (CanteenProvider.isAdmin) ...['));
    expect(src, contains('if (!CanteenProvider.isAdmin) return; // admin-only action'));
  });
}
