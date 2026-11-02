import 'package:cloud_firestore/cloud_firestore.dart';

import 'analytics_calc.dart';
import 'business_time.dart';
import 'canteen_provider.dart';
import 'paged_fetch.dart';
import 'report_data_loader.dart' show firestorePageFetcher;
import 'report_records.dart';

/// Everything the Analytics page shows, already aggregated.
class AnalyticsResult {
  final AnalyticsRange range;
  final DateTime loadedAt;
  final List<Map<String, dynamic>> itemPerformance;
  final List<Map<String, dynamic>> staffPerformance;
  final List<Map<String, dynamic>> timeSlots;
  final List<Map<String, dynamic>> anomalies;
  final List<Map<String, dynamic>> forecast;
  final List<MapEntry<String, Map<String, dynamic>>> weekly;
  final Map<String, double> monthlySales;
  final List<String> last6MonthKeys;

  /// Documents read from Firestore (cost indicator) and used after the
  /// branch filter.
  final int billsRead;
  final int billsUsed;
  final int dailyStatsRead;
  final int expensesRead;

  /// True when a safety row limit stopped a read: figures may be incomplete.
  final bool truncated;

  const AnalyticsResult({
    required this.range,
    required this.loadedAt,
    required this.itemPerformance,
    required this.staffPerformance,
    required this.timeSlots,
    required this.anomalies,
    required this.forecast,
    required this.weekly,
    required this.monthlySales,
    required this.last6MonthKeys,
    required this.billsRead,
    required this.billsUsed,
    required this.dailyStatsRead,
    required this.expensesRead,
    required this.truncated,
  });
}

/// Reads analytics source data in bounded, paged queries and aggregates it as
/// it arrives (bills are never kept in memory).
///
/// Branch isolation is unchanged: results are filtered with
/// `CanteenProvider.matchesSelectedCanteen`; for a concrete (non-main) branch
/// the bills/expenses queries are additionally scoped by `canteenId` on the
/// server (index: bills(canteenId, timestamp desc), expenses(canteenId,
/// timestamp asc), see firestore.indexes.json). Branch 'main' is read unscoped
/// because it also owns legacy documents without a `canteenId`.
class AnalyticsLoader {
  final FirebaseFirestore db;
  const AnalyticsLoader(this.db);

  static const _billPage = 500;
  static const _statsPage = 500;
  static const _expensePage = 40; // docs carry a base64 proof photo
  static const _maxRows = 200000;

  Future<AnalyticsResult> load(
    AnalyticsRange range, {
    DateTime? now,
    void Function(String stage, int count)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final at = now ?? DateTime.now();
    final start = range.startInstant(at);
    final startKey = range.startDateKey(at);
    final selected = CanteenProvider.selectedCanteenId;
    final scoped = needsServerBranchFilter(selected);
    var truncated = false;

    // ---- bills: aggregate page by page -------------------------------
    Query<Map<String, dynamic>> bq = db.collection('bills');
    if (scoped) bq = bq.where('canteenId', isEqualTo: selected);
    if (start != null) bq = bq.where('timestamp', isGreaterThanOrEqualTo: start);
    bq = bq.orderBy('timestamp', descending: true);

    final agg = BillAggregates(at);
    final seenBills = <String>{};
    final billsRes = await fetchAllPages<String>(
      fetchPage: firestorePageFetcher<String>(bq, (d) {
        if (seenBills.add(d.id)) {
          final data = d.data();
          if (CanteenProvider.matchesSelectedCanteen(data)) agg.add(data);
        }
        return d.id;
      }),
      pageSize: _billPage,
      maxItems: _maxRows,
      isCancelled: isCancelled,
      onProgress: (n) => onProgress?.call('bills', n),
    );
    truncated |= billsRes.truncated;

    // ---- dailyStats: one small doc per branch per day ----------------
    Query<Map<String, dynamic>> sq = db.collection('dailyStats');
    // Windowed reads filter on the `date` field. All-time reads page by
    // document id so legacy documents without a `date` are still included.
    sq = startKey != null
        ? sq.where('date', isGreaterThanOrEqualTo: startKey).orderBy('date')
        : sq.orderBy(FieldPath.documentId);
    final daily = DailyTotals();
    final seenStats = <String>{};
    final statsRes = await fetchAllPages<String>(
      fetchPage: firestorePageFetcher<String>(sq, (d) {
        if (seenStats.add(d.id)) {
          final data = d.data();
          if (CanteenProvider.matchesSelectedCanteen(data)) {
            daily.add(data, d.id, CanteenProvider.dateFromDailyStatsDocumentId);
          }
        }
        return d.id;
      }),
      pageSize: _statsPage,
      maxItems: _maxRows,
      isCancelled: isCancelled,
      onProgress: (n) => onProgress?.call('daily totals', n),
    );
    truncated |= statsRes.truncated;

    // ---- expenses: only the months that have any (feeds the month list)
    Query<Map<String, dynamic>> eq = db.collection('expenses');
    if (scoped) eq = eq.where('canteenId', isEqualTo: selected);
    if (start != null) eq = eq.where('timestamp', isGreaterThanOrEqualTo: start);
    eq = eq.orderBy('timestamp');
    final expenseMonths = <String>{};
    final seenExp = <String>{};
    final expRes = await fetchAllPages<String>(
      fetchPage: firestorePageFetcher<String>(eq, (d) {
        if (seenExp.add(d.id)) {
          final data = d.data();
          if (CanteenProvider.matchesSelectedCanteen(data)) {
            final ts = asDateTime(data['timestamp']);
            if (ts != null) expenseMonths.add(BusinessTime.monthKey(ts));
          }
        }
        return d.id; // proof image is dropped with the document
      }),
      pageSize: _expensePage,
      maxItems: _maxRows,
      isCancelled: isCancelled,
      onProgress: (n) => onProgress?.call('expenses', n),
    );
    truncated |= expRes.truncated;

    final monthly = daily.monthlySales();
    return AnalyticsResult(
      range: range,
      loadedAt: at,
      itemPerformance: agg.itemPerformance(),
      staffPerformance: agg.staffPerformance(),
      timeSlots: agg.timeSlots(),
      anomalies: daily.anomalies(),
      forecast: agg.forecast(),
      weekly: daily.weekly(BusinessTime.dateKeyDaysAgo(at, 7)),
      monthlySales: monthly,
      last6MonthKeys: lastSixMonthKeys(monthly, expenseMonths),
      billsRead: billsRes.items.length,
      billsUsed: agg.billCount,
      dailyStatsRead: statsRes.items.length,
      expensesRead: expRes.items.length,
      truncated: truncated,
    );
  }
}
