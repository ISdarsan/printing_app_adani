import 'business_time.dart';

/// The period an Excel export covers. `range == null` means all time.
/// Ranges are half-open business-day (IST) ranges: [start, end).
class ExportRange {
  final String id;
  final String label;
  final DateRange? range;
  const ExportRange(this.id, this.label, this.range);

  bool get isAllTime => range == null;

  /// Text printed on the summary sheet, e.g. "2026-08-01 to 2026-10-31".
  String get periodLabel {
    final r = range;
    if (r == null) return 'All time';
    final last = r.end.subtract(const Duration(milliseconds: 1));
    return '${BusinessTime.dateKey(r.start)} to ${BusinessTime.dateKey(last)}';
  }

  /// The choices offered to the admin, evaluated at [now].
  static List<ExportRange> presets(DateTime now) {
    final w = BusinessTime.wallClock(now);
    DateRange months(int back) {
      // First instant of the month `back` months before the current one,
      // through the end of the current month.
      final first = BusinessTime.monthRangeForMonth(w.year, w.month - back);
      final current = BusinessTime.monthRangeForMonth(w.year, w.month);
      return DateRange(first.start, current.end);
    }

    return [
      ExportRange('month', 'This month', months(0)),
      ExportRange('3m', 'Last 3 months', months(2)),
      ExportRange('12m', 'Last 12 months', months(11)),
      const ExportRange('all', 'All time', null),
    ];
  }
}
