import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'today_sales_page.dart';
import 'funds_received_page.dart';
import 'admin_expense_report_page.dart';
import 'monthly_sales_breakdown_page.dart';
import 'theme.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Analytics & Reports'),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _buildAnalyticsTile(
              context,
              icon: Icons.bar_chart_rounded,
              title: "Today's Sales",
              subtitle: "View all bills and revenue for today",
              gradient: AppGradients.greenAccent,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TodaySalesPage())),
            ),
            const SizedBox(height: 16),
            _buildAnalyticsTile(
              context,
              icon: Icons.calendar_month_rounded,
              title: "Monthly Breakdown",
              subtitle: "Day-by-day sales breakdown for the month",
              gradient: AppGradients.blueAccent,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MonthlySalesBreakdownPage())),
            ),
            const SizedBox(height: 16),
            _buildAnalyticsTile(
              context,
              icon: Icons.account_balance_wallet_rounded,
              title: "Monthly Fund Report",
              subtitle: "View and update the monthly fund allocation",
              gradient: AppGradients.brand,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FundsReceivedPage(isAdmin: true))),
            ),
            const SizedBox(height: 16),
            _buildAnalyticsTile(
              context,
              icon: Icons.receipt_long_rounded,
              title: "Expense Overview",
              subtitle: "View all logged expenses grouped by month",
              gradient: AppGradients.redAccent,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AdminExpenseReportPage())),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsTile(BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: glassCard(radius: 16),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textHint, size: 24),
          ],
        ),
      ),
    );
  }
}
