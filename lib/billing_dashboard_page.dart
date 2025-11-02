import 'package:flutter/material.dart';
import 'logout_splash_page.dart';

class BillingDashboardPage extends StatelessWidget {
  const BillingDashboardPage({super.key});

  // Your Adani brand gradient
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
      // DRAWER: All non-essential items are here
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
                Navigator.pushNamed(context, '/today_sales');
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.blue),
              title: const Text('Previous Bills'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Create and navigate to '/previous_bills'
              },
            ),
            ListTile(
              leading: const Icon(Icons.money_off, color: Colors.blue),
              title: const Text('Expenses Tracking'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/expenses');
              },
            ),
            // "Add Item" is now a management task in the drawer
            ListTile(
              leading: const Icon(Icons.add_box_outlined, color: Colors.blue),
              title: const Text('Add/Edit Item'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/add_item');
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
      // BODY: Only the two most essential buttons
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // This is the "Welcome, Cashier!" and stat cards
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome, Cashier!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF003C8F), // Dark Blue
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildStatCard(
                      icon: Icons.currency_rupee,
                      label: "Today's Sales",
                      value: "₹ 0.00", // Dummy data
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
              ],
            ),
          ),
          const Divider(thickness: 1, height: 1),
          const SizedBox(height: 20),

          // Essential Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildBigTile(
              context,
              icon: Icons.receipt_long_outlined, // Changed icon
              title: 'New Bill', // Changed title
              gradient: adaniGradient,
              onTap: () {
                // This is your "Print Bill" page, which is the main billing screen
                Navigator.pushNamed(context, '/print_bill');
              },
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildBigTile(
              context,
              icon: Icons.menu_book_outlined, // New icon
              title: 'View Menu', // New button
              isWhite: true,
              onTap: () {
                // Navigate to our new menu page
                Navigator.pushNamed(context, '/view_menu');
              },
            ),
          ),
        ],
      ),
    );
  }

  // Helper for Stat Cards
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

  // Helper for Big Action Tiles
  Widget _buildBigTile(
      BuildContext context, {
        required IconData icon,
        required String title,
        required VoidCallback onTap,
        LinearGradient? gradient,
        bool isWhite = false,
      }) {
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
        width: MediaQuery.of(context).size.width * 0.9,
        height: 140,
        decoration: decoration,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 60, color: contentColor),
            const SizedBox(width: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
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