import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'theme.dart';
import 'business_time.dart';
import 'canteen_provider.dart';

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatCurrency(double value) =>
      '₹${value.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  List<Map<String, dynamic>> _buildItemPerformance(
      List<QueryDocumentSnapshot> billDocs) {
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

  List<Map<String, dynamic>> _buildStaffPerformance(
      List<QueryDocumentSnapshot> billDocs) {
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

  List<Map<String, dynamic>> _buildTimeSlotData(
      List<QueryDocumentSnapshot> billDocs) {
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

  List<Map<String, dynamic>> _buildAnomalyList(
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

  List<Map<String, dynamic>> _buildForecastList(
      List<QueryDocumentSnapshot> billDocs) {
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

  @override
  Widget build(BuildContext context) {
    final startDateStr = BusinessTime.dateKeyDaysAgo(DateTime.now(), 7);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(
        title: 'Analytics Insights',
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('bills').snapshots(),
        builder: (context, billsSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance.collection('dailyStats').snapshots(),
            builder: (context, statsSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('expenses')
                    .snapshots(),
                builder: (context, expensesSnapshot) {
                  if (billsSnapshot.connectionState ==
                          ConnectionState.waiting ||
                      statsSnapshot.connectionState ==
                          ConnectionState.waiting ||
                      expensesSnapshot.connectionState ==
                          ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accentBlue));
                  }

                  final billDocs = (billsSnapshot.data?.docs ?? [])
                      .where((doc) => CanteenProvider.matchesSelectedCanteen(
                          doc.data() as Map<String, dynamic>))
                      .toList();
                  final dailyStatsDocs = (statsSnapshot.data?.docs ?? [])
                      .where((doc) => CanteenProvider.matchesSelectedCanteen(
                          doc.data() as Map<String, dynamic>))
                      .toList();
                  final expenseDocs = (expensesSnapshot.data?.docs ?? [])
                      .where((doc) => CanteenProvider.matchesSelectedCanteen(
                          doc.data() as Map<String, dynamic>))
                      .toList();

                  final dailyTotalsByDate = <String, Map<String, dynamic>>{};
                  for (final doc in dailyStatsDocs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final date = (data['date'] ??
                            CanteenProvider.dateFromDailyStatsDocumentId(
                                doc.id))
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

                  final itemPerformance = _buildItemPerformance(billDocs);
                  final staffPerformance = _buildStaffPerformance(billDocs);
                  final timeSlotData = _buildTimeSlotData(billDocs);
                  final anomalyList = _buildAnomalyList(dailyTotalsByDate);
                  final forecastList = _buildForecastList(billDocs);

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

                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.bgCard,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              indicator: BoxDecoration(
                                gradient: AppGradients.blueAccent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              labelColor: Colors.white,
                              unselectedLabelColor: AppColors.textSecondary,
                              labelStyle: AppText.style(
                                  fontSize: 11, fontWeight: FontWeight.bold),
                              tabs: const [
                                Tab(text: 'Weekly'),
                                Tab(text: 'Monthly'),
                                Tab(text: 'Payments'),
                                Tab(text: 'Profit'),
                                Tab(text: 'Ops'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 420,
                          child: TabBarView(
                            controller: _tabController,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _buildWeeklyPage(weeklyStats),
                              _buildMonthlyPage(
                                  last6MonthKeys, monthlySalesMap),
                              _buildPaymentAndTimePage(timeSlotData),
                              _buildProfitPage(itemPerformance),
                              _buildOpsPage(
                                  staffPerformance, anomalyList, forecastList),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPaymentAndTimePage(List<Map<String, dynamic>> slotData) {
    if (slotData.isEmpty) {
      return _buildNoDataPlaceholder('No timeslot data available');
    }

    final maxTotal = slotData.fold<double>(
        0, (max, item) => item['total'] > max ? item['total'] : max);
    final groups = slotData
        .map((slot) => BarChartGroupData(
              x: slotData.indexOf(slot),
              barRods: [
                BarChartRodData(
                  toY: (slot['cash'] as double),
                  color: AppColors.accentGreen,
                  width: 6,
                  borderRadius: BorderRadius.circular(2),
                ),
                BarChartRodData(
                  toY: (slot['upi'] as double),
                  color: AppColors.accentBlue,
                  width: 6,
                  borderRadius: BorderRadius.circular(2),
                ),
                BarChartRodData(
                  toY: (slot['credit'] as double),
                  color: AppColors.accentOrange,
                  width: 6,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ))
        .toList();

    return _buildChartContainer(
      title: 'Payment Mix by Time Slot',
      subtitle: 'Cash, UPI and credit activity by hour',
      chart: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _chartLegend('Cash', AppColors.accentGreen),
              const SizedBox(width: 10),
              _chartLegend('UPI', AppColors.accentBlue),
              const SizedBox(width: 10),
              _chartLegend('Credit', AppColors.accentOrange),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxTotal == 0 ? 100 : maxTotal * 1.15,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                      color: AppColors.bgDivider.withValues(alpha: 0.5),
                      strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval:
                          maxTotal <= 100 ? 20 : (maxTotal / 5).ceilToDouble(),
                      getTitlesWidget: (value, meta) {
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            value >= 1000
                                ? '${(value / 1000).toStringAsFixed(1)}k'
                                : value.toStringAsFixed(0),
                            style: AppText.style(
                              color: AppColors.textHint,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= slotData.length) {
                          return const SizedBox();
                        }
                        final slot = slotData[index]['slot'] as String;
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            slot,
                            style: AppText.style(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: groups,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitPage(List<Map<String, dynamic>> itemPerformance) {
    if (itemPerformance.isEmpty) {
      return _buildNoDataPlaceholder('No item performance data');
    }

    final topItems = itemPerformance.take(6).toList();
    final totalRevenue = itemPerformance.fold<double>(
        0, (runningTotal, item) => runningTotal + (item['revenue'] as double));

    return _buildChartContainer(
      title: 'Item Profit & Contribution',
      subtitle: 'Profit uses only bills with a recorded item cost',
      chart: ListView.builder(
        itemCount: topItems.length,
        padding: EdgeInsets.zero,
        itemBuilder: (context, index) {
          final item = topItems[index];
          final revenue = item['revenue'] as double;
          final profit = item['profit'] as double;
          final knownCostQty = item['knownCostQty'] as int;
          final unknownCostQty = item['unknownCostQty'] as int;
          final ratio = totalRevenue > 0 ? revenue / totalRevenue : 0.0;
          final label = (index + 1).toString();

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.bgDivider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('$label. ${item['name']}',
                        style: AppText.style(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(_formatCurrency(revenue),
                        style: AppText.style(
                            color: AppColors.accentBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Qty: ${item['qty']}',
                        style: AppText.style(
                            color: AppColors.textSecondary, fontSize: 11)),
                    const SizedBox(width: 18),
                    Text(
                        knownCostQty == 0
                            ? 'Profit: Unknown'
                            : 'Known-cost profit: ${_formatCurrency(profit)}',
                        style: AppText.style(
                            color: AppColors.accentGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                if (unknownCostQty > 0) ...[
                  const SizedBox(height: 4),
                  Text('$unknownCostQty units have no recorded cost',
                      style: AppText.style(
                          color: AppColors.accentOrange, fontSize: 10)),
                ],
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: AppColors.bgDivider,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.accentBlue),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOpsPage(
      List<Map<String, dynamic>> staffPerformance,
      List<Map<String, dynamic>> anomalyList,
      List<Map<String, dynamic>> forecastList) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInsightCard(
            title: 'Staff Sales Comparison',
            child: Column(
              children: staffPerformance.isEmpty
                  ? [
                      Text('No staff sales recorded yet.',
                          style: AppText.style(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ]
                  : List.generate(
                      staffPerformance.length > 5 ? 5 : staffPerformance.length,
                      (index) {
                      final staff = staffPerformance[index];
                      final total = staff['sales'] as double;
                      final max = staffPerformance.first['sales'] as double;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                    child: Text(staff['name'].toString(),
                                        style: AppText.style(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600))),
                                Text(_formatCurrency(total),
                                    style: AppText.style(
                                        color: AppColors.accentBlue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: max > 0
                                    ? (total / max).clamp(0.0, 1.0)
                                    : 0.0,
                                minHeight: 7,
                                backgroundColor: AppColors.bgDivider,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    AppColors.accentGreen),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
            ),
          ),
          const SizedBox(height: 14),
          _buildInsightCard(
            title: 'Daily Anomaly Detection',
            child: anomalyList.isEmpty
                ? Text('No unusual sales variation detected in recent days.',
                    style: AppText.style(
                        color: AppColors.textSecondary, fontSize: 12))
                : Column(
                    children: anomalyList.take(4).map((item) {
                      final isSpike = item['trend'] == 'spike';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSpike
                              ? AppColors.accentGreen.withValues(alpha: 0.08)
                              : AppColors.accentOrange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSpike
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              color: isSpike
                                  ? AppColors.accentGreen
                                  : AppColors.accentOrange,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item['date']} • ${isSpike ? 'sales spike' : 'sales dip'}',
                                    style: AppText.style(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '${_formatCurrency(item['currentSales'] as double)} vs ${_formatCurrency(item['averageSales'] as double)} (${item['changePct'].toStringAsFixed(1)}%)',
                                    style: AppText.style(
                                        color: AppColors.textSecondary,
                                        fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 14),
          _buildInsightCard(
            title: 'Forecasted Demand & Prep Suggestion',
            child: forecastList.isEmpty
                ? Text('No demand forecast available yet.',
                    style: AppText.style(
                        color: AppColors.textSecondary, fontSize: 12))
                : Column(
                    children: forecastList.map((item) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.bgDivider),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['name'].toString(),
                                      style: AppText.style(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                  Text(
                                      'Avg/day: ${((item['avgDailyQty'] as double)).toStringAsFixed(1)} • Suggested prep: ${item['recommendedStock']}',
                                      style: AppText.style(
                                          color: AppColors.textSecondary,
                                          fontSize: 10)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.accentBlue
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(item['trend'].toString(),
                                  style: AppText.style(
                                      color: AppColors.accentBlue,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: glassCard(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppText.style(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildWeeklyPage(
      List<MapEntry<String, Map<String, dynamic>>> weeklyDocs) {
    if (weeklyDocs.isEmpty) return _buildNoDataPlaceholder('No weekly data');

    List<FlSpot> spots = [];
    double maxVal = 100.0;
    for (int i = 0; i < weeklyDocs.length; i++) {
      final data = weeklyDocs[i].value;
      final sales = ((data['totalSales'] ?? 0.0) as num).toDouble();
      spots.add(FlSpot(i.toDouble(), sales));
      if (sales > maxVal) maxVal = sales;
    }
    maxVal *= 1.15;
    double yInterval = (maxVal / 5).ceilToDouble();
    if (yInterval < 10) yInterval = 10;

    return _buildChartContainer(
      title: 'Weekly Sales Revenue',
      subtitle: 'Daily sales timeline (last 7 days)',
      chart: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (val) => FlLine(
                color: AppColors.bgDivider.withValues(alpha: 0.5),
                strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 30,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= weeklyDocs.length) {
                    return const SizedBox();
                  }
                  final date = DateTime.parse(weeklyDocs[idx].key);
                  return SideTitleWidget(
                      meta: meta,
                      space: 8,
                      child: Text(DateFormat('dd MMM').format(date),
                          style: AppText.style(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w500)));
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 45,
                interval: yInterval,
                getTitlesWidget: (val, meta) {
                  return SideTitleWidget(
                      meta: meta,
                      space: 6,
                      child: Text(
                          val >= 1000
                              ? '${(val / 1000).toStringAsFixed(1)}k'
                              : val.toStringAsFixed(0),
                          style: AppText.style(
                              color: AppColors.textHint,
                              fontSize: 10,
                              fontWeight: FontWeight.w500)));
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (weeklyDocs.length - 1).toDouble(),
          minY: 0,
          maxY: maxVal,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              gradient: const LinearGradient(
                  colors: [Color(0xFF00E5A0), AppColors.accentGreen]),
              barWidth: 4,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    AppColors.accentGreen.withValues(alpha: 0.15),
                    AppColors.accentGreen.withValues(alpha: 0.0)
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyPage(
      List<String> monthKeys, Map<String, double> salesMap) {
    if (monthKeys.isEmpty) return _buildNoDataPlaceholder('No monthly data');

    List<BarChartGroupData> barGroups = [];
    double maxVal = 100.0;

    for (int i = 0; i < monthKeys.length; i++) {
      final key = monthKeys[i];
      final val = salesMap[key] ?? 0.0;
      if (val > maxVal) maxVal = val;

      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: val,
            gradient: const LinearGradient(
                colors: [AppColors.gradBlue, AppColors.accentBlue]),
            width: 18,
            borderRadius: BorderRadius.circular(4),
          )
        ],
      ));
    }
    maxVal *= 1.15;
    double yInterval = (maxVal / 5).ceilToDouble();
    if (yInterval < 10) yInterval = 10;

    return _buildChartContainer(
      title: 'Monthly Sales Revenue',
      subtitle: 'Comparison over the last 6 months',
      chart: BarChart(
        BarChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (val) => FlLine(
                color: AppColors.bgDivider.withValues(alpha: 0.5),
                strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= monthKeys.length) {
                    return const SizedBox();
                  }
                  final date = DateFormat('yyyy-MM').parse(monthKeys[idx]);
                  return SideTitleWidget(
                      meta: meta,
                      child: Text(DateFormat('MMM yy').format(date),
                          style: AppText.style(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w500)));
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 45,
                interval: yInterval,
                getTitlesWidget: (val, meta) {
                  return SideTitleWidget(
                      meta: meta,
                      space: 6,
                      child: Text(
                          val >= 1000
                              ? '${(val / 1000).toStringAsFixed(1)}k'
                              : val.toStringAsFixed(0),
                          style: AppText.style(
                              color: AppColors.textHint,
                              fontSize: 10,
                              fontWeight: FontWeight.w500)));
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
          maxY: maxVal,
        ),
      ),
    );
  }

  Widget _buildChartContainer(
      {required String title,
      required String subtitle,
      required Widget chart}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: glassCard(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppText.style(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          Text(subtitle,
              style:
                  AppText.style(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 20),
          Expanded(child: chart),
        ],
      ),
    );
  }

  Widget _buildNoDataPlaceholder(String title) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: glassCard(radius: 20),
        alignment: Alignment.center,
        child: Text(title,
            style: AppText.style(color: AppColors.textSecondary, fontSize: 14)),
      ),
    );
  }

  Widget _chartLegend(String label, Color color) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: AppText.style(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}
