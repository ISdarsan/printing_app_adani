import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'theme.dart';
import 'daily_sales_report_page.dart';

class DailySaleSummary {
  final DateTime date;
  final double total;
  DailySaleSummary({required this.date, required this.total});
}

class MonthlySalesBreakdownPage extends StatefulWidget {
  const MonthlySalesBreakdownPage({super.key});
  @override
  State<MonthlySalesBreakdownPage> createState() =>
      _MonthlySalesBreakdownPageState();
}

class _MonthlySalesBreakdownPageState extends State<MonthlySalesBreakdownPage> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  Future<void> _selectMonth(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.gradBlue,
            onPrimary: Colors.white,
            surface: AppColors.bgCard,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null &&
        (picked.month != _selectedMonth.month ||
            picked.year != _selectedMonth.year)) {
      setState(() => _selectedMonth = DateTime(picked.year, picked.month));
    }
  }

  Stream<List<DailySaleSummary>> _getDailyBreakdown() {
    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final end =
        DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);
    return FirebaseFirestore.instance
        .collection('bills')
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThanOrEqualTo: end)
        .orderBy('timestamp')
        .snapshots()
        .map((snap) {
      final Map<String, double> dailyTotals = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final date = (data['timestamp'] as Timestamp).toDate();
        final dayKey = DateFormat('yyyy-MM-dd').format(date);
        dailyTotals[dayKey] = (dailyTotals[dayKey] ?? 0) +
            (data['totalAmount'] as num).toDouble();
      }
      return dailyTotals.entries.map((e) {
        return DailySaleSummary(date: DateTime.parse(e.key), total: e.value);
      }).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Monthly Breakdown'),
      body: Column(
        children: [
          // ── Month Selector ────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: () => _selectMonth(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: glassCard(radius: 14),
                child: Row(children: [
                  const Icon(Icons.calendar_month_rounded,
                      color: AppColors.accentBlue, size: 22),
                  const SizedBox(width: 12),
                  Text(DateFormat('MMMM yyyy').format(_selectedMonth),
                      style: GoogleFonts.poppins(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        gradient: AppGradients.blueAccent,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('Change',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
          ),

          // ── Daily List ────────────────────────────────
          Expanded(
            child: StreamBuilder<List<DailySaleSummary>>(
              stream: _getDailyBreakdown(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.gradBlue));
                }
                if (!snap.hasData || snap.data!.isEmpty) {
                  return Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bar_chart,
                              size: 56, color: AppColors.textHint),
                          const SizedBox(height: 12),
                          Text('No sales data for this month',
                              style: GoogleFonts.poppins(
                                  color: AppColors.textSecondary,
                                  fontSize: 15)),
                        ]),
                  );
                }

                final days = snap.data!;
                final monthTotal = days.fold(0.0, (s, d) => s + d.total);
                final maxTotal =
                    days.map((d) => d.total).reduce((a, b) => a > b ? a : b);

                return Column(
                  children: [
                    // Month Total
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: gradientCard(
                            gradient: AppGradients.brand, radius: 16),
                        child: Row(children: [
                          const Icon(Icons.trending_up_rounded,
                              color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Month Total',
                                    style: GoogleFonts.poppins(
                                        color: Colors.white70, fontSize: 12)),
                                Text('₹${monthTotal.toStringAsFixed(0)}',
                                    style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800)),
                              ]),
                          const Spacer(),
                          Text('${days.length} days',
                              style: GoogleFonts.poppins(
                                  color: Colors.white70, fontSize: 12)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: days.length,
                        itemBuilder: (_, i) {
                          final day = days[i];
                          final pct = maxTotal > 0 ? day.total / maxTotal : 0.0;

                          return GestureDetector(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => DailySalesReportPage(
                                        selectedDate: day.date))),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              padding: const EdgeInsets.all(14),
                              decoration: glassCard(radius: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(
                                        DateFormat('EEE, MMM dd')
                                            .format(day.date),
                                        style: GoogleFonts.poppins(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                    const Spacer(),
                                    Text('₹${day.total.toStringAsFixed(0)}',
                                        style: GoogleFonts.poppins(
                                            color: AppColors.accentGreen,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right,
                                        color: AppColors.textHint, size: 16),
                                  ]),
                                  const SizedBox(height: 8),
                                  // Mini bar
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      backgroundColor: AppColors.bgDivider,
                                      valueColor:
                                          AlwaysStoppedAnimation(pct > 0.7
                                              ? AppColors.accentGreen
                                              : pct > 0.4
                                                  ? AppColors.accentBlue
                                                  : AppColors.accentOrange),
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
