import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Source-level guards (same style as missing_document_reads_test.dart) for
// behaviour that is hard to reach without a live Firestore. Each one was
// confirmed to fail against the pre-fix code.
String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('cash closing form is never built against an unknown expected cash', () {
    final s = read('lib/cash_reconciliation_page.dart');
    final stats = s.indexOf('stream: _todayStatsStream');
    final guardErr = s.indexOf('statsSnap.hasError', stats);
    final guardWait =
        s.indexOf('statsSnap.connectionState == ConnectionState.waiting', stats);
    final zero = s.indexOf('double systemCash = 0.0;', stats);
    expect(stats, greaterThan(-1));
    expect(guardErr, inInclusiveRange(stats, zero),
        reason: 'an error must be handled before systemCash defaults to 0');
    expect(guardWait, inInclusiveRange(stats, zero),
        reason: 'the form must wait for the first value before defaulting to 0');
  });

  test('screens that watch Firestore do not create a new stream inside build', () {
    // `stream: _getXxx(),` directly in a StreamBuilder re-opens the listener on
    // every rebuild. These screens must go through StreamCache.
    const files = [
      'lib/admin_dashboard_page.dart',
      'lib/today_sales_page.dart',
      'lib/daily_sales_report_page.dart',
      'lib/monthly_sales_breakdown_page.dart',
      'lib/admin_monthly_cashflow_page.dart',
      'lib/funds_received_page.dart',
      'lib/admin_expense_report_page.dart',
      'lib/billing_dashboard_page.dart',
    ];
    final bare = RegExp(r'stream:\s*(_get\w+|_fundStream|_monthExpensesStream|'
        r'NotificationsPage\.unreadCountStream)\b');
    for (final f in files) {
      final src = read(f);
      expect(src, contains('StreamCache'), reason: f);
      expect(bare.hasMatch(src), isFalse,
          reason: '$f creates a stream directly in build');
    }
  });

  test('bill detail separates "failed to load" from "not found"', () {
    final s = read('lib/bill_detail_page.dart');
    final err = s.indexOf('snap.hasError');
    expect(err, greaterThan(-1), reason: 'load errors must be handled');
    expect(err, lessThan(s.indexOf('Bill not found')));
  });

  test('no screen shows a raw exception object to staff', () {
    final bad = RegExp(r"Text\(\s*'Error: \$\{?(snap|snapshot)\w*\.error");
    for (final f in Directory('lib')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      expect(bad.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });
}
