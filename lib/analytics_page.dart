import 'package:flutter/material.dart';
import 'today_sales_page.dart';
import 'funds_received_page.dart'; // This is the 'Monthly Cashflow Report'
import 'expenses_page.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Analytics & Reports"),
        backgroundColor: theme.primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _buildAnalyticsTile(
              context,
              icon: Icons.bar_chart,
              title: "Today's Sales",
              subtitle: "View sales for the current day",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TodaySalesPage()),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildAnalyticsTile(
              context,
              icon: Icons.account_balance_wallet,
              title: "Monthly Cashflow",
              subtitle: "View funds received vs. expenses",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FundsReceivedPage()),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildAnalyticsTile(
              context,
              icon: Icons.money_off,
              title: "Log New Expense",
              subtitle: "Add a new expense record",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ExpensesPage()),
                );
              },
            ),
            // You can add more report links here as you build them
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsTile(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required VoidCallback onTap,
      }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        leading: Icon(icon, size: 40, color: Theme.of(context).primaryColor),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}