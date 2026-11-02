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

  /// Repayments whose mode is neither Cash nor UPI. They count in
  /// `creditReceived` but not in cash/UPI movement (same as the writer).
  final double otherRepayments;
  final int billCount;

  const FinancialSummary({
    required this.salesRevenue,
    required this.creditSales,
    required this.cashSales,
    required this.upiSales,
    required this.cashRepayments,
    required this.upiRepayments,
    this.otherRepayments = 0,
    required this.billCount,
  });

  factory FinancialSummary.fromRecords(
    Iterable<SaleRecord> sales,
    Iterable<RepaymentRecord> repayments,
  ) {
    double revenue = 0, credit = 0, cash = 0, upi = 0, rc = 0, ru = 0, ro = 0;
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
      if (r.mode != 'Cash' && r.mode != 'UPI') ro += r.amount;
    }
    return FinancialSummary(
      salesRevenue: revenue,
      creditSales: credit,
      cashSales: cash,
      upiSales: upi,
      cashRepayments: rc,
      upiRepayments: ru,
      otherRepayments: ro,
      billCount: bills,
    );
  }

  double get totalRepayments => cashRepayments + upiRepayments + otherRepayments;

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

/// Accrual operating position: sales revenue (credit sales included)
/// minus expenses. Repayments are NOT added: they settle revenue that was
/// already counted when the credit sale was made. Not a profit figure
/// (no cost of goods, wages, etc.).
double accrualOperatingPosition(FinancialSummary s, double expenses) =>
    s.salesRevenue - expenses;

/// Cash-basis movement: cash sales + UPI sales + cash repayments + UPI
/// repayments - expenses. Unpaid credit sales are excluded until repaid.
/// Not a profit figure and not a bank balance.
double cashBasisMovement(FinancialSummary s, double expenses) =>
    s.collections - expenses;

/// The formula the Excel export used before decision Q3 ("Sales +
/// Repayments - Expenses"). Kept only so tests can demonstrate that it
/// double counted every repaid credit sale. Not used by the app.
double legacyExcelNetPosition(FinancialSummary s, double expenses) =>
    s.salesRevenue + s.totalRepayments - expenses;

/// One line of the Excel "Dashboard Summary" sheet.
class SummaryRow {
  final String label;
  final double value;

  /// Plain-language basis shown in the third column of the sheet.
  final String formula;
  const SummaryRow(this.label, this.value, this.formula);
}

/// Rows of the Excel executive summary (decisions Q3 and Q4). Pure, so the
/// numbers the report shows are unit-tested.
List<SummaryRow> buildExecutiveSummaryRows(
  FinancialSummary s, {
  required double expenses,
  required double creditStillDue,
  required double cumulativeDiscrepancy,
}) =>
    [
      SummaryRow('Overall Revenue (All Branches)', s.salesRevenue,
          'Cash Sales + UPI Sales + Credit Issued. Repayments are never included.'),
      SummaryRow('Cash Sales', s.cashSales, 'Bills paid in Cash.'),
      SummaryRow('UPI Sales', s.upiSales, 'Bills paid by UPI.'),
      SummaryRow('Credit Issued', s.creditSales,
          'Bills put on credit (not yet money received).'),
      SummaryRow('Cash Repayments', s.cashRepayments,
          'Credit repayments received in Cash.'),
      SummaryRow('UPI Repayments', s.upiRepayments,
          'Credit repayments received by UPI.'),
      if (s.otherRepayments != 0)
        SummaryRow('Repayments (other / unrecorded mode)', s.otherRepayments,
            'Repayments whose mode is neither Cash nor UPI. Not in Total Cash/UPI Received.'),
      SummaryRow('Total Credit Repayments Received', s.totalRepayments,
          'Cash + UPI (+ other) repayments.'),
      SummaryRow('Total Cash Received', s.cashMovement,
          'Cash Sales + Cash Repayments (matches dailyStats totalCash).'),
      SummaryRow('Total UPI Received', s.upiMovement,
          'UPI Sales + UPI Repayments (matches dailyStats totalUpi).'),
      SummaryRow('Total Credits Still Due', creditStillDue,
          'Sum of all credit customers pending balances.'),
      SummaryRow('Overall Expenses', expenses, 'Sum of logged expenses.'),
      SummaryRow('Cumulative Cash Discrepancy', cumulativeDiscrepancy,
          'Sum of daily cash-closing differences (actual - system).'),
      SummaryRow('Accrual Operating Position (Sales - Expenses)',
          accrualOperatingPosition(s, expenses),
          'Overall Revenue - Overall Expenses. Includes credit sales; repayments are not added again. Not a profit figure.'),
      SummaryRow('Cash-Basis Movement (Received - Expenses)',
          cashBasisMovement(s, expenses),
          'Cash Sales + UPI Sales + Cash Repayments + UPI Repayments - Expenses. Excludes unpaid credit. Not a profit figure.'),
      SummaryRow('Credit Check (Issued - Repaid - Still Due)',
          s.creditSales - s.totalRepayments - creditStillDue,
          'Should be 0. A non-zero value points to credit records created before repayments were tracked, or edited by hand.'),
    ];

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
