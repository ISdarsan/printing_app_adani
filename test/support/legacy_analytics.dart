// TEST-ONLY REFERENCE. Verbatim copy of the analytics maths in
// lib/admin_analytics_page.dart as it was before the B-08 optimisation
// (commit 78f2cc5), with only the Firestore document type replaced by FakeDoc.
// test/analytics_equivalence_test.dart compares the new accumulators with it.
// ignore_for_file: prefer_final_locals, avoid_function_literals_in_foreach_calls
import 'package:canteen_adani/business_time.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FakeDoc {
  final String id;
  final Map<String, dynamic> _data;
  FakeDoc(this.id, this._data);
  dynamic data() => _data;
}

List<Map<String, dynamic>> legacyItemPerformance(
    List<FakeDoc> billDocs) {
  final itemData = <String, Map<String, dynamic>>{};

  for (final doc in billDocs) {
    final data = doc.data() as Map<String, dynamic>;
    final items = List<Map<String, dynamic>>.from(data['items'] ?? const []);
    for (final item in items) {
      final name = (item['name'] ?? 'Unknown').toString();
      final qty = (item['quantity'] is int)
          ? item['quantity'] as int
          : int.tryParse(item['quantity']?.toString() ?? '') ?? 0;
      final unitPrice =
          ((item['price'] ?? item['fullPrice'] ?? 0.0) as num).toDouble();
      final rawUnitCost = item['costPrice'];
      final unitCost = rawUnitCost is num ? rawUnitCost.toDouble() : null;
      final revenue = qty * unitPrice;
      final current = itemData.putIfAbsent(
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

  final list = itemData.entries
      .map((entry) => {
            'name': entry.key,
            'qty': entry.value['qty'] as int,
            'revenue': entry.value['revenue'] as double,
            'cost': entry.value['cost'] as double,
            'profit': entry.value['profit'] as double,
            'knownCostQty': entry.value['knownCostQty'] as int,
            'unknownCostQty': entry.value['unknownCostQty'] as int,
            'orders': entry.value['orders'] as int,
          })
      .toList();

  list.sort((a, b) {
    final diff = (b['profit'] as double).compareTo(a['profit'] as double);
    if (diff != 0) return diff;
    return (b['qty'] as int).compareTo(a['qty'] as int);
  });
  return list;
}

List<Map<String, dynamic>> legacyStaffPerformance(
    List<FakeDoc> billDocs) {
  final staffData = <String, Map<String, dynamic>>{};

  for (final doc in billDocs) {
    final data = doc.data() as Map<String, dynamic>;
    final staffKey =
        (data['createdByEmail'] ?? data['createdBy'] ?? 'Unknown').toString();
    final amount = ((data['totalAmount'] ?? 0.0) as num).toDouble();
    final current = staffData.putIfAbsent(
      staffKey,
      () => {
        'name': staffKey,
        'sales': 0.0,
        'bills': 0,
      },
    );
    current['sales'] = (current['sales'] as double) + amount;
    current['bills'] = (current['bills'] as int) + 1;
  }

  final list = staffData.entries
      .map((entry) => {
            'name': entry.key,
            'sales': entry.value['sales'] as double,
            'bills': entry.value['bills'] as int,
          })
      .toList();

  list.sort((a, b) => (b['sales'] as double).compareTo(a['sales'] as double));
  return list;
}

List<Map<String, dynamic>> legacyTimeSlotData(
    List<FakeDoc> billDocs) {
  final slotMap = <String, Map<String, dynamic>>{};

  for (final doc in billDocs) {
    final data = doc.data() as Map<String, dynamic>;
    final ts = data['timestamp'] as Timestamp?;
    if (ts == null) continue;

    final hour = BusinessTime.wallClock(ts.toDate()).hour;
    final bucket = '${hour.toString().padLeft(2, '0')}:00';
    final amount = ((data['totalAmount'] ?? 0.0) as num).toDouble();
    final mode = (data['paymentMode'] ?? 'Cash').toString();

    final slot = slotMap.putIfAbsent(
      bucket,
      () => {
        'cash': 0.0,
        'upi': 0.0,
        'credit': 0.0,
        'total': 0.0,
      },
    );

    slot['total'] = (slot['total'] as double) + amount;
    if (mode == 'Cash') {
      slot['cash'] = (slot['cash'] as double) + amount;
    } else if (mode == 'UPI') {
      slot['upi'] = (slot['upi'] as double) + amount;
    } else if (mode == 'Credit') {
      slot['credit'] = (slot['credit'] as double) + amount;
    }
  }

  final list = slotMap.entries
      .map((entry) => {
            'slot': entry.key,
            'cash': entry.value['cash'] as double,
            'upi': entry.value['upi'] as double,
            'credit': entry.value['credit'] as double,
            'total': entry.value['total'] as double,
          })
      .toList();

  list.sort((a, b) => (a['slot'] as String).compareTo(b['slot'] as String));
  return list;
}

List<Map<String, dynamic>> legacyAnomalyList(
    Map<String, Map<String, dynamic>> dailyTotalsByDate) {
  final sortedDates = dailyTotalsByDate.keys.toList()..sort();
  if (sortedDates.length < 2) return const [];

  final anomalies = <Map<String, dynamic>>[];
  final window = sortedDates.length >= 7 ? 7 : sortedDates.length;

  for (int i = window; i < sortedDates.length; i++) {
    final date = sortedDates[i];
    final currentSales =
        (dailyTotalsByDate[date]!['totalSales'] ?? 0.0) as double;
    final priorSales = <double>[];
    for (int j = i - window; j < i; j++) {
      priorSales.add((dailyTotalsByDate[sortedDates[j]]!['totalSales'] ?? 0.0)
          as double);
    }
    final avgPrior = priorSales.isEmpty
        ? 0.0
        : priorSales.reduce((a, b) => a + b) / priorSales.length;
    if (avgPrior <= 0) continue;
    final changePct = ((currentSales - avgPrior) / avgPrior) * 100;
    if (changePct.abs() > 25) {
      anomalies.add({
        'date': date,
        'currentSales': currentSales,
        'averageSales': avgPrior,
        'changePct': changePct,
        'trend': changePct >= 0 ? 'spike' : 'drop',
      });
    }
  }

  anomalies.sort((a, b) =>
      (b['changePct'] as double).compareTo(a['changePct'] as double));
  return anomalies;
}

List<Map<String, dynamic>> legacyForecastList(
    List<FakeDoc> billDocs) {
  final now = DateTime.now();
  final forecastStart = now.subtract(const Duration(days: 30));
  final priorWeekStart = now.subtract(const Duration(days: 14));
  final recentWeekStart = now.subtract(const Duration(days: 7));
  final itemMetrics = <String, Map<String, int>>{};

  for (final doc in billDocs) {
    final data = doc.data() as Map<String, dynamic>;
    final timestamp = data['timestamp'] as Timestamp?;
    if (timestamp == null) continue;
    final billDate = timestamp.toDate();
    if (billDate.isBefore(forecastStart)) continue;

    final items = List<Map<String, dynamic>>.from(data['items'] ?? const []);
    for (final item in items) {
      final name = (item['name'] ?? 'Unknown').toString();
      final quantity = item['quantity'] is int
          ? item['quantity'] as int
          : int.tryParse(item['quantity']?.toString() ?? '') ?? 0;
      final metrics = itemMetrics.putIfAbsent(
        name,
        () => {'qty': 0, 'priorWeekQty': 0, 'recentWeekQty': 0},
      );
      metrics['qty'] = metrics['qty']! + quantity;
      if (!billDate.isBefore(priorWeekStart) &&
          billDate.isBefore(recentWeekStart)) {
        metrics['priorWeekQty'] = metrics['priorWeekQty']! + quantity;
      } else if (!billDate.isBefore(recentWeekStart)) {
        metrics['recentWeekQty'] = metrics['recentWeekQty']! + quantity;
      }
    }
  }

  final items = itemMetrics.entries
      .map((entry) => {'name': entry.key, ...entry.value})
      .toList()
    ..sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));
  final forecast = <Map<String, dynamic>>[];

  for (int i = 0; i < items.length && i < 5; i++) {
    final item = items[i];
    final avgDailyQty = (item['qty'] as int) / 30.0;
    final stockTarget = (avgDailyQty * 2.5).ceil();
    final priorWeekQty = item['priorWeekQty'] as int;
    final recentWeekQty = item['recentWeekQty'] as int;
    final trend = recentWeekQty > priorWeekQty
        ? 'Upward'
        : recentWeekQty < priorWeekQty
            ? 'Downward'
            : 'Stable';
    forecast.add({
      'name': item['name'],
      'avgDailyQty': avgDailyQty,
      'recommendedStock': stockTarget,
      'trend': trend,
    });
  }
  return forecast;
}



/// Verbatim inline aggregation from the original build(): dailyStats totals.
Map<String, Map<String, dynamic>> legacyDailyTotals(
    List<FakeDoc> dailyStatsDocs, String Function(String) dateFromId) {
  final dailyTotalsByDate = <String, Map<String, dynamic>>{};
  for (final doc in dailyStatsDocs) {
    final data = doc.data() as Map<String, dynamic>;
    final date = (data['date'] ??
            dateFromId(doc.id))
        .toString();
    if (DateTime.tryParse(date) == null) continue;
    dailyTotalsByDate.putIfAbsent(
        date,
        () => {
              'totalSales': 0.0,
              'totalCash': 0.0,
              'totalUpi': 0.0,
              'totalCredit': 0.0,
            });
    final totals = dailyTotalsByDate[date]!;
    for (final field in [
      'totalSales',
      'totalCash',
      'totalUpi',
      'totalCredit'
    ]) {
      totals[field] = (totals[field] as double) +
          ((data[field] ?? 0.0) as num).toDouble();
    }
  }


  return dailyTotalsByDate;
}

/// Verbatim month logic from the original build(): returns
/// (weeklyStats, monthlySalesMap, last6MonthKeys).
({List<MapEntry<String, Map<String, dynamic>>> weekly, Map<String, double> sales, List<String> last6})
    legacyMonthly(Map<String, Map<String, dynamic>> dailyTotalsByDate,
        List<FakeDoc> expenseDocs, String startDateStr) {
  final dailyDates = dailyTotalsByDate.keys.toList()..sort();
  final weeklyStats = dailyDates
      .where((date) => date.compareTo(startDateStr) >= 0)
      .map((date) => MapEntry(date, dailyTotalsByDate[date]!))
      .toList();

  Map<String, double> monthlySalesMap = {};
  Map<String, double> monthlyExpensesMap = {};
  for (final date in dailyDates) {
    final data = dailyTotalsByDate[date]!;
    final monthKey = date.substring(0, 7);
    monthlySalesMap[monthKey] =
        (monthlySalesMap[monthKey] ?? 0.0) +
            ((data['totalSales'] ?? 0.0) as num).toDouble();
  }

  for (var doc in expenseDocs) {
    final data = doc.data() as Map<String, dynamic>;
    final ts = data['timestamp'] as Timestamp?;
    if (ts == null) continue;
    final monthKey = BusinessTime.monthKey(ts.toDate());
    monthlyExpensesMap[monthKey] =
        (monthlyExpensesMap[monthKey] ?? 0.0) +
            ((data['amount'] ?? 0.0) as num).toDouble();
  }

  final sortedMonthKeys = {
    ...monthlySalesMap.keys,
    ...monthlyExpensesMap.keys
  }.toList()
    ..sort();
  final last6MonthKeys = sortedMonthKeys.length > 6
      ? sortedMonthKeys.sublist(sortedMonthKeys.length - 6)
      : sortedMonthKeys;


  return (weekly: weeklyStats, sales: monthlySalesMap, last6: last6MonthKeys);
}
