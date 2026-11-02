import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'theme.dart';
import 'state_views.dart';
import 'business_time.dart';
import 'analytics_calc.dart';
import 'analytics_loader.dart';
import 'paged_fetch.dart';
import 'canteen_selector.dart';

/// Loads the analytics for a canteen. Injectable so the page (and its charts)
/// can be tested without Firebase.
typedef AnalyticsLoadFn = Future<AnalyticsResult> Function(
  AnalyticsRange range,
  String canteenId, {
  bool Function()? isCancelled,
  void Function(String stage, int count)? onProgress,
});

class AdminAnalyticsPage extends StatefulWidget {
  final AnalyticsLoadFn? loadAnalytics;
  final Stream<List<CanteenChoice>>? canteenChoices; // tests only
  const AdminAnalyticsPage({super.key, this.loadAnalytics, this.canteenChoices});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AnalyticsRange _range = AnalyticsRange.defaultRange;
  String _canteen = kAllCanteens; // admin: all canteens, or one
  // The top bar is built in two layouts (loading / loaded); a stable key keeps
  // the canteen selector (and its listener) alive across them.
  final GlobalKey _canteenSelectorKey = GlobalKey();
  AnalyticsResult? _result;
  Object? _error;
  bool _loading = false;
  String _progress = '';
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _load();
  }

  @override
  void dispose() {
    _generation++; // cancels any load still running
    _tabController.dispose();
    super.dispose();
  }

  String _formatCurrency(double value) =>
      '₹${value.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  Future<void> _load() async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _progress = 'Starting...';
    });
    try {
      final loader = widget.loadAnalytics ??
          (range, canteenId, {isCancelled, onProgress}) =>
              AnalyticsLoader(FirebaseFirestore.instance).load(range,
                  canteenId: canteenId,
                  isCancelled: isCancelled,
                  onProgress: onProgress);
      final r = await loader(
        _range,
        _canteen,
        isCancelled: () => !mounted || gen != _generation,
        onProgress: (stage, n) {
          if (mounted && gen == _generation) {
            setState(() => _progress = 'Reading $stage: $n');
          }
        },
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _result = r;
        _loading = false;
      });
    } on PagedFetchCancelled {
      // Superseded by a newer load or the page was closed.
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Widget _rangeBar() {
    final r = _result;
    String status;
    if (_loading) {
      status = _progress;
    } else if (r != null) {
      status = '${r.billsUsed} bills · ${r.dailyStatsRead} daily records · '
          'updated ${DateFormat('hh:mm a').format(BusinessTime.wallClock(r.loadedAt))}'
          '${r.truncated ? ' · INCOMPLETE (row limit reached)' : ''}';
    } else {
      status = '';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Which canteen to analyse: all of them together, or one.
          CanteenSelector(
            key: _canteenSelectorKey,
            value: _canteen,
            label: 'Canteen',
            choicesStream: widget.canteenChoices,
            margin: const EdgeInsets.only(bottom: 10),
            onChanged: (c) {
              if (c.id == _canteen) return;
              setState(() => _canteen = c.id);
              _load();
            },
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in AnalyticsRange.presets)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p.label,
                          style: AppText.style(
                              fontSize: 12,
                              color: p.id == _range.id
                                  ? Colors.white
                                  : AppColors.textSecondary)),
                      selected: p.id == _range.id,
                      selectedColor: AppColors.accentBlue,
                      backgroundColor: AppColors.bgCard,
                      onSelected: _loading
                          ? null
                          : (_) {
                              setState(() => _range = p);
                              _load();
                            },
                    ),
                  ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppColors.textSecondary),
                  onPressed: _loading ? null : _load,
                ),
              ],
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                  minHeight: 2, color: AppColors.accentBlue),
            ),
          if (status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(status,
                  style: AppText.style(
                      color: AppColors.textSecondary, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(
        title: 'Analytics Insights',
        centerTitle: true,
      ),
      body: r == null
          ? Column(children: [
              _rangeBar(),
              Expanded(
                child: Center(
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Could not load analytics.\n${friendlyErrorMessage(_error)}',
                                  textAlign: TextAlign.center,
                                  style: AppText.style(
                                      color: AppColors.accentRed,
                                      fontSize: 13)),
                              const SizedBox(height: 12),
                              TextButton(
                                  onPressed: _load, child: const Text('Retry')),
                            ],
                          ),
                        )
                      : const CircularProgressIndicator(
                          color: AppColors.accentBlue),
                ),
              ),
            ])
          : SingleChildScrollView(
              child: Column(
                children: [
                  _rangeBar(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Text('Refresh failed, showing the earlier figures. ${friendlyErrorMessage(_error)}',
                          style: AppText.style(
                              color: AppColors.accentRed, fontSize: 11)),
                    ),
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
                        _buildWeeklyPage(r.weekly),
                        _buildMonthlyPage(r.last6MonthKeys, r.monthlySales),
                        _buildPaymentAndTimePage(r.timeSlots),
                        _buildProfitPage(r.itemPerformance),
                        _buildOpsPage(
                            r.staffPerformance, r.anomalies, r.forecast),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
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
                    // the name takes the free space and wraps; the amount never
                    // gets pushed off the screen by a long item name
                    Expanded(
                      child: Text('$label. ${item['name']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.style(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
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
                    Flexible(
                      child: Text(
                          knownCostQty == 0
                              ? 'Profit: Unknown'
                              : 'Known-cost profit: ${_formatCurrency(profit)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.style(
                              color: AppColors.accentGreen,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
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
                  final date = DateTime.tryParse(weeklyDocs[idx].key);
                  if (date == null) return const SizedBox();
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
