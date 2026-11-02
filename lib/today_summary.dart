import 'report_records.dart';

/// Today's figures for one branch, read from a single `dailyStats` document
/// instead of querying every bill of the day.
///
/// Field meaning (see FINANCIAL_DATA_AUDIT.md section 2):
///   totalSales, totalBills, totalCredit  = SALES only
///   totalCash, totalUpi                  = sales + credit repayments in that mode
///   creditReceived                       = repayments (any mode)
///
/// The cashier dashboard shows only `sales` and `bills`, whose definitions are
/// identical to "sum of bills.totalAmount" and "number of bills" for the day.
/// `cash`/`upi` here are collections (they include repayments) and must not be
/// presented as cash/UPI *sales*.
class TodaySummary {
  final double sales;
  final int bills;
  final double credit;
  final double cashCollected;
  final double upiCollected;
  final double creditReceived;
  const TodaySummary({
    this.sales = 0,
    this.bills = 0,
    this.credit = 0,
    this.cashCollected = 0,
    this.upiCollected = 0,
    this.creditReceived = 0,
  });

  static const empty = TodaySummary();

  /// A missing document means no sale has been made today (the first bill of
  /// the day creates it), so it is all zeros.
  factory TodaySummary.fromDailyStats(Map<String, dynamic>? d) {
    if (d == null) return empty;
    return TodaySummary(
      sales: asDouble(d['totalSales']),
      bills: asInt(d['totalBills']),
      credit: asDouble(d['totalCredit']),
      cashCollected: asDouble(d['totalCash']),
      upiCollected: asDouble(d['totalUpi']),
      creditReceived: asDouble(d['creditReceived']),
    );
  }

  /// What the old query-based card computed.
  factory TodaySummary.fromBills(Iterable<BillRow> bills) {
    double sales = 0, credit = 0, cash = 0, upi = 0;
    var n = 0;
    for (final b in bills) {
      sales += b.amount;
      n++;
      if (b.paymentMode == 'Credit') credit += b.amount;
      if (b.paymentMode == 'Cash') cash += b.amount;
      if (b.paymentMode == 'UPI') upi += b.amount;
    }
    return TodaySummary(
        sales: sales, bills: n, credit: credit, cashCollected: cash, upiCollected: upi);
  }

  /// Differences (stats minus bills) on the fields that share a definition:
  /// sales, bill count and credit sales. Empty = consistent. A non-empty map
  /// means a bill was deleted/edited after being counted, or a clock-skew
  /// device wrote the bill around midnight.
  static Map<String, double> salesDrift(TodaySummary stats, TodaySummary fromBills,
      {double tolerance = 0.01}) {
    final out = <String, double>{};
    void cmp(String k, double a, double b) {
      if ((a - b).abs() > tolerance) out[k] = a - b;
    }

    cmp('sales', stats.sales, fromBills.sales);
    cmp('bills', stats.bills.toDouble(), fromBills.bills.toDouble());
    cmp('credit', stats.credit, fromBills.credit);
    return out;
  }

  /// Text for the dashboard cards (whole rupees, as before).
  String get salesLabel => '₹${sales.toStringAsFixed(0)}';
  String get billsLabel => '$bills';
}
