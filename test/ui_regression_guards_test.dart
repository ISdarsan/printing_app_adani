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
      final src = f.readAsStringSync();
      expect(bad.hasMatch(src), isFalse, reason: f.path);
      // also `Text('... $_error')` style output of a stored error object
      expect(RegExp(r"Text\('[^']*\$_error").hasMatch(src), isFalse,
          reason: '${f.path} prints a raw error object');
    }
  });

  test('no screen prints a raw error object or exception (outside debug logs)', () {
    final raw = RegExp(r"\$\{?(snap|snapshot|\w*[sS]nap|op)\.error\}?|\$e'|\$\{e\}");
    for (final f in Directory('lib')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      var n = 0;
      for (final line in f.readAsLinesSync()) {
        n++;
        final t = line.trimLeft();
        // debug logs: debugPrint(...) or a wrapped log string starting '[Tag]
        if (t.startsWith('//') ||
            t.startsWith("'[") ||
            t.contains('debugPrint(') ||
            t.contains('print(')) {
          continue;
        }
        expect(raw.hasMatch(line), isFalse,
            reason: '${f.path}:$n shows a raw error to the user: ${line.trim()}');
      }
    }
  });

  test('list/report pages never hand Firestore a new stream from build()', () {
    // admin_dashboard_page: its remaining inline streams are small
    // whole-collection lists inside dialogs/sheets (documented in
    // PERFORMANCE_AUDIT.md).
    final direct = RegExp(r'stream:\s*(FirebaseFirestore|_stream\b|CanteenProvider\.scopeQuery)');
    for (final f in Directory('lib')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_page.dart'))) {
      if (f.path.endsWith('admin_dashboard_page.dart')) continue;
      expect(direct.hasMatch(f.readAsStringSync()), isFalse,
          reason: '${f.path} opens a Firestore listener inside build()');
    }
  });

  test('money cards show a dash, never a made-up zero, while loading or on error', () {
    final s = read('lib/admin_dashboard_page.dart');
    expect(s.contains("?? '0'"), isFalse);
    expect(s.contains("String sales = '₹0'"), isFalse);
  });

  test('stream errors on the dashboard chart and recent bills are not shown as "empty"', () {
    final s = read('lib/admin_dashboard_page.dart');
    final weekly = s.indexOf("_cached('weekly'");
    final weeklyErr = s.indexOf('snapshot.hasError', weekly);
    expect(weeklyErr, greaterThan(-1), reason: 'chart must handle errors');
    expect(weeklyErr, lessThan(s.indexOf('No trends data available yet')));
    final recent = s.indexOf("_cached('recent'");
    final recentErr = s.indexOf('snapshot.hasError', recent);
    expect(recentErr, greaterThan(-1), reason: 'recent bills must handle errors');
    expect(recentErr, lessThan(s.indexOf('No recent bills recorded.')));
  });

  test('loading states in builders use the shared AppLoading (it explains a slow connection)', () {
    final bare = RegExp(r'return (const )?Center\(\s*child:\s*(Padding\([^)]*child:\s*)?CircularProgressIndicator');
    for (final f in Directory('lib')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('state_views.dart')) continue;
      expect(bare.hasMatch(f.readAsStringSync()), isFalse,
          reason: '${f.path} has a bare spinner as a loading state');
    }
  });
}
