import 'dart:math';

import 'package:canteen_adani/analytics_calc.dart';
import 'package:canteen_adani/business_time.dart';
import 'package:canteen_adani/canteen_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/legacy_analytics.dart';

/// Synthetic data only. The optimized pipeline (BillAggregates, DailyTotals,
/// AnalyticsRange windows) is compared with the verbatim pre-optimisation code
/// in test/support/legacy_analytics.dart.

final rnd = Random(42);
final DateTime now0 = DateTime.now();

const staff = ['a@x.com', 'b@x.com', null, 'c@x.com'];
const modes = ['Cash', 'UPI', 'Credit'];
const itemNames = ['Tea', 'Samosa', 'Vada', 'Coffee', 'Idli', 'Dosa', 'Puri'];

Map<String, dynamic> makeBill(int i, DateTime ts, String? branch) {
  final nItems = 1 + rnd.nextInt(3);
  return {
    'timestamp': Timestamp.fromDate(ts),
    if (branch != null) 'canteenId': branch,
    'totalAmount': (20 + rnd.nextInt(300)) + (rnd.nextInt(4) * 0.25),
    'paymentMode': modes[rnd.nextInt(3)],
    if (staff[i % 4] != null) 'createdByEmail': staff[i % 4],
    'createdBy': 'uid${i % 4}',
    'items': [
      for (var k = 0; k < nItems; k++)
        {
          'name': itemNames[rnd.nextInt(itemNames.length)],
          'quantity': rnd.nextBool() ? 1 + rnd.nextInt(4) : '${1 + rnd.nextInt(4)}',
          if (rnd.nextBool()) 'price': 10.0 + rnd.nextInt(40) else 'fullPrice': 12.5,
          if (rnd.nextInt(3) != 0) 'costPrice': 4.0 + rnd.nextInt(8),
        }
    ],
  };
}

/// ~14 months of bills, branches main / north / south / untagged legacy.
List<Map<String, dynamic>> makeBills(int n) {
  final out = <Map<String, dynamic>>[];
  final start = now0.subtract(const Duration(days: 14 * 30));
  for (var i = 0; i < n; i++) {
    // whole minutes + 30 s keeps timestamps off every window boundary
    final minutes = rnd.nextInt(14 * 30 * 24 * 60 - 60);
    final ts = start.add(Duration(minutes: minutes, seconds: 30));
    final b = [ 'main', 'north', 'south', null ][rnd.nextInt(4)];
    out.add(makeBill(i, ts, b));
  }
  return out;
}

void expectSameLists(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
  expect(a.length, b.length);
  for (var i = 0; i < a.length; i++) {
    expect(a[i].keys.toSet(), b[i].keys.toSet());
    for (final k in a[i].keys) {
      final x = a[i][k], y = b[i][k];
      if (x is double && y is double) {
        expect(x, closeTo(y, 1e-6), reason: 'row $i key $k');
      } else {
        expect(x, y, reason: 'row $i key $k');
      }
    }
  }
}

BillAggregates aggOf(Iterable<Map<String, dynamic>> bills) {
  final a = BillAggregates(DateTime.now());
  for (final b in bills) {
    a.add(b);
  }
  return a;
}

List<FakeDoc> docsOf(Iterable<Map<String, dynamic>> bills) =>
    [for (final (i, b) in bills.indexed) FakeDoc('d$i', b)];

bool inWindow(Map<String, dynamic> b, DateTime? start) =>
    start == null || !(b['timestamp'] as Timestamp).toDate().isBefore(start);

void main() {
  final bills = makeBills(2500);

  group('bill aggregates equal the original implementation', () {
    test('all time: items, staff, time slots, forecast', () {
      final docs = docsOf(bills);
      final agg = aggOf(bills);
      expectSameLists(agg.itemPerformance(), legacyItemPerformance(docs));
      expectSameLists(agg.staffPerformance(), legacyStaffPerformance(docs));
      expectSameLists(agg.timeSlots(), legacyTimeSlotData(docs));
      expectSameLists(agg.forecast(), legacyForecastList(docs));
      expect(agg.billCount, 2500);
    });

    for (final range in AnalyticsRange.presets) {
      test('window ${range.label}: same results as the original fed the same documents', () {
        final start = range.startInstant(DateTime.now());
        final windowed = bills.where((b) => inWindow(b, start)).toList();
        final docs = docsOf(windowed);
        final agg = aggOf(windowed);
        expectSameLists(agg.itemPerformance(), legacyItemPerformance(docs));
        expectSameLists(agg.staffPerformance(), legacyStaffPerformance(docs));
        expectSameLists(agg.timeSlots(), legacyTimeSlotData(docs));
        expectSameLists(agg.forecast(), legacyForecastList(docs));
      });
    }

    test('forecast (rolling last 30 days) is identical for every window >= 30 days', () {
      final all = aggOf(bills).forecast();
      for (final range in AnalyticsRange.presets) {
        final start = range.startInstant(DateTime.now());
        final w = aggOf(bills.where((b) => inWindow(b, start))).forecast();
        expectSameLists(w, all);
      }
    });

    test('incremental page-by-page feeding equals one-shot feeding', () {
      final one = aggOf(bills);
      final paged = BillAggregates(DateTime.now());
      for (var i = 0; i < bills.length; i += 500) {
        for (final b in bills.skip(i).take(500)) {
          paged.add(b);
        }
      }
      expectSameLists(paged.itemPerformance(), one.itemPerformance());
      expectSameLists(paged.staffPerformance(), one.staffPerformance());
      expectSameLists(paged.timeSlots(), one.timeSlots());
    });
  });

  group('branch isolation is preserved', () {
    for (final branch in ['main', 'north', 'south']) {
      test('selected branch "$branch": filtered aggregation equals the original on the filtered list', () {
        CanteenProvider.setSelectedCanteen(id: branch, name: branch);
        final mine = bills.where(CanteenProvider.matchesSelectedCanteen).toList();
        final agg = BillAggregates(DateTime.now());
        // exactly what AnalyticsLoader does per document
        for (final b in bills) {
          if (CanteenProvider.matchesSelectedCanteen(b)) agg.add(b);
        }
        expectSameLists(agg.staffPerformance(), legacyStaffPerformance(docsOf(mine)));
        expectSameLists(agg.itemPerformance(), legacyItemPerformance(docsOf(mine)));
        expect(agg.billCount, mine.length);
        // nothing from another branch leaks in
        expect(mine.every((b) => (b['canteenId'] ?? 'main') == branch), isTrue);
      });
    }

    test('legacy untagged bills belong to main only', () {
      CanteenProvider.setSelectedCanteen(id: 'main', name: 'Main');
      final untagged = bills.where((b) => b['canteenId'] == null).length;
      final main = bills.where(CanteenProvider.matchesSelectedCanteen).length;
      expect(untagged, greaterThan(0));
      expect(main, bills.where((b) => b['canteenId'] == 'main').length + untagged);
      CanteenProvider.setSelectedCanteen(id: 'north', name: 'North');
      expect(bills.where(CanteenProvider.matchesSelectedCanteen).any((b) => b['canteenId'] == null), isFalse);
    });

    test('server-side branch filter only for concrete branches', () {
      expect(needsServerBranchFilter('main'), isFalse); // legacy docs have no canteenId
      expect(needsServerBranchFilter('north'), isTrue);
      expect(needsServerBranchFilter(''), isFalse);
    });

    test('branch sums add up to the whole', () {
      double sum(Iterable<Map<String, dynamic>> l) =>
          l.fold(0.0, (t, b) => t + (b['totalAmount'] as double));
      final byBranch = {
        for (final id in ['main', 'north', 'south'])
          id: bills.where((b) => (b['canteenId'] ?? 'main') == id)
      };
      expect(byBranch.values.fold(0.0, (t, l) => t + sum(l)), closeTo(sum(bills), 1e-6));
    });
  });

  group('dailyStats aggregates equal the original implementation', () {
    // one doc per branch per day for 14 months, plus a legacy doc without
    // a `date` field and an invalid one
    final stats = <FakeDoc>[];
    setUpAll(() {
      final base = BusinessTime.wallClock(now0);
      for (var d = 0; d < 14 * 30; d++) {
        final day = DateTime.utc(base.year, base.month, base.day - d);
        final key = BusinessTime.dateKey(day.subtract(BusinessTime.offset));
        for (final b in ['main', 'north']) {
          stats.add(FakeDoc('${b}_$key', {
            'canteenId': b,
            'date': key,
            'totalSales': 500.0 + rnd.nextInt(2000) * (d % 11 == 0 ? 3 : 1),
            'totalCash': 200.0 + rnd.nextInt(500),
            'totalUpi': 100.0 + rnd.nextInt(500),
            'totalCredit': rnd.nextInt(300).toDouble(),
          }));
        }
      }
      stats.add(FakeDoc('2020-01-05', {'totalSales': 10.0})); // legacy: no date field, no canteenId
      stats.add(FakeDoc('main_not-a-date', {'canteenId': 'main', 'date': 'oops', 'totalSales': 99.0}));
    });

    test('per-date totals, weekly, monthly, anomalies are identical (all time)', () {
      CanteenProvider.setSelectedCanteen(id: 'main', name: 'Main');
      final mine = stats.where((d) => CanteenProvider.matchesSelectedCanteen(d.data() as Map<String, dynamic>)).toList();
      final legacy = legacyDailyTotals(mine, CanteenProvider.dateFromDailyStatsDocumentId);
      final dt = DailyTotals();
      for (final d in mine) {
        dt.add(d.data() as Map<String, dynamic>, d.id, CanteenProvider.dateFromDailyStatsDocumentId);
      }
      expect(dt.byDate.keys.toSet(), legacy.keys.toSet());
      for (final k in legacy.keys) {
        for (final f in ['totalSales', 'totalCash', 'totalUpi', 'totalCredit']) {
          expect(dt.byDate[k]![f], closeTo(legacy[k]![f] as double, 1e-9), reason: '$k $f');
        }
      }
      expectSameLists(dt.anomalies(), legacyAnomalyList(legacy));
      final startKey = BusinessTime.dateKeyDaysAgo(DateTime.now(), 7);
      final lm = legacyMonthly(legacy, const [], startKey);
      expect(dt.weekly(startKey).map((e) => e.key).toList(), lm.weekly.map((e) => e.key).toList());
      expect(dt.monthlySales().keys.toList()..sort(), lm.sales.keys.toList()..sort());
      for (final k in lm.sales.keys) {
        expect(dt.monthlySales()[k], closeTo(lm.sales[k]!, 1e-6));
      }
      expect(lastSixMonthKeys(dt.monthlySales(), const []), lm.last6);
    });

    test('6-month window gives the same Monthly-tab months and sales as all time', () {
      CanteenProvider.setSelectedCanteen(id: 'main', name: 'Main');
      final startKey = AnalyticsRange.months6.startDateKey(DateTime.now())!;
      final all = DailyTotals();
      final win = DailyTotals();
      for (final d in stats) {
        final data = d.data() as Map<String, dynamic>;
        if (!CanteenProvider.matchesSelectedCanteen(data)) continue;
        all.add(data, d.id, CanteenProvider.dateFromDailyStatsDocumentId);
        // server query `date >= startKey` (docs without a date field are not returned)
        if (data['date'] is String && (data['date'] as String).compareTo(startKey) >= 0) {
          win.add(data, d.id, CanteenProvider.dateFromDailyStatsDocumentId);
        }
      }
      final a6 = lastSixMonthKeys(all.monthlySales(), const []);
      final w6 = lastSixMonthKeys(win.monthlySales(), const []);
      expect(w6, a6);
      for (final k in a6) {
        expect(win.monthlySales()[k], closeTo(all.monthlySales()[k]!, 1e-6));
      }
    });

    test('expense-only months still appear in the Monthly tab', () {
      final sales = {'2026-08': 100.0, '2026-09': 100.0, '2026-10': 100.0};
      final keys = lastSixMonthKeys(sales, {'2026-11'});
      expect(keys.last, '2026-11');
      expect(keys.length, 4);
    });

    test('KNOWN LIMIT: with a month of zero activity the 6-month window shows fewer months than all time', () {
      // all-time view would reach back to an older month to fill 6 slots
      final all = {'2026-01': 1.0, '2026-02': 1.0, '2026-03': 1.0, '2026-04': 1.0, '2026-06': 1.0, '2026-07': 1.0, '2026-08': 1.0};
      final windowed = {'2026-04': 1.0, '2026-06': 1.0, '2026-07': 1.0, '2026-08': 1.0}; // window starts in April
      expect(lastSixMonthKeys(all, const []).length, 6);
      expect(lastSixMonthKeys(windowed, const []).length, 4);
    });
  });

  group('analytics periods (IST business calendar)', () {
    final nov2 = DateTime.utc(2026, 11, 2, 6, 0); // 11:30 IST
    test('30 / 90 days start at IST midnight', () {
      expect(AnalyticsRange.days30.startInstant(nov2), DateTime.utc(2026, 10, 2, 18, 30)); // 2026-10-03 00:00 IST
      expect(AnalyticsRange.days30.startDateKey(nov2), '2026-10-03');
      expect(AnalyticsRange.days90.startDateKey(nov2), '2026-08-04');
    });
    test('6 months = June..November (current + 5), 12 months = Dec..Nov', () {
      expect(AnalyticsRange.months6.startDateKey(nov2), '2026-06-01');
      expect(AnalyticsRange.months12.startDateKey(nov2), '2025-12-01');
    });
    test('January rolls the year back', () {
      final jan = DateTime.utc(2027, 1, 15, 6);
      expect(AnalyticsRange.months6.startDateKey(jan), '2026-08-01');
    });
    test('window start is the first instant of that IST day (inclusive)', () {
      final start = AnalyticsRange.months6.startInstant(nov2)!;
      expect(start, DateTime.utc(2026, 5, 31, 18, 30));
      final firstMoment = start;
      final justBefore = start.subtract(const Duration(milliseconds: 1));
      expect(!firstMoment.isBefore(start), isTrue);
      expect(justBefore.isBefore(start), isTrue);
    });
    test('all time has no start; default is 6 months', () {
      expect(AnalyticsRange.all.startInstant(nov2), isNull);
      expect(AnalyticsRange.all.startDateKey(nov2), isNull);
      expect(AnalyticsRange.defaultRange.id, '6m');
      expect(AnalyticsRange.presets.length, 5);
    });
  });

  group('modelled read volume (synthetic, not a production measurement)', () {
    test('windowed reads are a fraction of all-time reads', () {
      final all = bills.length;
      final reads = {
        for (final r in AnalyticsRange.presets)
          r.id: bills.where((b) => inWindow(b, r.startInstant(DateTime.now()))).length
      };
      // ignore: avoid_print
      print('MODELLED READS of $all synthetic bills: $reads');
      expect(reads['all'], all);
      expect(reads['30d']!, lessThan(all * 0.15));
      expect(reads['90d']!, lessThan(all * 0.35));
      expect(reads['6m']!, lessThan(all * 0.55));
      expect(reads['12m']!, lessThan(all));
    });
  });
}
