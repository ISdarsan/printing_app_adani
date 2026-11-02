import 'dart:io';

import 'package:canteen_adani/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// Business decision: the monthly fund stays organisation-wide and cashier
/// screens must say so. These screens need Firestore to render, so the wording
/// is guarded at source level (the strings must stay wired to the cashier path).
void main() {
  String read(String p) => File(p).readAsStringSync();

  test('the shared-fund note says it is organisation-wide and canteen-only spending', () {
    expect(kSharedFundNote, contains('shared by all canteens'));
    expect(kSharedFundNote, contains('this canteen'));
    expect(kSharedFundNote, contains('not the organisation'));
  });

  test('Funds Received: cashier labels are explicit, admin labels unchanged', () {
    final src = read('lib/funds_received_page.dart');
    expect(src, contains("widget.isAdmin ? 'Allocated Fund' : 'Organisation Fund'"));
    expect(src, contains("widget.isAdmin ? 'Total Spent' : 'Spent by this canteen'"));
    expect(src, contains("widget.isAdmin ? 'Monthly Budget Console' : 'Organisation Fund (shared by all canteens)'"));
    expect(src, contains("Fund minus this canteen"));
    // the note is shown to cashiers only
    expect(src, contains('if (!widget.isAdmin)'));
    expect(src, contains('kSharedFundNote'));
  });

  test('Cashier dashboard alert no longer claims the fund is this canteen\'s budget', () {
    final src = read('lib/billing_dashboard_page.dart');
    expect(src, contains('Shared fund exceeded by this canteen alone'));
    expect(src, contains('organisation-wide fund'));
    expect(src, isNot(contains("'Budget Overspent!'")));
    expect(src, isNot(contains("Low Budget Alert (")));
  });

  test('Add Item: the delete action is admin-only in the app', () {
    final src = read('lib/add_item_page.dart');
    expect(src, contains('if (CanteenProvider.isAdmin) ...['));
    expect(src, contains('if (!CanteenProvider.isAdmin) return; // admin-only action'));
  });
}
