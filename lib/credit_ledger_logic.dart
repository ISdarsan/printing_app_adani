import 'money.dart';

/// Is this credit bill fully paid? A bill is paid when its status says so or
/// nothing is pending. A missing pending amount means the whole total is due.
bool creditBillIsPaid(Map<String, dynamic> bill) {
  final total = (bill['totalAmount'] as num?)?.toDouble() ?? 0.0;
  final pending = (bill['pendingAmount'] as num?)?.toDouble() ?? total;
  return bill['creditStatus'] == 'Paid' || pending <= 0;
}

/// Total still due across credit bills, in whole paise (so the sum of many
/// bills never drifts by a paisa).
int creditDuePaise(Iterable<Map<String, dynamic>> bills) {
  var due = 0;
  for (final b in bills) {
    if (creditBillIsPaid(b)) continue;
    final total = (b['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final pending = (b['pendingAmount'] as num?)?.toDouble() ?? total;
    due += toPaise(pending);
  }
  return due;
}
