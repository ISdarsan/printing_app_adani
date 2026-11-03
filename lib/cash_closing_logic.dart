import 'business_time.dart';
import 'money.dart';

/// Pure rules for the daily cash closing, separated from the screen so they
/// can be tested.

enum ClosingStatus { balanced, shortage, surplus }

/// Compared in whole paise, so floating-point dust never shows as a shortage.
ClosingStatus closingStatusFor(double discrepancy) {
  final p = toPaise(discrepancy);
  if (p == 0) return ClosingStatus.balanced;
  return p < 0 ? ClosingStatus.shortage : ClosingStatus.surplus;
}

/// Chip text for a closing record. Exact amounts (₹0.40 is shown as ₹0.40, not
/// rounded to a whole rupee, which used to read "Shortage: ₹0").
String closingChipText(double discrepancy) {
  switch (closingStatusFor(discrepancy)) {
    case ClosingStatus.balanced:
      return 'Balanced';
    case ClosingStatus.shortage:
      return 'Shortage: ₹${formatRupees(discrepancy.abs())}';
    case ClosingStatus.surplus:
      return 'Surplus: ₹${formatRupees(discrepancy)}';
  }
}

/// The calendar day of a closing record.
///
/// Uses the `date` field (yyyy-MM-dd). Older records without it fall back to
/// the date suffix of the document id (`<canteenId>_<yyyy-MM-dd>`). Returns
/// null when neither is a real date, so the screen shows the raw text instead
/// of crashing the whole list.
DateTime? closingDay(Object? dateField, String docId) {
  final fromField = _parseDay(dateField?.toString());
  if (fromField != null) return fromField;
  final cut = docId.lastIndexOf('_');
  return _parseDay(cut < 0 ? docId : docId.substring(cut + 1));
}

DateTime? _parseDay(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  // DateTime.tryParse accepts 2026-13-45 and silently rolls it over, so the
  // parts are checked here.
  if (mo < 1 || mo > 12) return null;
  if (d < 1 || d > DateTime(y, mo + 1, 0).day) return null;
  return DateTime(y, mo, d);
}

/// True when the business day (IST) is no longer the day the closing screen was
/// opened for. The expected cash on screen belongs to the OLD day, so it must
/// be refreshed before anything is saved.
bool closingDayChanged({required String openedDayKey, required DateTime now}) =>
    BusinessTime.dateKey(now) != openedDayKey;
