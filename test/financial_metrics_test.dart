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

  group('net position (decision B-07-Q3)', () {
    test('cash basis = collections - expenses', () {
      expect(netPositionCashBasis(s, 200), 1350);
    });

    test('accrual basis = sales - expenses (repayments not added)', () {
      expect(netPositionAccrual(s, 200), 1500);
    });

    test('legacy Excel formula double counts repaid credit', () {
      // 350 of credit sales were repaid: counted once as sales, again as
      // repayment. Accrual says 1500; legacy says 1850 (= 1500 + 350).
      expect(legacyExcelNetPosition(s, 200), 1850);
      expect(legacyExcelNetPosition(s, 200) - netPositionAccrual(s, 200),
          s.totalRepayments);
    });
  });
}
