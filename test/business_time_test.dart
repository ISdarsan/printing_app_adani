import 'package:canteen_adani/business_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// IST wall time -> instant, for readable test data.
DateTime ist(int y, int m, int d, [int h = 0, int mi = 0, int s = 0, int ms = 0]) =>
    DateTime.utc(y, m, d, h, mi, s, ms).subtract(BusinessTime.offset);

void main() {
  group('day range [startOfDay, startOfNextDay)', () {
    final r = BusinessTime.dayRange(ist(2026, 11, 2, 15, 30));

    test('starts at IST midnight (18:30 UTC the previous day)', () {
      expect(r.start, DateTime.utc(2026, 11, 1, 18, 30));
      expect(r.end, DateTime.utc(2026, 11, 2, 18, 30));
    });

    test('includes first and last instants of the day', () {
      expect(r.contains(ist(2026, 11, 2, 0, 0, 0)), isTrue);
      expect(r.contains(ist(2026, 11, 2, 23, 59, 59, 999)), isTrue);
    });

    test('excludes the instant just before and the next midnight', () {
      expect(r.contains(ist(2026, 11, 1, 23, 59, 59, 999)), isFalse);
      expect(r.contains(ist(2026, 11, 3, 0, 0, 0)), isFalse);
    });

    test('23:59:59.5 is no longer lost (old 23:59:59 upper bound bug)', () {
      final late = ist(2026, 11, 2, 23, 59, 59, 500);
      expect(r.contains(late), isTrue);
      // The old inclusive end 23:59:59.000 would have excluded it.
      expect(late.isAfter(ist(2026, 11, 2, 23, 59, 59)), isTrue);
    });

    test('adjacent days never overlap and leave no gap', () {
      final next = BusinessTime.dayRange(ist(2026, 11, 3, 1));
      expect(next.start, r.end);
    });
  });

  group('midnight transitions and timezone independence', () {
    test('21:00 UTC is already the next day in IST', () {
      final i = DateTime.utc(2026, 11, 2, 21, 0);
      expect(BusinessTime.dateKey(i), '2026-11-03');
    });

    test('18:29:59 UTC is still the same IST day, 18:30 UTC is next', () {
      expect(BusinessTime.dateKey(DateTime.utc(2026, 11, 2, 18, 29, 59)),
          '2026-11-02');
      expect(BusinessTime.dateKey(DateTime.utc(2026, 11, 2, 18, 30)),
          '2026-11-03');
    });

    test('same instant gives same key regardless of isUtc flag', () {
      final utc = DateTime.utc(2026, 5, 1, 19, 0);
      final local = utc.toLocal();
      expect(BusinessTime.dateKey(local), BusinessTime.dateKey(utc));
    });

    test('a US-timezone evening is the next IST day', () {
      // 2026-03-01 20:00 at UTC-5 == 2026-03-02 01:00 UTC == 06:30 IST Mar 2
      expect(BusinessTime.dateKey(DateTime.utc(2026, 3, 2, 1, 0)),
          '2026-03-02');
    });
  });

  group('month-end transitions', () {
    test('31 Oct 23:59:59.999 IST is October, 1 Nov 00:00 IST is November', () {
      final oct = BusinessTime.monthRangeForMonth(2026, 10);
      expect(oct.contains(ist(2026, 10, 31, 23, 59, 59, 999)), isTrue);
      expect(oct.contains(ist(2026, 11, 1, 0, 0, 0)), isFalse);
      expect(BusinessTime.monthKey(ist(2026, 10, 31, 23, 59)), '2026-10');
      expect(BusinessTime.monthKey(ist(2026, 11, 1, 0, 0)), '2026-11');
    });

    test('December rolls into January of the next year', () {
      final dec = BusinessTime.monthRangeForMonth(2026, 12);
      expect(dec.end, BusinessTime.monthRangeForMonth(2027, 1).start);
      expect(dec.end, DateTime.utc(2026, 12, 31, 18, 30));
    });

    test('leap February has 29 days of coverage', () {
      final feb = BusinessTime.monthRangeForMonth(2028, 2);
      expect(feb.end.difference(feb.start), const Duration(days: 29));
      final feb27 = BusinessTime.monthRangeForMonth(2027, 2);
      expect(feb27.end.difference(feb27.start), const Duration(days: 28));
    });

    test('monthRange(instant) matches monthRangeForMonth', () {
      final i = ist(2026, 7, 15, 12);
      final a = BusinessTime.monthRange(i);
      final b = BusinessTime.monthRangeForMonth(2026, 7);
      expect(a.start, b.start);
      expect(a.end, b.end);
    });

    test('consecutive months tile with no gap or overlap', () {
      for (var m = 1; m <= 12; m++) {
        final a = BusinessTime.monthRangeForMonth(2026, m);
        final b = BusinessTime.monthRangeForMonth(2026, m + 1);
        expect(a.end, b.start);
      }
    });
  });

  group('date keys for lookbacks', () {
    test('seven days before 3 Nov is 27 Oct', () {
      expect(BusinessTime.dateKeyDaysAgo(ist(2026, 11, 3, 10), 7), '2026-10-27');
    });

    test('lookback crosses year boundary', () {
      expect(BusinessTime.dateKeyDaysAgo(ist(2027, 1, 3, 10), 7), '2026-12-27');
    });
  });
}
