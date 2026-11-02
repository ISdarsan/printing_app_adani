/// Business calendar for the canteens: fixed IST (Asia/Kolkata, UTC+05:30,
/// no daylight saving). Every "day" and "month" boundary used by queries,
/// dailyStats ids and reports is computed here so results do not depend on
/// the phone's timezone setting.
///
/// Ranges are half-open: [start, end) where `end` is the first instant of the
/// next day/month. Query with `isGreaterThanOrEqualTo: start` and
/// `isLessThan: end` so no instant (including 23:59:59.5) is lost or counted
/// twice.
library;

class DateRange {
  /// Inclusive, UTC instant.
  final DateTime start;

  /// Exclusive, UTC instant.
  final DateTime end;
  const DateRange(this.start, this.end);

  bool contains(DateTime instant) {
    final t = instant.toUtc();
    return !t.isBefore(start) && t.isBefore(end);
  }

  @override
  String toString() => 'DateRange($start, $end)';
}

class BusinessTime {
  BusinessTime._();

  static const Duration offset = Duration(hours: 5, minutes: 30);

  /// Wall-clock fields in the business zone (returned as a UTC-flagged
  /// DateTime so the caller never mixes it up with a real instant).
  static DateTime wallClock(DateTime instant) => instant.toUtc().add(offset);

  static DateTime _utcInstant(int y, int m, int d) =>
      DateTime.utc(y, m, d).subtract(offset);

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 'yyyy-MM-dd' of [instant] in the business zone.
  static String dateKey(DateTime instant) {
    final w = wallClock(instant);
    return '${w.year.toString().padLeft(4, '0')}-${_two(w.month)}-${_two(w.day)}';
  }

  /// 'yyyy-MM' of [instant] in the business zone.
  static String monthKey(DateTime instant) => dateKey(instant).substring(0, 7);

  /// The business day containing [instant].
  static DateRange dayRange(DateTime instant) {
    final w = wallClock(instant);
    return dayRangeForDate(w.year, w.month, w.day);
  }

  /// A calendar day given as its business-zone year/month/day (e.g. the
  /// result of a date picker).
  static DateRange dayRangeForDate(int year, int month, int day) =>
      DateRange(_utcInstant(year, month, day), _utcInstant(year, month, day + 1));

  /// The business month containing [instant].
  static DateRange monthRange(DateTime instant) {
    final w = wallClock(instant);
    return monthRangeForMonth(w.year, w.month);
  }

  /// A calendar month given as business-zone year/month (month 1-12).
  static DateRange monthRangeForMonth(int year, int month) =>
      DateRange(_utcInstant(year, month, 1), _utcInstant(year, month + 1, 1));

  /// Business date key `days` days before the day containing [instant].
  static String dateKeyDaysAgo(DateTime instant, int days) {
    final w = wallClock(instant);
    return dateKey(_utcInstant(w.year, w.month, w.day - days));
  }
}
