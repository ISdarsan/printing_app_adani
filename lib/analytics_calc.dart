import 'business_time.dart';
import 'report_records.dart';

/// Pure analytics maths used by the admin Analytics page.
///
/// The functions here are the former private `_build*` methods of
/// `admin_analytics_page.dart`, moved unchanged in behavior so they can be fed
/// page by page (bills are aggregated as they arrive and never kept) and unit
/// tested against the original implementation (see
/// test/analytics_equivalence_test.dart).

// ---------------------------------------------------------------------------
// Period selection
// ---------------------------------------------------------------------------

/// How much history the analytics page reads. `null` start means all time.
class AnalyticsRange {
  final String id;
  final String label;
  final int? daysBack;
  final int? monthsBack;
  const AnalyticsRange._(this.id, this.label, {this.daysBack, this.monthsBack});

  static const days30 = AnalyticsRange._('30d', '30 days', daysBack: 30);
  static const days90 = AnalyticsRange._('90d', '90 days', daysBack: 90);

  /// Current month plus the 5 before it: exactly what the Monthly tab shows.
  static const months6 = AnalyticsRange._('6m', '6 months', monthsBack: 5);
  static const months12 = AnalyticsRange._('12m', '12 months', monthsBack: 11);
  static const all = AnalyticsRange._('all', 'All time');

  static const presets = [days30, days90, months6, months12, all];
  static const defaultRange = months6;

  bool get isAllTime => daysBack == null && monthsBack == null;

  /// First instant included (UTC), or null for all time. IST business calendar.
  DateTime? startInstant(DateTime now) {
    final w = BusinessTime.wallClock(now);
    if (daysBack != null) {
      return BusinessTime.dayRangeForDate(w.year, w.month, w.day - daysBack!)
          .start;
    }
    if (monthsBack != null) {
      return BusinessTime.monthRangeForMonth(w.year, w.month - monthsBack!)
          .start;
    }
    return null;
  }

  /// First `yyyy-MM-dd` included for `dailyStats.date`, or null for all time.
  String? startDateKey(DateTime now) {
    final s = startInstant(now);
    return s == null ? null : BusinessTime.dateKey(s);
  }
}

/// Server-side branch filter is only possible for a concrete branch. Canteen
/// 'main' also owns legacy documents that have no `canteenId` field, which a
/// query cannot match, so it is read unscoped and filtered on the device.
bool needsServerBranchFilter(String selectedCanteenId) =>
    selectedCanteenId.isNotEmpty && selectedCanteenId != 'main';

// ---------------------------------------------------------------------------
// Bill aggregators (single pass, no bill retained)
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _items(Map<String, dynamic> data) =>
    List<Map<String, dynamic>>.from(data['items'] ?? const []);

class BillAggregates {
  final DateTime now;
  BillAggregates(this.now)
      : _forecastStart = now.subtract(const Duration(days: 30)),
        _priorWeekStart = now.subtract(const Duration(days: 14)),
        _recentWeekStart = now.subtract(const Duration(days: 7));

  final DateTime _forecastStart;
  final DateTime _priorWeekStart;
  final DateTime _recentWeekStart;

  int billCount = 0;
  final _itemData = <String, Map<String, dynamic>>{};
  final _staffData = <String, Map<String, dynamic>>{};
  final _slotMap = <String, Map<String, dynamic>>{};
  final _itemMetrics = <String, Map<String, int>>{};

  /// Feed one bill document's data (already branch-filtered by the caller).
  void add(Map<String, dynamic> data) {
    billCount++;
    _addItemPerformance(data);
    _addStaff(data);
    _addTimeSlot(data);
    _addForecast(data);
  }

  void _addItemPerformance(Map<String, dynamic> data) {
    for (final item in _items(data)) {
      final name = (item['name'] ?? 'Unknown').toString();
      final qty = (item['quantity'] is int)
          ? item['quantity'] as int
          : int.tryParse(item['quantity']?.toString() ?? '') ?? 0;
      final unitPrice =
          ((item['price'] ?? item['fullPrice'] ?? 0.0) as num).toDouble();
      final rawUnitCost = item['costPrice'];
      final unitCost = rawUnitCost is num ? rawUnitCost.toDouble() : null;
      final revenue = qty * unitPrice;
      final current = _itemData.putIfAbsent(
        name,
        () => {
          'qty': 0,
          'revenue': 0.0,
          'cost': 0.0,
          'profit': 0.0,
          'knownCostQty': 0,
          'unknownCostQty': 0,
          'orders': 0,
        },
      );
      current['qty'] = (current['qty'] as int) + qty;
      current['revenue'] = (current['revenue'] as double) + revenue;
      if (unitCost == null) {
        current['unknownCostQty'] = (current['unknownCostQty'] as int) + qty;
      } else {
        final cost = qty * unitCost;
        current['cost'] = (current['cost'] as double) + cost;
        current['profit'] = (current['profit'] as double) + (revenue - cost);
        current['knownCostQty'] = (current['knownCostQty'] as int) + qty;
      }
      current['orders'] = (current['orders'] as int) + 1;
    }
  }

  void _addStaff(Map<String, dynamic> data) {
    final staffKey =
        (data['createdByEmail'] ?? data['createdBy'] ?? 'Unknown').toString();
    final amount = ((data['totalAmount'] ?? 0.0) as num).toDouble();
    final current = _staffData.putIfAbsent(
        staffKey, () => {'name': staffKey, 'sales': 0.0, 'bills': 0});
    current['sales'] = (current['sales'] as double) + amount;
    current['bills'] = (current['bills'] as int) + 1;
  }

  void _addTimeSlot(Map<String, dynamic> data) {
    final ts = asDateTime(data['timestamp']);
    if (ts == null) return;
    final hour = BusinessTime.wallClock(ts).hour;
    final bucket = '${hour.toString().padLeft(2, '0')}:00';
    final amount = ((data['totalAmount'] ?? 0.0) as num).toDouble();
    final mode = (data['paymentMode'] ?? 'Cash').toString();
    final slot = _slotMap.putIfAbsent(
        bucket, () => {'cash': 0.0, 'upi': 0.0, 'credit': 0.0, 'total': 0.0});
    slot['total'] = (slot['total'] as double) + amount;
    if (mode == 'Cash') {
      slot['cash'] = (slot['cash'] as double) + amount;
    } else if (mode == 'UPI') {
      slot['upi'] = (slot['upi'] as double) + amount;
    } else if (mode == 'Credit') {
      slot['credit'] = (slot['credit'] as double) + amount;
    }
  }

  void _addForecast(Map<String, dynamic> data) {
    final billDate = asDateTime(data['timestamp']);
    if (billDate == null) return;
    if (billDate.isBefore(_forecastStart)) return;
    for (final item in _items(data)) {
      final name = (item['name'] ?? 'Unknown').toString();
      final quantity = item['quantity'] is int
          ? item['quantity'] as int
          : int.tryParse(item['quantity']?.toString() ?? '') ?? 0;
      final metrics = _itemMetrics.putIfAbsent(
          name, () => {'qty': 0, 'priorWeekQty': 0, 'recentWeekQty': 0});
      metrics['qty'] = metrics['qty']! + quantity;
      if (!billDate.isBefore(_priorWeekStart) &&
          billDate.isBefore(_recentWeekStart)) {
        metrics['priorWeekQty'] = metrics['priorWeekQty']! + quantity;
      } else if (!billDate.isBefore(_recentWeekStart)) {
        metrics['recentWeekQty'] = metrics['recentWeekQty']! + quantity;
      }
    }
  }

  List<Map<String, dynamic>> itemPerformance() {
    final list = _itemData.entries
        .map((e) => {
              'name': e.key,
              'qty': e.value['qty'] as int,
              'revenue': e.value['revenue'] as double,
              'cost': e.value['cost'] as double,
              'profit': e.value['profit'] as double,
              'knownCostQty': e.value['knownCostQty'] as int,
              'unknownCostQty': e.value['unknownCostQty'] as int,
              'orders': e.value['orders'] as int,
            })
        .toList();
    list.sort((a, b) {
      final diff = (b['profit'] as double).compareTo(a['profit'] as double);
      if (diff != 0) return diff;
      return (b['qty'] as int).compareTo(a['qty'] as int);
    });
    return list;
  }

  List<Map<String, dynamic>> staffPerformance() {
    final list = _staffData.entries
        .map((e) => {
              'name': e.key,
              'sales': e.value['sales'] as double,
              'bills': e.value['bills'] as int,
            })
        .toList();
    list.sort((a, b) => (b['sales'] as double).compareTo(a['sales'] as double));
    return list;
  }

  List<Map<String, dynamic>> timeSlots() {
    final list = _slotMap.entries
        .map((e) => {
              'slot': e.key,
              'cash': e.value['cash'] as double,
              'upi': e.value['upi'] as double,
              'credit': e.value['credit'] as double,
              'total': e.value['total'] as double,
            })
        .toList();
    list.sort((a, b) => (a['slot'] as String).compareTo(b['slot'] as String));
    return list;
  }

  List<Map<String, dynamic>> forecast() {
    final items = _itemMetrics.entries
        .map((e) => {'name': e.key, ...e.value})
        .toList()
      ..sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < items.length && i < 5; i++) {
      final item = items[i];
      final avgDailyQty = (item['qty'] as int) / 30.0;
      final stockTarget = (avgDailyQty * 2.5).ceil();
      final prior = item['priorWeekQty'] as int;
      final recent = item['recentWeekQty'] as int;
      final trend = recent > prior
          ? 'Upward'
          : recent < prior
              ? 'Downward'
              : 'Stable';
      out.add({
        'name': item['name'],
        'avgDailyQty': avgDailyQty,
        'recommendedStock': stockTarget,
        'trend': trend,
      });
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// dailyStats based aggregates
// ---------------------------------------------------------------------------

/// Sums dailyStats documents (one per branch per day) into per-date totals.
/// Same keys and arithmetic as the former inline loop.
class DailyTotals {
  final byDate = <String, Map<String, dynamic>>{};

  /// [docId] is the document id, used only when `date` is missing.
  void add(Map<String, dynamic> data, String docId,
      String Function(String docId) dateFromId) {
    final date = (data['date'] ?? dateFromId(docId)).toString();
    if (DateTime.tryParse(date) == null) return;
    final totals = byDate.putIfAbsent(
        date,
        () => {
              'totalSales': 0.0,
              'totalCash': 0.0,
              'totalUpi': 0.0,
              'totalCredit': 0.0,
            });
    for (final field in ['totalSales', 'totalCash', 'totalUpi', 'totalCredit']) {
      totals[field] = (totals[field] as double) +
          ((data[field] ?? 0.0) as num).toDouble();
    }
  }

  List<String> get sortedDates => byDate.keys.toList()..sort();

  /// Last 7 business days, as the Weekly tab shows.
  List<MapEntry<String, Map<String, dynamic>>> weekly(String startDateKey) =>
      sortedDates
          .where((d) => d.compareTo(startDateKey) >= 0)
          .map((d) => MapEntry(d, byDate[d]!))
          .toList();

  Map<String, double> monthlySales() {
    final m = <String, double>{};
    for (final date in sortedDates) {
      final key = date.substring(0, 7);
      m[key] = (m[key] ?? 0.0) +
          ((byDate[date]!['totalSales'] ?? 0.0) as num).toDouble();
    }
    return m;
  }

  List<Map<String, dynamic>> anomalies() {
    final sortedDates = this.sortedDates;
    if (sortedDates.length < 2) return const [];
    final out = <Map<String, dynamic>>[];
    final window = sortedDates.length >= 7 ? 7 : sortedDates.length;
    for (var i = window; i < sortedDates.length; i++) {
      final date = sortedDates[i];
      final current = (byDate[date]!['totalSales'] ?? 0.0) as double;
      final prior = <double>[];
      for (var j = i - window; j < i; j++) {
        prior.add((byDate[sortedDates[j]]!['totalSales'] ?? 0.0) as double);
      }
      final avg = prior.isEmpty
          ? 0.0
          : prior.reduce((a, b) => a + b) / prior.length;
      if (avg <= 0) continue;
      final changePct = ((current - avg) / avg) * 100;
      if (changePct.abs() > 25) {
        out.add({
          'date': date,
          'currentSales': current,
          'averageSales': avg,
          'changePct': changePct,
          'trend': changePct >= 0 ? 'spike' : 'drop',
        });
      }
    }
    out.sort((a, b) =>
        (b['changePct'] as double).compareTo(a['changePct'] as double));
    return out;
  }
}

/// The month keys the Monthly tab displays: the 6 latest months that have
/// either sales or expenses (months that have only expenses still appear,
/// with zero sales, as before).
List<String> lastSixMonthKeys(
    Map<String, double> monthlySales, Iterable<String> expenseMonthKeys) {
  final keys = {...monthlySales.keys, ...expenseMonthKeys}.toList()..sort();
  return keys.length > 6 ? keys.sublist(keys.length - 6) : keys;
}
