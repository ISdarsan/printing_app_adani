import 'package:canteen_adani/financial_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hypothetical day used throughout (see FINANCIAL_DATA_AUDIT.md):
///   Sales:      Cash 500, Cash 300, UPI 400, Credit 200 (Ravi), Credit 300 (Ravi)
///   Repayments: Cash 250 (Ravi), UPI 100 (Ravi)
const _sales = [
  SaleRecord(500, 'Cash'),
  SaleRecord(300, 'Cash'),
  SaleRecord(400, 'UPI'),
  SaleRecord(200, 'Credit'),
  SaleRecord(300, 'Credit'),
];
const _repayments = [
  RepaymentRecord(250, 'Cash'),
  RepaymentRecord(100, 'UPI'),
];

/// Applies the same increments the Firestore writers apply to dailyStats.
Map<String, double> _applyWriters(
    List<SaleRecord> sales, List<RepaymentRecord> repayments) {
  final doc = <String, double>{};
  void add(Map<String, num> delta) =>
      delta.forEach((k, v) => doc[k] = (doc[k] ?? 0) + v.toDouble());
  for (final s in sales) {
    add(dailyStatsDeltaForSale(s.amount, s.mode));
  }
  for (final r in repayments) {
    add(dailyStatsDeltaForRepayment(r.amount, r.mode));
  }
  return doc;
}

void main() {
  final s = FinancialSummary.fromRecords(_sales, _repayments);

  group('sales', () {
    test('cash, UPI and credit sales are split correctly', () {
      expect(s.cashSales, 800);
      expect(s.upiSales, 400);
      expect(s.creditSales, 500);
      expect(s.salesRevenue, 1700);
      expect(s.billCount, 5);
    });
  });

  group('repayments', () {
    test('cash and UPI repayments are tracked separately', () {
      expect(s.cashRepayments, 250);
      expect(s.upiRepayments, 100);
      expect(s.totalRepayments, 350);
    });

    test('repayments are NOT new sales revenue', () {
      final withoutRepayments = FinancialSummary.fromRecords(_sales, const []);
      expect(s.salesRevenue, withoutRepayments.salesRevenue);
      expect(s.billCount, withoutRepayments.billCount);
      expect(s.creditSales, withoutRepayments.creditSales);
    });

    test('repayment delta never touches sales fields', () {
      final d = dailyStatsDeltaForRepayment(250, 'Cash');
      expect(d.containsKey('totalSales'), isFalse);
      expect(d.containsKey('totalBills'), isFalse);
      expect(d.containsKey('totalCredit'), isFalse);
      expect(d, {'totalCash': 250, 'creditReceived': 250});
      expect(dailyStatsDeltaForRepayment(100, 'UPI'),
          {'totalUpi': 100, 'creditReceived': 100});
    });
  });

  group('combined collection totals', () {
    test('cash/UPI movement = sales + repayments in that mode', () {
      expect(s.cashMovement, 1050);
      expect(s.upiMovement, 500);
      expect(s.collections, 1550);
    });

    test('credit sales are never counted as collected money', () {
      // 1700 revenue, but only 1550 actually received; 500 credit issued,
      // 350 repaid -> 150 still owed. 1700 - 150 == 1550.
      expect(s.salesRevenue - s.collections, 150);
      expect(s.creditSales - s.totalRepayments, 150);
    });
  });

  group('daily aggregation (writers vs source records)', () {
    test('dailyStats built from the writers matches the derived summary', () {
      final doc = _applyWriters(_sales.toList(), _repayments.toList());
      expect(doc, {
        'totalSales': 1700,
        'totalBills': 5,
        'totalCash': 1050,
        'totalUpi': 500,
        'totalCredit': 500,
        'creditReceived': 350,
      });
      expect(dailyStatsDrift(doc, s), isEmpty);
    });

    test('a bill is counted exactly once (no double counting)', () {
      final one = _applyWriters([const SaleRecord(100, 'Cash')], const []);
      expect(one['totalSales'], 100);
      expect(one['totalCash'], 100);
      expect(one['totalBills'], 1);
      expect(one.containsKey('totalUpi'), isFalse);
    });

    test('drift detector reports a stored value that disagrees', () {
      final doc = _applyWriters(_sales.toList(), _repayments.toList());
      doc['totalCash'] = 1000; // 50 short
      expect(dailyStatsDrift(doc, s), {'totalCash': -50});
    });

    test('drift detector treats missing stored fields as zero', () {
      final drift = dailyStatsDrift({}, s);
      expect(drift['totalSales'], -1700);
      expect(drift['creditReceived'], -350);
    });
  });

  group('reconciliation', () {
    test('expected register cash includes cash repayments, excludes UPI', () {
      expect(s.expectedRegisterCash, 1050);
    });

    test('shortage / surplus against actual cash', () {
      expect(1000 - s.expectedRegisterCash, -50); // shortage
      expect(1100 - s.expectedRegisterCash, 50); // surplus
      expect(1050 - s.expectedRegisterCash, 0);
    });

    test('credit-only day expects zero cash', () {
      final x = FinancialSummary.fromRecords(
          const [SaleRecord(500, 'Credit')], const []);
      expect(x.expectedRegisterCash, 0);
    });
  });

  group('monthly aggregation', () {
    test('sum of daily summaries equals the summary of all records', () {
      final day2Sales = [const SaleRecord(600, 'UPI')];
      final day2Rep = [const RepaymentRecord(150, 'Cash')];
      final d1 = s;
      final d2 = FinancialSummary.fromRecords(day2Sales, day2Rep);
      final month = FinancialSummary.fromRecords(
          [..._sales, ...day2Sales], [..._repayments, ...day2Rep]);
      expect(d1.salesRevenue + d2.salesRevenue, month.salesRevenue);
      expect(d1.cashMovement + d2.cashMovement, month.cashMovement);
      expect(d1.upiMovement + d2.upiMovement, month.upiMovement);
      expect(month.salesRevenue, 2300);
    });
  });

  group('Q3: accrual operating position and cash-basis movement', () {
    test('accrual = sales revenue (credit included) - expenses', () {
      expect(accrualOperatingPosition(s, 200), 1500);
    });

    test('cash basis = cash+UPI sales + cash+UPI repayments - expenses', () {
      // 800 + 400 + 250 + 100 - 200
      expect(cashBasisMovement(s, 200), 1350);
    });

    test('repayments change cash basis but never accrual', () {
      final noRep = FinancialSummary.fromRecords(_sales, const []);
      expect(accrualOperatingPosition(s, 200),
          accrualOperatingPosition(noRep, 200));
      expect(cashBasisMovement(s, 200) - cashBasisMovement(noRep, 200),
          s.totalRepayments);
    });

    test('credit sales raise accrual but not cash basis until repaid', () {
      final creditOnly = FinancialSummary.fromRecords(
          const [SaleRecord(500, 'Credit')], const []);
      expect(accrualOperatingPosition(creditOnly, 0), 500);
      expect(cashBasisMovement(creditOnly, 0), 0);
      final repaid = FinancialSummary.fromRecords(
          const [SaleRecord(500, 'Credit')],
          const [RepaymentRecord(500, 'Cash')]);
      expect(accrualOperatingPosition(repaid, 0), 500); // unchanged
      expect(cashBasisMovement(repaid, 0), 500); // now received
    });

    test('the two measures differ exactly by outstanding credit', () {
      final outstanding = s.creditSales - s.totalRepayments;
      expect(accrualOperatingPosition(s, 200) - cashBasisMovement(s, 200),
          outstanding);
    });

    test('legacy Excel formula double counted repaid credit', () {
      expect(legacyExcelNetPosition(s, 200), 1850);
      expect(legacyExcelNetPosition(s, 200) - accrualOperatingPosition(s, 200),
          s.totalRepayments);
    });
  });

  group('Q2: expenses and register cash', () {
    test('expected register cash ignores expenses entirely', () {
      expect(s.expectedRegisterCash, 1050);
      expect(s.expectedRegisterCash, s.cashMovement);
      // Expenses only enter the position measures, not register cash.
      expect(cashBasisMovement(s, 0) - cashBasisMovement(s, 300), 300);
    });

    test('expenses reduce both reported positions', () {
      expect(accrualOperatingPosition(s, 0) - accrualOperatingPosition(s, 200),
          200);
      expect(cashBasisMovement(s, 0) - cashBasisMovement(s, 200), 200);
    });
  });

  group('Q4: Excel summary rows', () {
    final rows = buildExecutiveSummaryRows(s,
        expenses: 200, creditStillDue: 150, cumulativeDiscrepancy: -50);
    double v(String label) => rows.firstWhere((r) => r.label == label).value;
    bool has(String label) => rows.any((r) => r.label == label);

    test('old "Collected" labels are gone, new labels present', () {
      expect(has('Cash Collected'), isFalse);
      expect(has('UPI Collected'), isFalse);
      for (final l in [
        'Cash Sales',
        'UPI Sales',
        'Cash Repayments',
        'UPI Repayments',
        'Total Cash Received',
        'Total UPI Received',
        'Credit Issued',
        'Total Credits Still Due',
        'Total Credit Repayments Received',
        'Overall Expenses',
        'Cumulative Cash Discrepancy',
      ]) {
        expect(has(l), isTrue, reason: l);
      }
    });

    test('sales and repayments are separated', () {
      expect(v('Cash Sales'), 800);
      expect(v('UPI Sales'), 400);
      expect(v('Cash Repayments'), 250);
      expect(v('UPI Repayments'), 100);
      expect(v('Overall Revenue (All Branches)'), 1700);
    });

    test('Total Cash/UPI Received reconcile with dailyStats', () {
      final doc = _applyWriters(_sales.toList(), _repayments.toList());
      expect(v('Total Cash Received'), doc['totalCash']);
      expect(v('Total UPI Received'), doc['totalUpi']);
      expect(v('Total Credit Repayments Received'), doc['creditReceived']);
      expect(v('Overall Revenue (All Branches)'), doc['totalSales']);
      expect(v('Credit Issued'), doc['totalCredit']);
    });

    test('both positions present with correct values and qualified names', () {
      expect(v('Accrual Operating Position (Sales - Expenses)'), 1500);
      expect(v('Cash-Basis Movement (Received - Expenses)'), 1350);
      expect(
          rows.any((r) => r.label.toLowerCase().contains('profit')), isFalse);
      expect(
          rows
              .where((r) =>
                  r.label.contains('Position') || r.label.contains('Movement'))
              .every((r) => r.formula.contains('Not a profit figure')),
          isTrue);
    });

    test('credit check is zero when records are consistent', () {
      expect(v('Credit Check (Issued - Repaid - Still Due)'), 0);
    });

    test('every row explains its basis', () {
      expect(rows.every((r) => r.formula.trim().isNotEmpty), isTrue);
    });

    test('unclassified repayments are shown, not silently dropped', () {
      final weird = FinancialSummary.fromRecords(
          const [SaleRecord(100, 'Credit')],
          const [RepaymentRecord(40, 'Cheque')]);
      expect(weird.totalRepayments, 40);
      expect(weird.cashMovement, 0);
      final r = buildExecutiveSummaryRows(weird,
          expenses: 0, creditStillDue: 60, cumulativeDiscrepancy: 0);
      expect(
          r.any((x) =>
              x.label.startsWith('Repayments (other') && x.value == 40),
          isTrue);
      expect(r.firstWhere((x) => x.label.startsWith('Credit Check')).value, 0);
    });
  });

  group('branch split adds up to the whole (export branch rows)', () {
    test('sum of branch summaries equals the combined summary', () {
      final north = FinancialSummary.fromRecords(const [
        SaleRecord(500, 'Cash'),
        SaleRecord(200, 'Credit')
      ], const [
        RepaymentRecord(50, 'Cash')
      ]);
      final south = FinancialSummary.fromRecords(
          const [SaleRecord(400, 'UPI')], const [RepaymentRecord(100, 'UPI')]);
      final all = FinancialSummary.fromRecords(const [
        SaleRecord(500, 'Cash'),
        SaleRecord(200, 'Credit'),
        SaleRecord(400, 'UPI')
      ], const [
        RepaymentRecord(50, 'Cash'),
        RepaymentRecord(100, 'UPI')
      ]);
      expect(north.salesRevenue + south.salesRevenue, all.salesRevenue);
      expect(north.cashMovement + south.cashMovement, all.cashMovement);
      expect(north.upiMovement + south.upiMovement, all.upiMovement);
      expect(
          north.totalRepayments + south.totalRepayments, all.totalRepayments);
      expect(cashBasisMovement(north, 30) + cashBasisMovement(south, 20),
          cashBasisMovement(all, 50));
    });
  });
}
