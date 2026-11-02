import 'package:canteen_adani/business_time.dart';
import 'package:canteen_adani/export_range.dart';
import 'package:canteen_adani/financial_metrics.dart';
import 'package:canteen_adani/paged_fetch.dart';
import 'package:flutter_test/flutter_test.dart';

/// A record like a Firestore document: id + timestamp (many share a timestamp).
class Doc {
  final String id;
  final int ts; // epoch millis
  final double amount;
  const Doc(this.id, this.ts, this.amount);
}

/// Simulates `orderBy('timestamp', desc)` + `startAfterDocument(lastDoc)`:
/// Firestore breaks timestamp ties by document id in the same direction.
List<Doc> sortedLikeFirestore(List<Doc> docs) => [...docs]
  ..sort((a, b) {
    final c = b.ts.compareTo(a.ts);
    return c != 0 ? c : b.id.compareTo(a.id);
  });

PageFetcher<Doc> docCursorPager(List<Doc> store) {
  final sorted = sortedLikeFirestore(store);
  return (cursor, limit) async {
    var start = 0;
    if (cursor != null) {
      start = sorted.indexWhere((d) => d.id == (cursor as Doc).id) + 1;
    }
    final page = sorted.skip(start).take(limit).toList();
    return PageResult(page, page.isEmpty ? cursor : page.last, page.length == limit);
  };
}

/// WRONG on purpose (negative control): cursor is only the timestamp value.
PageFetcher<Doc> timestampOnlyPager(List<Doc> store) {
  final sorted = sortedLikeFirestore(store);
  return (cursor, limit) async {
    final page = (cursor == null
            ? sorted
            : sorted.where((d) => d.ts < (cursor as int)))
        .take(limit)
        .toList();
    return PageResult(page, page.isEmpty ? cursor : page.last.ts, page.length == limit);
  };
}

/// Many documents share each timestamp (bills saved in the same second).
List<Doc> makeStore(int n, {int perTimestamp = 7}) => [
      for (var i = 0; i < n; i++)
        Doc('b${i.toString().padLeft(6, '0')}', 1000000 + (i ~/ perTimestamp),
            (i % 50) + 0.25),
    ];

void main() {
  group('no skipped and no duplicated records', () {
    for (final n in [0, 1, 7, 499, 500, 501, 1203]) {
      for (final size in [1, 7, 250, 500]) {
        test('n=$n pageSize=$size (ties on timestamp)', () async {
          final store = makeStore(n);
          final r = await fetchAllPages<Doc>(
            fetchPage: docCursorPager(store),
            pageSize: size,
            keyOf: (d) => d.id,
          );
          expect(r.items.length, n);
          expect(r.items.map((d) => d.id).toSet().length, n);
          expect(r.items.map((d) => d.id).toSet(),
              store.map((d) => d.id).toSet());
          expect(r.duplicatesDropped, 0, reason: 'cursor must not repeat rows');
          expect(r.truncated, isFalse);
        });
      }
    }

    test('order is preserved (timestamp desc, id desc)', () async {
      final store = makeStore(120)..shuffle();
      final r = await fetchAllPages<Doc>(
          fetchPage: docCursorPager(store), pageSize: 17, keyOf: (d) => d.id);
      expect(r.items.map((d) => d.id).toList(),
          sortedLikeFirestore(store).map((d) => d.id).toList());
    });

    test('NEGATIVE CONTROL: a timestamp-only cursor really does lose rows', () async {
      final store = makeStore(100); // 7 docs per timestamp, page 10 splits ties
      final r = await fetchAllPages<Doc>(
          fetchPage: timestampOnlyPager(store), pageSize: 10, keyOf: (d) => d.id);
      expect(r.items.length, lessThan(100),
          reason: 'proves why the document cursor is required');
    });

    test('duplicates from a misbehaving source are detected and dropped', () async {
      final store = makeStore(30);
      final sorted = sortedLikeFirestore(store);
      Future<PageResult<Doc>> overlapping(Object? cursor, int limit) async {
        // Each page repeats the last row of the previous page.
        var start = 0;
        if (cursor != null) {
          start = sorted.indexWhere((d) => d.id == (cursor as Doc).id);
        }
        final page = sorted.skip(start).take(limit).toList();
        return PageResult(page, page.last, page.length == limit && start + limit < sorted.length + 1);
      }
      final r = await fetchAllPages<Doc>(
          fetchPage: overlapping, pageSize: 10, keyOf: (d) => d.id);
      expect(r.items.length, 30);
      expect(r.duplicatesDropped, greaterThan(0));
    });
  });

  group('amounts reconcile after paging', () {
    test('sum and per-mode totals equal the unpaged source', () async {
      final store = makeStore(1203);
      final modes = ['Cash', 'UPI', 'Credit'];
      SaleRecord rec(Doc d) => SaleRecord(d.amount, modes[d.id.hashCode.abs() % 3]);
      final direct = FinancialSummary.fromRecords(store.map(rec), const []);
      final paged = await fetchAllPages<Doc>(
          fetchPage: docCursorPager(store), pageSize: 250, keyOf: (d) => d.id);
      final viaPages = FinancialSummary.fromRecords(paged.items.map(rec), const []);
      expect(viaPages.salesRevenue, closeTo(direct.salesRevenue, 1e-6));
      expect(viaPages.cashSales, closeTo(direct.cashSales, 1e-6));
      expect(viaPages.upiSales, closeTo(direct.upiSales, 1e-6));
      expect(viaPages.creditSales, closeTo(direct.creditSales, 1e-6));
      expect(viaPages.billCount, 1203);
    });
  });

  group('large datasets', () {
    test('50,000 records in pages of 500 complete quickly without duplicates', () async {
      final store = makeStore(50000, perTimestamp: 13);
      final sw = Stopwatch()..start();
      var progress = 0;
      final r = await fetchAllPages<Doc>(
        fetchPage: docCursorPager(store),
        pageSize: 500,
        keyOf: (d) => d.id,
        onProgress: (n) => progress = n,
      );
      expect(r.items.length, 50000);
      expect(r.pages, 101); // 100 full pages + 1 empty terminating page
      expect(progress, 50000);
      expect(r.duplicatesDropped, 0);
      expect(sw.elapsed.inSeconds, lessThan(60));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('maxItems caps memory and reports truncation', () async {
      final store = makeStore(2000);
      final r = await fetchAllPages<Doc>(
          fetchPage: docCursorPager(store),
          pageSize: 300,
          maxItems: 1000,
          keyOf: (d) => d.id);
      expect(r.items.length, 1000);
      expect(r.truncated, isTrue);
    });
  });

  group('failures and interruptions', () {
    test('a transient failure is retried and the result is still complete', () async {
      final store = makeStore(100);
      final inner = docCursorPager(store);
      var calls = 0;
      Future<PageResult<Doc>> flaky(Object? c, int l) async {
        calls++;
        if (calls == 2) throw StateError('network blip');
        return inner(c, l);
      }
      final r = await fetchAllPages<Doc>(
          fetchPage: flaky,
          pageSize: 30,
          retryDelay: Duration.zero,
          keyOf: (d) => d.id);
      expect(r.items.length, 100);
      expect(r.retriedPages, 1);
      expect(r.duplicatesDropped, 0);
    });

    test('a permanent failure throws with the progress made, never a partial result', () async {
      final store = makeStore(100);
      final inner = docCursorPager(store);
      var calls = 0;
      Future<PageResult<Doc>> dead(Object? c, int l) async {
        calls++;
        if (calls >= 3) throw StateError('offline');
        return inner(c, l);
      }
      await expectLater(
        fetchAllPages<Doc>(
            fetchPage: dead,
            pageSize: 30,
            maxRetries: 2,
            retryDelay: Duration.zero,
            keyOf: (d) => d.id),
        throwsA(isA<PagedFetchException>()
            .having((e) => e.itemsLoaded, 'itemsLoaded', 60)
            .having((e) => e.pagesLoaded, 'pagesLoaded', 2)),
      );
    });

    test('cancellation stops before the next page', () async {
      final store = makeStore(1000);
      var cancel = false;
      var pagesSeen = 0;
      final inner = docCursorPager(store);
      Future<PageResult<Doc>> counting(Object? c, int l) {
        pagesSeen++;
        if (pagesSeen == 2) cancel = true;
        return inner(c, l);
      }
      await expectLater(
        fetchAllPages<Doc>(
            fetchPage: counting,
            pageSize: 100,
            isCancelled: () => cancel,
            keyOf: (d) => d.id),
        throwsA(isA<PagedFetchCancelled>()),
      );
      expect(pagesSeen, 2);
    });

    test('a source that claims more data but returns nothing cannot loop forever', () async {
      Future<PageResult<Doc>> stuck(Object? c, int l) async =>
          PageResult<Doc>(const [], c, true);
      final r = await fetchAllPages<Doc>(fetchPage: stuck, pageSize: 10);
      expect(r.items, isEmpty);
    });
  });

  group('export periods (IST, half-open)', () {
    // 2026-11-15 12:00 IST
    final now = DateTime.utc(2026, 11, 15, 12, 0).subtract(const Duration(hours: 5, minutes: 30));
    final presets = ExportRange.presets(now);
    ExportRange p(String id) => presets.firstWhere((x) => x.id == id);

    test('this month covers the whole of November in IST', () {
      final r = p('month').range!;
      expect(r.start, DateTime.utc(2026, 10, 31, 18, 30));
      expect(r.end, DateTime.utc(2026, 11, 30, 18, 30));
      expect(p('month').periodLabel, '2026-11-01 to 2026-11-30');
    });

    test('last 3 months = Sep, Oct, Nov; last 12 months crosses the year', () {
      expect(p('3m').periodLabel, '2026-09-01 to 2026-11-30');
      expect(p('12m').periodLabel, '2025-12-01 to 2026-11-30');
    });

    test('a bill at 23:59:59.999 IST on the last day is inside, next midnight outside', () {
      final r = p('month').range!;
      final lastMs = DateTime.utc(2026, 11, 30, 18, 29, 59, 999);
      final next = DateTime.utc(2026, 11, 30, 18, 30);
      expect(r.contains(lastMs), isTrue);
      expect(r.contains(next), isFalse);
    });

    test('all time has no range', () {
      expect(p('all').range, isNull);
      expect(p('all').isAllTime, isTrue);
      expect(p('all').periodLabel, 'All time');
    });

    test('presets work in January (previous months roll back a year)', () {
      final jan = ExportRange.presets(DateTime.utc(2027, 1, 10, 6, 0));
      expect(jan.firstWhere((x) => x.id == '3m').periodLabel, '2026-11-01 to 2027-01-31');
    });

    test('period boundaries tile with BusinessTime months', () {
      final r = p('12m').range!;
      expect(r.start, BusinessTime.monthRangeForMonth(2025, 12).start);
    });
  });
}
