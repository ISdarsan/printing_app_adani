/// Pure financial semantics for the canteen app.
///
/// This file documents and encodes how `dailyStats` is written today so the
/// rules can be unit-tested. See FINANCIAL_DATA_AUDIT.md.
///
/// Field meaning of a `dailyStats/{canteenId}_{yyyy-MM-dd}` document:
///   totalSales, totalBills, totalCredit  -> SALES only (written by billing)
///   totalCash, totalUpi                  -> COLLECTIONS: sales paid in that
///                                           mode PLUS credit repayments in
///                                           that mode (written by billing
///                                           and by repayments)
///   creditReceived                       -> repayments only (any mode)
library;

class SaleRecord {
  final double amount;
  final String mode; // 'Cash' | 'UPI' | 'Credit'
  const SaleRecord(this.amount, this.mode);
}

class RepaymentRecord {
  final double amount;
  final String mode; // 'Cash' | 'UPI'
  const RepaymentRecord(this.amount, this.mode);
}

/// Increments applied to `dailyStats` (as plain numbers, before wrapping in
/// FieldValue.increment). Single source of truth for both writers.
Map<String, num> dailyStatsDeltaForSale(double amount, String mode) => {
      'totalSales': amount,
      'totalBills': 1,
      if (mode == 'Cash') 'totalCash': amount,
      if (mode == 'UPI') 'totalUpi': amount,
      if (mode == 'Credit') 'totalCredit': amount,
    };

/// A repayment is NOT a sale: it never touches totalSales/totalBills/
/// totalCredit. It adds to the cash/UPI collected and to creditReceived.
Map<String, num> dailyStatsDeltaForRepayment(double amount, String mode) => {
      if (mode == 'Cash') 'totalCash': amount,
      if (mode == 'UPI') 'totalUpi': amount,
      'creditReceived': amount,
    };

class FinancialSummary {
  /// Revenue earned (cash + UPI + credit sales). Repayments excluded.
  final double salesRevenue;
  final double creditSales;
  final double cashSales;
  final double upiSales;
  final double cashRepayments;
  final double upiRepayments;
  final int billCount;

  const FinancialSummary({
    required this.salesRevenue,
    required this.creditSales,
    required this.cashSales,
    required this.upiSales,
    required this.cashRepayments,
    required this.upiRepayments,
    required this.billCount,
  });

  factory FinancialSummary.fromRecords(
    Iterable<SaleRecord> sales,
    Iterable<RepaymentRecord> repayments,
  ) {
    double revenue = 0, credit = 0, cash = 0, upi = 0, rc = 0, ru = 0;
    int bills = 0;
    for (final s in sales) {
      revenue += s.amount;
      bills++;
      if (s.mode == 'Cash') cash += s.amount;
      if (s.mode == 'UPI') upi += s.amount;
      if (s.mode == 'Credit') credit += s.amount;
    }
    for (final r in repayments) {
      if (r.mode == 'Cash') rc += r.amount;
      if (r.mode == 'UPI') ru += r.amount;
    }
    return FinancialSummary(
      salesRevenue: revenue,
      creditSales: credit,
      cashSales: cash,
      upiSales: upi,
      cashRepayments: rc,
      upiRepayments: ru,
      billCount: bills,
    );
  }

  double get totalRepayments => cashRepayments + upiRepayments;

  /// Matches dailyStats.totalCash.
  double get cashMovement => cashSales + cashRepayments;

  /// Matches dailyStats.totalUpi.
  double get upiMovement => upiSales + upiRepayments;

  /// What the register should physically hold. This is what the cashier
  /// reconciliation screen compares against (it reads dailyStats.totalCash).
  /// Expenses are not deducted: they carry no payment mode and are drawn from
  /// the monthly CSR fund (see FINANCIAL_DATA_AUDIT.md, open question Q2).
  double get expectedRegisterCash => cashMovement;

  /// Cash-basis money actually received (excludes unpaid credit).
  double get collections => cashMovement + upiMovement;

  /// Shape of the dailyStats document these records should produce.
  Map<String, num> toDailyStatsFields() => {
        'totalSales': salesRevenue,
        'totalBills': billCount,
        'totalCash': cashMovement,
        'totalUpi': upiMovement,
        'totalCredit': creditSales,
        'creditReceived': totalRepayments,
      };
}

/// Cash-basis net position: money actually received minus expenses.
double netPositionCashBasis(FinancialSummary s, double expenses) =>
    s.collections - expenses;

/// Accrual-basis result: revenue earned (incl. credit) minus expenses.
/// Repayments are NOT added: they settle revenue already counted at sale time.
double netPositionAccrual(FinancialSummary s, double expenses) =>
    s.salesRevenue - expenses;

/// The formula the Excel export currently uses ("Sales + Repayments -
/// Expenses"). Kept only so tests can demonstrate that it double counts every
/// repaid credit sale. Not used by the app.
double legacyExcelNetPosition(FinancialSummary s, double expenses) =>
    s.salesRevenue + s.totalRepayments - expenses;

/// Differences between a stored dailyStats doc and the figures derived from
/// source records. Read-only diagnostic for the reconciliation strategy;
/// empty map means consistent (within [tolerance]).
Map<String, double> dailyStatsDrift(
  Map<String, dynamic> stored,
  FinancialSummary derived, {
  double tolerance = 0.01,
}) {
  final expected = derived.toDailyStatsFields();
  final drift = <String, double>{};
  expected.forEach((field, value) {
    final actual = ((stored[field] ?? 0) as num).toDouble();
    final diff = actual - value.toDouble();
    if (diff.abs() > tolerance) drift[field] = diff;
  });
  return drift;
}
