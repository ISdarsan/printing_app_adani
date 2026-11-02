import 'package:canteen_adani/business_time.dart';
import 'package:canteen_adani/canteen_provider.dart';
import 'package:canteen_adani/financial_metrics.dart';
import 'package:canteen_adani/report_records.dart';
import 'package:canteen_adani/today_summary.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime ist(int d, int h, int m, [int s = 0]) =>
    DateTime.utc(2026, 11, d, h, m, s).subtract(const Duration(hours: 5, minutes: 30));

BillRow bill(String id, String mode, double amt, DateTime ts, {String branch = 'north'}) =>
    BillRow(id: id, timestamp: ts, billNumber: 1, canteenId: branch, customerName: '-', customerPhone: '-', paymentMode: mode, amount: amt);

/// Applies the production writers (dailyStatsDelta*) to a list of records.
Map<String, dynamic> statsDoc(List<BillRow> bills, List<RepaymentRecord> reps) {
  final doc = <String, double>{};
  void add(Map<String, num> d) => d.forEach((k, v) => doc[k] = (doc[k] ?? 0) + v.toDouble());
  for (final b in bills) {
    add(dailyStatsDeltaForSale(b.amount, b.paymentMode));
  }
  for (final r in reps) {
    add(dailyStatsDeltaForRepayment(r.amount, r.mode));
  }
  return {...doc, 'canteenId': 'north', 'date': '2026-11-02'};
}

void main() {
  final bills = [
    bill('1', 'Cash', 500, ist(2, 9, 0)),
    bill('2', 'Cash', 300.5, ist(2, 10, 0)),
    bill('3', 'UPI', 400.25, ist(2, 11, 0)),
    bill('4', 'Credit', 200, ist(2, 12, 0)),
    bill('5', 'Credit', 99.99, ist(2, 13, 0)),
  ];
  const reps = [RepaymentRecord(250, 'Cash'), RepaymentRecord(100, 'UPI')];

  group('dailyStats card equals the source records', () {
    final stats = TodaySummary.fromDailyStats(statsDoc(bills, reps));
    final fromBills = TodaySummary.fromBills(bills);

    test('sales, bill count and credit sales are identical to the bills query', () {
      expect(stats.sales, closeTo(fromBills.sales, 1e-9));
      expect(stats.sales, closeTo(1500.74, 1e-9));
      expect(stats.bills, 5);
      expect(stats.credit, closeTo(299.99, 1e-9));
      expect(TodaySummary.salesDrift(stats, fromBills), isEmpty);
    });

    test('the card labels are unchanged (whole rupees, plain count)', () {
      expect(stats.salesLabel, '₹1501');
      expect(stats.billsLabel, '5');
    });

    test('repayments are NOT sales: they change collections only', () {
      final noRep = TodaySummary.fromDailyStats(statsDoc(bills, const []));
      expect(stats.sales, noRep.sales);
      expect(stats.bills, noRep.bills);
      expect(stats.cashCollected - noRep.cashCollected, 250);
      expect(stats.upiCollected - noRep.upiCollected, 100);
      expect(stats.creditReceived, 350);
    });

    test('cash/UPI collected = bill-derived sales + repayments (definitions differ by design)', () {
      expect(stats.cashCollected, closeTo(fromBills.cashCollected + 250, 1e-9));
      expect(stats.upiCollected, closeTo(fromBills.upiCollected + 100, 1e-9));
      expect(stats.cashCollected == fromBills.cashCollected, isFalse);
    });

    test('equals the reconciliation figure (same field the closing screen reads)', () {
      expect(stats.cashCollected, FinancialSummary.fromRecords(
        bills.map((b) => SaleRecord(b.amount, b.paymentMode)), reps).expectedRegisterCash);
    });
  });

  group('edge cases', () {
    test('no document yet = no sales today = zeros (not an error)', () {
      final t = TodaySummary.fromDailyStats(null);
      expect(t.sales, 0);
      expect(t.bills, 0);
      expect(t.salesLabel, '₹0');
    });

    test('missing or odd fields are treated as zero, ints accepted', () {
      final t = TodaySummary.fromDailyStats({'totalSales': 120, 'totalBills': 3.0});
      expect(t.sales, 120);
      expect(t.bills, 3);
      expect(t.credit, 0);
    });

    test('a deleted bill is detected as drift (stats are higher than the bills)', () {
      final stats = TodaySummary.fromDailyStats(statsDoc(bills, const []));
      final afterDelete = TodaySummary.fromBills(bills.where((b) => b.id != '3'));
      final drift = TodaySummary.salesDrift(stats, afterDelete);
      expect(drift['sales'], closeTo(400.25, 1e-9));
      expect(drift['bills'], 1);
    });

    test('floating point noise is not reported as drift', () {
      final noisy = [for (var i = 0; i < 300; i++) bill('n$i', 'Cash', 0.1, ist(2, 9, 0))];
      final stats = TodaySummary.fromDailyStats(statsDoc(noisy, const []));
      expect(TodaySummary.salesDrift(stats, TodaySummary.fromBills(noisy)), isEmpty);
    });
  });

  group('the right document is read, per branch and per IST day', () {
    test('doc id = branch_date, so another branch can never leak in', () {
      CanteenProvider.applyStaffData({'role': 'cashier', 'canteenId': 'north', 'canteenName': 'N'});
      expect(CanteenProvider.dailyStatsDocumentId(ist(2, 10, 0)), 'north_2026-11-02');
      CanteenProvider.applyStaffData({'role': 'cashier', 'canteenId': 'south', 'canteenName': 'S'});
      expect(CanteenProvider.dailyStatsDocumentId(ist(2, 10, 0)), 'south_2026-11-02');
    });

    test('midnight: a bill at 23:59:59 IST and one at 00:00:01 IST use different documents', () {
      CanteenProvider.applyStaffData({'role': 'cashier', 'canteenId': 'north', 'canteenName': 'N'});
      expect(CanteenProvider.dailyStatsDocumentId(ist(2, 23, 59, 59)), 'north_2026-11-02');
      expect(CanteenProvider.dailyStatsDocumentId(ist(3, 0, 0, 1)), 'north_2026-11-03');
    });

    test('the card rolls over at IST midnight (document id changes)', () {
      CanteenProvider.applyStaffData({'role': 'cashier', 'canteenId': 'north', 'canteenName': 'N'});
      final before = CanteenProvider.dailyStatsDocumentId(ist(2, 23, 59, 59));
      final after = CanteenProvider.dailyStatsDocumentId(ist(3, 0, 0, 0));
      expect(before, isNot(after));
      // and the bills-by-time-range the old card used agrees about the day
      expect(BusinessTime.dayRange(ist(2, 23, 59, 59)).contains(ist(2, 23, 59, 59)), isTrue);
      expect(BusinessTime.dayRange(ist(2, 23, 59, 59)).contains(ist(3, 0, 0, 0)), isFalse);
    });
  });
}
