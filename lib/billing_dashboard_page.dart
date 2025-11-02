import 'package:flutter/material.dart';
import 'print_bill_page.dart';
import 'add_item_page.dart';
import 'logout_splash_page.dart'; // Make sure this file is in your lib/ folder
// We'll also create these two placeholder pages
import 'today_sales_page.dart';
import 'expenses_page.dart';

class BillingDashboardPage extends StatelessWidget {
  const BillingDashboardPage({super.key});

  // The Adani gradient you like
  final LinearGradient adaniGradient = const LinearGradient(
    colors: [
      Color(0xFF0066B3), // blue
      Color(0xFF6C3FB5), // purple
      Color(0xFFE91E63), // pink
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: AppBar(
          iconTheme: const IconThemeData(color: Colors.white), // 3-bar color
          flexibleSpace: Container(
            decoration: BoxDecoration(gradient: adaniGradient),
          ),
          title: const Text(
            'Cashier Dashboard',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
          elevation: 3,
        ),
      ),
      // Drawer with menu options (same as before)
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(gradient: adaniGradient),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 40, color: Colors.blue),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Cashier',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart, color: Colors.blue),
              title: const Text('Today\'s Total Sales'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const TodaySalesPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.blue),
              title: const Text('Previous Bills'),
              onTap: () {
                Navigator.pop(context);
                // We can make a 'PreviousBillsPage' next
              },
            ),
            ListTile(
              leading: const Icon(Icons.money_off, color: Colors.blue),
              title: const Text('Expenses Tracking'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ExpensesPage()));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const LogoutSplashPage()),
                );
              },
            ),
          ],
        ),
      ),
      // --- NEW DASHBOARD BODY ---
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Welcome Header
            const Text(
              'Welcome, Cashier!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF003C8F), // Dark Blue
              ),
            ),
            const SizedBox(height: 16),

            // 2. "At a Glance" Info Cards
            Row(
              children: [
                _buildStatCard(
                  icon: Icons.currency_rupee,
                  label: "Today's Sales",
                  value: "₹ 0.00", // This is dummy data for now
                  color: Colors.green,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  icon: Icons.receipt,
                  label: "Total Bills",
                  value: "0", // Dummy data
                  color: Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 3. Main Action Grid
            const Text(
              'Main Actions',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // "New Bill" card (styled with gradient)
                _buildBigTile(
                  context,
                  icon: Icons.print,
                  title: 'New Bill',
                  gradient: adaniGradient, // Highlighted card
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PrintBillPage()),
                    );
                  },
                ),
                // "Add Item" card (white)
                _buildBigTile(
                  context,
                  icon: Icons.add_box,
                  title: 'Add Item',
                  isWhite: true, // White card
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const AddItemPage()),
                    );
                  },
                ),
                // "Expenses" card (white)
                _buildBigTile(
                  context,
                  icon: Icons.money_off,
                  title: 'Log Expense',
                  isWhite: true, // White card
                  onTap: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ExpensesPage()));
                  },
                ),
                // "Previous Bills" card (white)
                _buildBigTile(
                  context,
                  icon: Icons.receipt_long,
                  title: 'Previous Bills',
                  isWhite: true, // White card
                  onTap: () {
                    // We can make a 'PreviousBillsPage' next
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // A new widget for the small "At a Glance" stat cards
  Widget _buildStatCard(
      {required IconData icon,
        required String label,
        required String value,
        required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Modified widget for the big "Action Grid" tiles
  Widget _buildBigTile(
      BuildContext context, {
        required IconData icon,
        required String title,
        required VoidCallback onTap,
        LinearGradient? gradient,
        bool isWhite = false,
      }) {
    // Define the gradient and text/icon color
    final Decoration decoration = gradient != null
        ? BoxDecoration(
      gradient: gradient,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: gradient.colors.last.withOpacity(0.4),
          blurRadius: 10,
          offset: const Offset(0, 6),
        ),
      ],
    )
        : BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Colors.black26,
          blurRadius: 8,
          offset: Offset(0, 4),
        ),
      ],
    );

    final Color contentColor =
    isWhite ? const Color(0xFF0066B3) : Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: decoration,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 60, color: contentColor),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: contentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}