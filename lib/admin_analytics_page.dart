import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'theme.dart';

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
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final startDateStr = DateFormat('yyyy-MM-dd').format(sevenDaysAgo);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(
        title: "Analytics Insights",
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('dailyStats').snapshots(),
        builder: (context, statsSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('expenses').snapshots(),
            builder: (context, expensesSnapshot) {
              if (statsSnapshot.connectionState == ConnectionState.waiting ||
                  expensesSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.accentBlue));
              }

              final dailyStatsDocs = statsSnapshot.data?.docs ?? [];
              final expenseDocs = expensesSnapshot.data?.docs ?? [];

              // Sort dailyStats chronologically
              dailyStatsDocs.sort((a, b) => a.id.compareTo(b.id));

              // weekly data (last 7 days)
              final weeklyDocs = dailyStatsDocs
                  .where((doc) => doc.id.compareTo(startDateStr) >= 0)
                  .toList();

              // Monthly aggregation
              Map<String, double> monthlySalesMap = {};
              Map<String, double> monthlyExpensesMap = {};

              for (var doc in dailyStatsDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final monthKey = doc.id.substring(0, 7); // yyyy-MM
                monthlySalesMap[monthKey] = (monthlySalesMap[monthKey] ?? 0.0) +
                    ((data['totalSales'] ?? 0.0) as num).toDouble();
              }

              for (var doc in expenseDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final ts = data['timestamp'] as Timestamp?;
                if (ts == null) continue;
                final monthKey = DateFormat('yyyy-MM').format(ts.toDate());
                monthlyExpensesMap[monthKey] = (monthlyExpensesMap[monthKey] ?? 0.0) +
                    ((data['amount'] ?? 0.0) as num).toDouble();
              }

              final sortedMonthKeys = {
                ...monthlySalesMap.keys,
                ...monthlyExpensesMap.keys
              }.toList();
              sortedMonthKeys.sort();
              final last6MonthKeys = sortedMonthKeys.length > 6
                  ? sortedMonthKeys.sublist(sortedMonthKeys.length - 6)
                  : sortedMonthKeys;

              return SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    // Navigation Segmented Tabs
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
                          labelStyle: GoogleFonts.poppins(
                              fontSize: 11, fontWeight: FontWeight.bold),
                          tabs: const [
                            Tab(text: 'Weekly'),
                            Tab(text: 'Monthly'),
                            Tab(text: 'Payments'),
                            Tab(text: 'Sales/Exp'),
                            Tab(text: 'Top Items'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Chart Container with Fixed Height to avoid looking stretched
                    SizedBox(
                      height: 380,
                      child: TabBarView(
                        controller: _tabController,
                        physics: const NeverScrollableScrollPhysics(), // avoid horizontal scroll conflict
                        children: [
                          _buildWeeklyPage(weeklyDocs),
                          _buildMonthlyPage(last6MonthKeys, monthlySalesMap),
                          _buildPaymentBreakdownPage(weeklyDocs),
                          _buildRevenueVsExpensesPage(
                              last6MonthKeys, monthlySalesMap, monthlyExpensesMap),
                          _buildTopItemsPage(),
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
      ),
    );
  }

  Widget _buildWeeklyPage(List<DocumentSnapshot> weeklyDocs) {
    if (weeklyDocs.isEmpty) return _buildNoDataPlaceholder('No weekly data');

    List<FlSpot> spots = [];
    double maxVal = 100.0;
    for (int i = 0; i < weeklyDocs.length; i++) {
      final data = weeklyDocs[i].data() as Map<String, dynamic>;
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
                color: AppColors.bgDivider.withValues(alpha: 0.5), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 30,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= weeklyDocs.length) return const SizedBox();
                  final date = DateTime.parse(weeklyDocs[idx].id);
                  return SideTitleWidget(
                      meta: meta,
                      space: 8,
                      child: Text(DateFormat('dd MMM').format(date),
                          style: GoogleFonts.poppins(
                              color: AppColors.textSecondary,
                              fontSize: 9,
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
                          style: GoogleFonts.poppins(
                              color: AppColors.textHint,
                              fontSize: 9,
                              fontWeight: FontWeight.w500)));
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                  colors: [Color(0xFF00E5A0), Color(0xFF00C980)]),
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

  Widget _buildMonthlyPage(List<String> monthKeys, Map<String, double> salesMap) {
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
                colors: [Color(0xFF2196F3), Color(0xFF4FC3F7)]),
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
                color: AppColors.bgDivider.withValues(alpha: 0.5), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx < 0 || idx >= monthKeys.length) return const SizedBox();
                  final date = DateFormat('yyyy-MM').parse(monthKeys[idx]);
                  return SideTitleWidget(
                      meta: meta,
                      child: Text(DateFormat('MMM yy').format(date),
                          style: GoogleFonts.poppins(
                              color: AppColors.textSecondary,
                              fontSize: 9,
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
                          style: GoogleFonts.poppins(
                              color: AppColors.textHint,
                              fontSize: 9,
                              fontWeight: FontWeight.w500)));
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
          maxY: maxVal,
        ),
      ),
    );
  }

  Widget _buildPaymentBreakdownPage(List<DocumentSnapshot> weeklyDocs) {
    if (weeklyDocs.isEmpty) return _buildNoDataPlaceholder('No transactions');

    double cashTotal = 0;
    double upiTotal = 0;
    double creditTotal = 0;

    for (var doc in weeklyDocs) {
      final data = doc.data() as Map<String, dynamic>;
      cashTotal += ((data['totalCash'] ?? 0.0) as num).toDouble();
      upiTotal += ((data['totalUpi'] ?? 0.0) as num).toDouble();
      creditTotal += ((data['totalCredit'] ?? 0.0) as num).toDouble();
    }

    final total = cashTotal + upiTotal + creditTotal;
    if (total == 0) return _buildNoDataPlaceholder('No sales logged');

    return _buildChartContainer(
      title: 'Payment Breakdown',
      subtitle: 'Breakdown of payment modes (Last 7 Days)',
      chart: Row(
        children: [
          Expanded(
            flex: 2,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 35,
                sections: [
                  PieChartSectionData(
                    color: AppColors.accentGreen,
                    value: cashTotal,
                    title: '${((cashTotal / total) * 100).toStringAsFixed(0)}%',
                    radius: 20,
                    titleStyle: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  PieChartSectionData(
                    color: AppColors.accentBlue,
                    value: upiTotal,
                    title: '${((upiTotal / total) * 100).toStringAsFixed(0)}%',
                    radius: 20,
                    titleStyle: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  PieChartSectionData(
                    color: AppColors.accentOrange,
                    value: creditTotal,
                    title: '${((creditTotal / total) * 100).toStringAsFixed(0)}%',
                    radius: 20,
                    titleStyle: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLegendItem('💵 Cash', cashTotal, AppColors.accentGreen),
                const SizedBox(height: 12),
                _buildLegendItem('📱 UPI', upiTotal, AppColors.accentBlue),
                const SizedBox(height: 12),
                _buildLegendItem('💳 Credit', creditTotal, AppColors.accentOrange),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildRevenueVsExpensesPage(List<String> monthKeys,
      Map<String, double> salesMap, Map<String, double> expensesMap) {
    if (monthKeys.isEmpty) return _buildNoDataPlaceholder('No data');

    List<BarChartGroupData> barGroups = [];
    double maxVal = 100.0;

    for (int i = 0; i < monthKeys.length; i++) {
      final key = monthKeys[i];
      final sales = salesMap[key] ?? 0.0;
      final expenses = expensesMap[key] ?? 0.0;

      if (sales > maxVal) maxVal = sales;
      if (expenses > maxVal) maxVal = expenses;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: sales,
              color: AppColors.accentBlue,
              width: 10,
              borderRadius: BorderRadius.circular(2),
            ),
            BarChartRodData(
              toY: expenses,
              color: AppColors.accentRed,
              width: 10,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ),
      );
    }
    maxVal *= 1.15;
    double yInterval = (maxVal / 5).ceilToDouble();
    if (yInterval < 10) yInterval = 10;

    return _buildChartContainer(
      title: 'Sales vs Expenses',
      subtitle: 'Comparison of monthly revenues & expenditures',
      chart: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _chartLegend('Sales', AppColors.accentBlue),
              const SizedBox(width: 12),
              _chartLegend('Expenses', AppColors.accentRed),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: BarChart(
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
                                style: GoogleFonts.poppins(
                                    color: AppColors.textSecondary,
                                    fontSize: 9,
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
                                style: GoogleFonts.poppins(
                                    color: AppColors.textHint,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500)));
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: barGroups,
                maxY: maxVal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartContainer(
      {required String title, required String subtitle, required Widget chart}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: glassCard(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.poppins(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          Text(subtitle,
              style: GoogleFonts.poppins(
                  color: AppColors.textSecondary, fontSize: 11)),
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
            style: GoogleFonts.poppins(
                color: AppColors.textSecondary, fontSize: 14)),
      ),
    );
  }

  Widget _buildLegendItem(String label, double amount, Color color) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 11)),
            Text('₹${amount.toStringAsFixed(0)}',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        )
      ],
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
            style:
                GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }

  Widget _buildTopItemsPage() {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bills')
          .where('timestamp', isGreaterThanOrEqualTo: thirtyDaysAgo)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accentBlue));
        }

        final docs = snapshot.data?.docs ?? [];
        Map<String, int> itemCounts = {};
        int totalQuantity = 0;

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
          for (var item in items) {
            final name = item['name'] ?? 'Unknown';
            final qty = (item['quantity'] ?? 0) as int;
            itemCounts[name] = (itemCounts[name] ?? 0) + qty;
            totalQuantity += qty;
          }
        }

        final sortedItems = itemCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        final top5 = sortedItems.length > 5 ? sortedItems.sublist(0, 5) : sortedItems;

        if (top5.isEmpty) {
          return _buildNoDataPlaceholder('No sales in the last 30 days');
        }

        return _buildChartContainer(
          title: 'Top Selling Menu Items',
          subtitle: 'Best selling portions in the last 30 days',
          chart: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: top5.length,
            itemBuilder: (context, i) {
              final item = top5[i];
              final name = item.key;
              final qty = item.value;
              final pct = totalQuantity > 0 ? (qty / totalQuantity) : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${i + 1}. $name',
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        Text('$qty portions',
                            style: GoogleFonts.poppins(color: AppColors.accentBlue, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 8,
                        backgroundColor: AppColors.bgDivider,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentGreen),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}