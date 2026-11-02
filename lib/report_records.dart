/// Plain, Firestore-free records used by the Excel export and analytics.
///
/// Reading a Firestore document into one of these drops everything the
/// reports do not need (notably `proofImageBase64` on expenses and the
/// `items` array on bills), so large exports keep a small memory footprint.
library;

DateTime? asDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  try {
    // cloud_firestore Timestamp (duck-typed so this file stays pure Dart).
    final d = (v as dynamic).toDate();
    return d is DateTime ? d : null;
  } catch (_) {
    return null;
  }
}

double asDouble(dynamic v) => v is num ? v.toDouble() : 0.0;

int asInt(dynamic v) => v is num ? v.toInt() : 0;

String _s(dynamic v, [String fallback = '']) {
  final t = v?.toString() ?? '';
  return t.isEmpty ? fallback : t;
}

String branchIdOf(dynamic canteenId) {
  final c = canteenId?.toString() ?? '';
  return c.isEmpty ? 'main' : c;
}

class BillRow {
  final String id;
  final DateTime? timestamp;
  final int billNumber;
  final String canteenId;
  final String customerName;
  final String customerPhone;
  final String paymentMode;
  final double amount;
  const BillRow({
    this.id = '',
    required this.timestamp,
    required this.billNumber,
    required this.canteenId,
    required this.customerName,
    required this.customerPhone,
    required this.paymentMode,
    required this.amount,
  });

  factory BillRow.fromMap(Map<String, dynamic> d, {String id = ''}) => BillRow(
        id: id,
        timestamp: asDateTime(d['timestamp']),
        billNumber: asInt(d['billNumber']),
        canteenId: branchIdOf(d['canteenId']),
        customerName: _s(d['customerName'], 'Walk-in'),
        customerPhone: _s(d['customerPhone'], '-'),
        paymentMode: _s(d['paymentMode']),
        amount: asDouble(d['totalAmount']),
      );
}

class ExpenseRow {
  final String id;
  final DateTime? timestamp;
  final String canteenId;
  final String description;
  final double amount;
  const ExpenseRow({
    this.id = '',
    required this.timestamp,
    required this.canteenId,
    required this.description,
    required this.amount,
  });

  factory ExpenseRow.fromMap(Map<String, dynamic> d, {String id = ''}) =>
      ExpenseRow(
        id: id,
        timestamp: asDateTime(d['timestamp']),
        canteenId: branchIdOf(d['canteenId']),
        description: _s(d['description']),
        amount: asDouble(d['amount']),
      );
}

class RepaymentRow {
  final String id;
  final DateTime? timestamp;
  final String canteenId;
  final String customerName;
  final String customerPhone;
  final String paymentMode;
  final double amount;
  final String processedBy;
  const RepaymentRow({
    this.id = '',
    required this.timestamp,
    required this.canteenId,
    required this.customerName,
    required this.customerPhone,
    required this.paymentMode,
    required this.amount,
    required this.processedBy,
  });

  factory RepaymentRow.fromMap(Map<String, dynamic> d, {String id = ''}) =>
      RepaymentRow(
        id: id,
        timestamp: asDateTime(d['timestamp']),
        canteenId: branchIdOf(d['canteenId']),
        customerName: _s(d['customerName'], 'Unknown'),
        customerPhone: _s(d['customerPhone'], '-'),
        paymentMode: _s(d['paymentMode']),
        amount: asDouble(d['amount']),
        processedBy: _s(d['processedBy']),
      );
}

class ReconRow {
  final String id;
  final DateTime? timestamp;
  final String canteenId;
  final String date;
  final double systemCash;
  final double actualCash;
  final double discrepancy;
  final String submittedBy;
  final String note;
  const ReconRow({
    this.id = '',
    required this.timestamp,
    required this.canteenId,
    required this.date,
    required this.systemCash,
    required this.actualCash,
    required this.discrepancy,
    required this.submittedBy,
    required this.note,
  });

  factory ReconRow.fromMap(Map<String, dynamic> d, {String id = ''}) =>
      ReconRow(
        id: id,
        timestamp: asDateTime(d['timestamp']),
        canteenId: branchIdOf(d['canteenId']),
        date: _s(d['date']),
        systemCash: asDouble(d['systemCash']),
        actualCash: asDouble(d['actualCash']),
        discrepancy: asDouble(d['discrepancy']),
        submittedBy: _s(d['submittedBy']),
        note: _s(d['note']),
      );
}

class CreditRow {
  final String id;
  final String canteenId;
  final String name;
  final String phone;
  final double totalPending;
  const CreditRow({
    this.id = '',
    required this.canteenId,
    required this.name,
    required this.phone,
    required this.totalPending,
  });

  factory CreditRow.fromMap(Map<String, dynamic> d, {String id = ''}) =>
      CreditRow(
        id: id,
        canteenId: branchIdOf(d['canteenId']),
        name: _s(d['name'], 'Unknown'),
        phone: _s(d['phone']),
        totalPending: asDouble(d['totalPending']),
      );
}

/// Adds the quantities of one bill's `items` into [topItems]
/// (name -> portions). Tolerates missing/odd quantity types.
void accumulateTopItems(Map<String, int> topItems, dynamic items) {
  if (items is! List) return;
  for (final raw in items) {
    if (raw is! Map) continue;
    final name = raw['name']?.toString() ?? 'Unknown';
    final q = raw['quantity'];
    final qty = q is num ? q.toInt() : int.tryParse(q?.toString() ?? '') ?? 0;
    topItems[name] = (topItems[name] ?? 0) + qty;
  }
}

/// Everything the workbook needs, already reduced to plain values.
class ReportData {
  final List<BillRow> bills;
  final List<ExpenseRow> expenses;
  final List<CreditRow> credits;
  final List<RepaymentRow> repayments;
  final List<ReconRow> recons;
  final Map<String, int> topItems;
  final Map<String, String> canteenNames;

  /// Human description of the period, e.g. "All time" or
  /// "2026-05-01 to 2026-10-31".
  final String periodLabel;

  const ReportData({
    required this.bills,
    required this.expenses,
    required this.credits,
    required this.repayments,
    required this.recons,
    required this.topItems,
    required this.canteenNames,
    this.periodLabel = 'All time',
  });
}
