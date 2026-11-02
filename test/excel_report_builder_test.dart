import 'dart:convert';
import 'dart:io';

import 'package:canteen_adani/excel_report_builder.dart';
import 'package:canteen_adani/report_records.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter_test/flutter_test.dart';

/// Synthetic data only. No production data is used anywhere.
DateTime ist(int y, int m, int d, int h, int mi, [int s = 0]) =>
    DateTime.utc(y, m, d, h, mi, s).subtract(const Duration(hours: 5, minutes: 30));

const northName = 'North: Block/A [Annex] Campus Canteen Long Name';

Map<String, dynamic> bill(int n, String? canteen, String mode, double amt,
        DateTime ts,
        {String? cust, String? phone, List<Map<String, dynamic>>? items}) =>
    {
      'billNumber': n,
      if (canteen != null) 'canteenId': canteen,
      'paymentMode': mode,
      'totalAmount': amt,
      'timestamp': ts,
      if (cust != null) 'customerName': cust,
      if (phone != null) 'customerPhone': phone,
      'items': items ?? [
        {'name': 'Tea', 'quantity': 2},
        {'name': 'Samosa', 'quantity': 1},
      ],
    };

final rawBills = <Map<String, dynamic>>[
  bill(1, 'main', 'Cash', 500, ist(2026, 10, 31, 23, 59, 59)), // last second of Oct
  bill(2, 'main', 'Cash', 300, ist(2026, 11, 1, 0, 0, 0)), // first second of Nov
  bill(3, null, 'UPI', 400, ist(2026, 11, 1, 9, 15)), // legacy: no canteenId => main
  bill(4, 'main', 'Credit', 200, ist(2026, 11, 1, 12, 0),
      cust: 'Ravi', phone: '9000000001'),
  bill(5, 'main', 'Credit', 300, ist(2026, 11, 1, 13, 0),
      cust: 'Ravi', phone: '9000000001'),
  bill(6, 'north', 'Cash', 150.5, ist(2026, 11, 1, 10, 0),
      items: [{'name': 'Tea', 'quantity': 3}, {'name': 'Vada', 'quantity': '4'}]),
  bill(7, 'north', 'UPI', 250.25, ist(2026, 11, 1, 11, 0)),
  bill(8, 'north', 'Credit', 100, ist(2026, 11, 1, 14, 0),
      cust: 'Meena', phone: '9000000002'),
];

final rawExpenses = <Map<String, dynamic>>[
  {'timestamp': ist(2026, 11, 1, 8, 0), 'canteenId': 'main', 'description': 'Vegetables', 'amount': 120.0, 'proofImageBase64': 'AAAA'},
  {'timestamp': ist(2026, 11, 1, 8, 30), 'canteenId': 'north', 'description': 'Gas', 'amount': 80.75},
  {'timestamp': ist(2026, 11, 1, 9, 0), 'description': 'Legacy untagged', 'amount': 50.0},
];

final rawRepayments = <Map<String, dynamic>>[
  {'timestamp': ist(2026, 11, 1, 16, 0), 'canteenId': 'main', 'customerName': 'Ravi', 'customerPhone': '9000000001', 'paymentMode': 'Cash', 'amount': 250.0, 'processedBy': 'a@x.com'},
  {'timestamp': ist(2026, 11, 1, 17, 0), 'canteenId': 'main', 'customerName': 'Ravi', 'customerPhone': '9000000001', 'paymentMode': 'UPI', 'amount': 100.0, 'processedBy': 'a@x.com'},
  {'timestamp': ist(2026, 11, 1, 18, 0), 'canteenId': 'north', 'customerName': 'Meena', 'customerPhone': '9000000002', 'paymentMode': 'Cash', 'amount': 40.0, 'processedBy': 'b@x.com'},
];

final rawCredits = <Map<String, dynamic>>[
  {'canteenId': 'main', 'name': 'Ravi', 'phone': '9000000001', 'totalPending': 150.0}, // 500-350
  {'canteenId': 'north', 'name': 'Meena', 'phone': '9000000002', 'totalPending': 60.0}, // 100-40
];

final rawRecons = <Map<String, dynamic>>[
  {'timestamp': ist(2026, 11, 1, 20, 0), 'canteenId': 'main', 'date': '2026-11-01', 'systemCash': 1050.0, 'actualCash': 1000.0, 'discrepancy': -50.0, 'submittedBy': 'a@x.com', 'note': 'short'},
  {'timestamp': ist(2026, 11, 1, 20, 5), 'canteenId': 'north', 'date': '2026-11-01', 'systemCash': 190.5, 'actualCash': 190.5, 'discrepancy': 0.0, 'submittedBy': 'b@x.com', 'note': ''},
];

ReportData buildData() {
  final top = <String, int>{};
  for (final b in rawBills) {
    accumulateTopItems(top, b['items']);
  }
  return ReportData(
    bills: [for (final m in rawBills) BillRow.fromMap(m)],
    expenses: [for (final m in rawExpenses) ExpenseRow.fromMap(m)],
    credits: [for (final m in rawCredits) CreditRow.fromMap(m)],
    repayments: [for (final m in rawRepayments) RepaymentRow.fromMap(m)],
    recons: [for (final m in rawRecons) ReconRow.fromMap(m)],
    topItems: top,
    canteenNames: const {'main': 'Main Canteen', 'north': northName},
    periodLabel: 'Synthetic test data',
  );
}

Object? _jsonSafe(Object? v) => v is DateTime ? v.toUtc().toIso8601String() : v;

String cellText(Sheet s, int c, int r) =>
    s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value
        ?.toString() ??
    '';

double cellNum(Sheet s, int c, int r) {
  final v = s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value;
  if (v is DoubleCellValue) return v.value;
  if (v is IntCellValue) return v.value.toDouble();
  throw StateError('not numeric at $c,$r: $v');
}

void main() {
  late List<int> bytes;
  late Excel decoded;
  final data = buildData();

  setUpAll(() {
    final excel = ExcelReportBuilder.build(data,
        generatedAt: DateTime.utc(2026, 11, 2, 4, 0)); // 09:30 IST
    bytes = excel.encode()!;
    decoded = Excel.decodeBytes(bytes);

    // Persist for the independent Python/openpyxl validation.
    final dir = Directory('build/validation')..createSync(recursive: true);
    File('${dir.path}/synthetic_report.xlsx').writeAsBytesSync(bytes);
    File('${dir.path}/synthetic_source.json').writeAsStringSync(jsonEncode({
      'bills': rawBills,
      'expenses': rawExpenses,
      'repayments': rawRepayments,
      'credits': rawCredits,
      'recons': rawRecons,
      'canteenNames': data.canteenNames,
    }, toEncodable: _jsonSafe));
  });

  test('a real xlsx file is produced and can be decoded again', () {
    expect(bytes.length, greaterThan(2000));
    expect(bytes[0], 0x50); // 'P' of the PK zip header
    expect(bytes[1], 0x4B);
    expect(decoded.tables.isNotEmpty, isTrue);
  });

  test('every expected worksheet exists, in the original order', () {
    final names = decoded.tables.keys.toList();
    expect(names.first, 'Dashboard Summary');
    expect(names[1], 'All Bills');
    for (final n in [
      'All Expenses',
      'Credit Accounts',
      'Repayment Logs',
      'Cash Reconciliations',
      'Top Selling Items',
    ]) {
      expect(names, contains(n));
    }
    // Per-branch sheets: main, north (name sanitised + truncated, <= 31).
    final branchBills = names.where((n) => n.endsWith(' Bills') && n != 'All Bills');
    final branchExp = names.where((n) => n.endsWith(' Expenses') && n != 'All Expenses');
    expect(branchBills.length, 2);
    expect(branchExp.length, 2);
    expect(names, contains('Main Canteen Bills'));
    expect(names, contains('Main Canteen Expenses'));
    for (final n in names) {
      expect(n.length, lessThanOrEqualTo(31), reason: n);
      expect(RegExp(r'[:\\/?*\[\]]').hasMatch(n), isFalse, reason: n);
    }
    expect(names.toSet().length, names.length);
  });

  test('existing columns are preserved in position and text', () {
    final bills = decoded['All Bills'];
    const expected = [
      'Date & Time', 'Bill Number', 'Canteen Branch', 'Customer Name',
      'Customer Phone', 'Payment Mode', 'Total Amount (INR)'
    ];
    for (var i = 0; i < expected.length; i++) {
      expect(cellText(bills, i, 0), expected[i]);
    }
    expect([for (var i = 0; i < 4; i++) cellText(decoded['All Expenses'], i, 0)],
        ['Date & Time', 'Canteen Branch', 'Description', 'Amount (INR)']);
    expect([for (var i = 0; i < 6; i++) cellText(decoded['Repayment Logs'], i, 0)], [
      'Date & Time', 'Customer Name', 'Customer Phone', 'Cleared Mode',
      'Repayment Amount (INR)', 'Processed By'
    ]);
    expect([for (var i = 0; i < 7; i++) cellText(decoded['Cash Reconciliations'], i, 0)], [
      'Reconciled Date', 'System Cash (INR)', 'Actual Cash (INR)',
      'Discrepancy (INR)', 'Audited By', 'Notes', 'Timestamp'
    ]);
    expect([for (var i = 0; i < 3; i++) cellText(decoded['Credit Accounts'], i, 0)],
        ['Customer Name', 'Phone Number', 'Total Pending Due (INR)']);
    expect(cellText(decoded['Top Selling Items'], 0, 0), 'Menu Item Name');
    expect(cellText(decoded['Top Selling Items'], 1, 0), 'Portions Sold (Total)');
  });

  test('row counts match the source records (nothing lost or duplicated)', () {
    expect(decoded['All Bills'].maxRows, 1 + rawBills.length);
    expect(decoded['All Expenses'].maxRows, 1 + rawExpenses.length);
    expect(decoded['Repayment Logs'].maxRows, 1 + rawRepayments.length);
    expect(decoded['Cash Reconciliations'].maxRows, 1 + rawRecons.length);
    expect(decoded['Credit Accounts'].maxRows, 1 + rawCredits.length);
    // Branch sheets add up to the combined sheet (legacy untagged => main).
    final names = decoded.tables.keys;
    var billRows = 0, expRows = 0;
    for (final n in names) {
      if (n.endsWith(' Bills') && n != 'All Bills') {
        billRows += decoded[n].maxRows - 1;
      }
      if (n.endsWith(' Expenses') && n != 'All Expenses') {
        expRows += decoded[n].maxRows - 1;
      }
    }
    expect(billRows, rawBills.length);
    expect(expRows, rawExpenses.length);
  });

  test('timestamps are rendered in IST, not UTC or device time', () {
    final b = decoded['All Bills'];
    // bill #1 was saved at 23:59:59 IST on 31 Oct; minute precision => 23:59.
    expect(cellText(b, 0, 1), '2026-10-31 23:59');
    expect(cellText(b, 0, 2), '2026-11-01 00:00'); // bill #2, first second of Nov
    expect(cellText(b, 0, 3), '2026-11-01 09:15');
    expect(cellText(decoded['Dashboard Summary'], 0, 1),
        'Report Generated: 2026-11-02 09:30 IST');
  });

  group('Dashboard Summary numbers', () {
    late Map<String, double> v;
    late Map<String, String> note;
    setUpAll(() {
      final s = decoded['Dashboard Summary'];
      v = {};
      note = {};
      for (var r = 4; r < 30; r++) {
        final label = cellText(s, 0, r);
        if (label.isEmpty) break;
        v[label] = cellNum(s, 1, r);
        note[label] = cellText(s, 2, r);
      }
    });

    // Independent arithmetic from the raw synthetic records:
    // sales: Cash 500+300+150.5=950.5  UPI 400+250.25=650.25  Credit 200+300+100=600
    // revenue 2200.75; repayments Cash 250+40=290, UPI 100; expenses 250.75
    test('sales are split by mode and exclude repayments', () {
      expect(v['Overall Revenue (All Branches)'], closeTo(2200.75, 0.001));
      expect(v['Cash Sales'], closeTo(950.5, 0.001));
      expect(v['UPI Sales'], closeTo(650.25, 0.001));
      expect(v['Credit Issued'], closeTo(600, 0.001));
    });

    test('repayments are split by mode', () {
      expect(v['Cash Repayments'], closeTo(290, 0.001));
      expect(v['UPI Repayments'], closeTo(100, 0.001));
      expect(v['Total Credit Repayments Received'], closeTo(390, 0.001));
    });

    test('Total Cash / UPI Received', () {
      expect(v['Total Cash Received'], closeTo(1240.5, 0.001)); // 950.5+290
      expect(v['Total UPI Received'], closeTo(750.25, 0.001)); // 650.25+100
    });

    test('positions use the approved formulas', () {
      expect(v['Overall Expenses'], closeTo(250.75, 0.001));
      expect(v['Accrual Operating Position (Sales - Expenses)'],
          closeTo(2200.75 - 250.75, 0.001));
      expect(v['Cash-Basis Movement (Received - Expenses)'],
          closeTo(1240.5 + 750.25 - 250.75, 0.001));
    });

    test('credit still due, discrepancy, and Credit Check == 0', () {
      expect(v['Total Credits Still Due'], closeTo(210, 0.001));
      expect(v['Cumulative Cash Discrepancy'], closeTo(-50, 0.001));
      expect(v['Credit Check (Issued - Repaid - Still Due)'], closeTo(0, 0.001));
    });

    test('old labels are gone, the profit word is never used', () {
      expect(v.containsKey('Cash Collected'), isFalse);
      expect(v.containsKey('UPI Collected'), isFalse);
      expect(v.keys.any((k) => k.toLowerCase().contains('profit')), isFalse);
    });

    test('every row has a non-empty formula explanation', () {
      for (final k in v.keys) {
        expect(note[k]!.trim().isNotEmpty, isTrue, reason: k);
      }
    });
  });

  test('branch breakdown rows add up to the combined summary', () {
    final s = decoded['Dashboard Summary'];
    var row = -1;
    for (var r = 0; r < 60; r++) {
      if (cellText(s, 0, r) == 'BRANCH-WISE BREAKDOWN') {
        row = r + 2; // header at r+1
        break;
      }
    }
    expect(row, greaterThan(0));
    expect(cellText(s, 0, row - 1), 'Branch');
    double sales = 0, cashS = 0, upiS = 0, cr = 0, cashR = 0, upiR = 0, exp = 0;
    var bills = 0, branches = 0;
    for (var r = row; cellText(s, 0, r).isNotEmpty; r++) {
      branches++;
      sales += cellNum(s, 1, r);
      bills += cellNum(s, 2, r).toInt();
      exp += cellNum(s, 3, r);
      cashS += cellNum(s, 4, r);
      upiS += cellNum(s, 5, r);
      cr += cellNum(s, 6, r);
      cashR += cellNum(s, 7, r);
      upiR += cellNum(s, 8, r);
      // per-branch positions are internally consistent
      expect(cellNum(s, 9, r),
          closeTo(cellNum(s, 1, r) - cellNum(s, 3, r), 0.01));
      expect(cellNum(s, 10, r),
          closeTo(cellNum(s, 4, r) + cellNum(s, 5, r) + cellNum(s, 7, r) + cellNum(s, 8, r) - cellNum(s, 3, r), 0.01));
    }
    expect(branches, 2);
    expect(bills, rawBills.length);
    expect(sales, closeTo(2200.75, 0.01));
    expect(cashS, closeTo(950.5, 0.01));
    expect(upiS, closeTo(650.25, 0.01));
    expect(cr, closeTo(600, 0.01));
    expect(cashR, closeTo(290, 0.01));
    expect(upiR, closeTo(100, 0.01));
    expect(exp, closeTo(250.75, 0.01));
  });

  test('top selling items are summed and sorted (quantity strings tolerated)', () {
    final t = decoded['Top Selling Items'];
    final got = <String, int>{};
    for (var r = 1; cellText(t, 0, r).isNotEmpty; r++) {
      got[cellText(t, 0, r)] = cellNum(t, 1, r).toInt();
    }
    // Tea: 2*(bills 1-5,7,8 =7 bills)=14 + 3 (bill 6) = 17; Samosa 7; Vada 4
    expect(got['Tea'], 17);
    expect(got['Samosa'], 7);
    expect(got['Vada'], 4);
    final counts = got.values.toList();
    expect(counts, [...counts]..sort((a, b) => b.compareTo(a)));
  });
}
