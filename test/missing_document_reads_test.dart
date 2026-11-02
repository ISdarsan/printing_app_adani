import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// B-32 regression guard.
///
/// Under the production-candidate rules a cashier is DENIED when reading a
/// document that does not exist (the rules cannot judge the branch of a missing
/// document). Reading by query is safe (an own-branch query just returns
/// nothing). This test finds every place the app reads a single document, or
/// reads inside a transaction, and requires each to be listed here with the
/// reason it is safe. A new document read fails the test until someone reviews
/// it, which is the point.
///
/// Safe categories:
///  * SELF  canteenStaff/{own uid}: the rules always allow the user to read it
///  * FUND  monthlyFunds/{month}: read rule is `activeStaff()`, not record based
///  * CTR   counters/{id}: read rule is based on the id, not on the record
///  * ADMIN screens only an admin can open (admins may read missing documents)
///  * EXISTS the document is known to exist (opened from a list of existing records)
const allowed = <String, Map<String, String>>{
  'canteen_provider.dart': {'canteenStaff': 'SELF'},
  'role_splash_page.dart': {'canteenStaff': 'SELF'},
  'connection_probe.dart': {'canteenStaff': 'SELF'},
  'billing_dashboard_page.dart': {'monthlyFunds': 'FUND'},
  'funds_received_page.dart': {'monthlyFunds': 'FUND (cashier and admin view)'},
  'admin_dashboard_page.dart': {'monthlyFunds': 'ADMIN'},
  'admin_monthly_cashflow_page.dart': {'monthlyFunds': 'ADMIN'},
  'bill_detail_page.dart': {'bills': 'EXISTS: opened from a list of existing bills'},
  'credit_detail_page.dart': {
    'creditCustomers': 'EXISTS: opened from the customer list (stream and transaction read)',
  },
  'print_bill_page.dart': {'counters': 'CTR (legacy and per-branch bill counters)'},
  'tracked_write.dart': {
    'ref.get': 'EXISTS-ISH: only after the create was refused as an update, i.e. the document exists; a failure is treated as "not confirmed"',
  },
};

class Hit {
  final String file;
  final String what;
  Hit(this.file, this.what);
  @override
  String toString() => '$file -> $what';
}

List<Hit> scan() {
  final hits = <Hit>[];
  final dir = Directory('lib');
  final collRe = RegExp(r"collection\('(\w+)'\)");
  for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    final name = f.path.split(RegExp(r'[\\/]')).last;
    final text = f.readAsStringSync().replaceAll('\r\n', '\n');
    for (final stmt in text.split(';')) {
      final s = stmt.replaceAll(RegExp(r'\s+'), ' ');
      final c = collRe.firstMatch(s)?.group(1);
      // document reference read directly: ...collection('x').doc(...).get() / .snapshots()
      if (c != null &&
          s.contains('.doc(') &&
          RegExp(r"\.doc\([^;]*\)\s*\.(get|snapshots)\(").hasMatch(s) &&
          !RegExp(r"\.doc\([^;]*\)\s*\.(set|update|delete)\(").hasMatch(s)) {
        hits.add(Hit(name, c));
      }
      // transaction reads: tx.get( / transaction.get(
      if (RegExp(r"\b(tx|transaction)\.get\(").hasMatch(s)) {
        final target = RegExp(r"\b(?:tx|transaction)\.get\(\s*([^)]*)\)").firstMatch(s)?.group(1) ?? '';
        final coll = c ??
            (target.contains('counter')
                ? 'counters'
                : target.contains('customer')
                    ? 'creditCustomers'
                    : target.contains('doc.reference') || target.contains('reference')
                        ? 'creditCustomers'
                        : target.contains('reconciliation')
                            ? 'cashReconciliations'
                            : target);
        hits.add(Hit(name, '${coll.toString()} (transaction read)'));
      }
      // generic reference .get(... Source.server) used to confirm a write
      if (name == 'tracked_write.dart' && s.contains('ref.get(')) hits.add(Hit(name, 'ref.get'));
    }
  }
  return hits;
}

void main() {
  test('every single-document or in-transaction read is reviewed and safe for cashiers', () {
    final hits = scan();
    expect(hits, isNotEmpty, reason: 'the scan must find the known reads');
    final unreviewed = <Hit>[];
    for (final h in hits) {
      final key = h.what.split(' ').first;
      final ok = allowed[h.file]?.containsKey(key) ?? false;
      if (!ok) unreviewed.add(h);
    }
    expect(unreviewed, isEmpty,
        reason: 'New document read(s) found. A cashier is denied when the document does not exist (B-32). '
            'Use an own-branch query, or review the read and add it to the allowlist with the reason: $unreviewed');
  });

  test('the dangerous reads fixed for B-32 stay gone', () {
    String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    // bill save: no tx.get of the customer or of the bill document
    final bill = read('lib/print_bill_page.dart');
    expect(bill, isNot(contains('await tx.get(customerRef)')));
    expect(bill, isNot(contains('await tx.get(billRef)')));
    // cash closing: no transaction read of the closing, queries instead
    final close = read('lib/cash_reconciliation_page.dart');
    expect(close, isNot(contains('transaction.get(reconciliationRef)')));
    expect(close, contains(".where('date', isEqualTo: _todayId)"));
    // dashboard card: a query, not the document
    final dash = read('lib/billing_dashboard_page.dart');
    expect(dash, isNot(contains('.doc(docId)\n          .snapshots()')));
  });

  test('every collection the app reads for a cashier is filtered by canteenId (no unscoped cashier reads)', () {
    // The cashier-facing screens must scope with canteenId or CanteenProvider.scopeQuery.
    const cashierFiles = [
      'billing_dashboard_page.dart', 'today_sales_page.dart', 'daily_sales_report_page.dart',
      'all_bills_page.dart', 'monthly_sales_breakdown_page.dart', 'funds_received_page.dart',
      'credit_customers_page.dart', 'menu_view_page.dart', 'cash_reconciliation_page.dart',
      'notifications_page.dart',
    ];
    for (final f in cashierFiles) {
      final src = File('lib/$f').readAsStringSync();
      expect(src.contains('canteenId') || src.contains('scopeQuery'), isTrue, reason: f);
    }
  });
}
