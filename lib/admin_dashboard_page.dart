import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // For user email
import 'package:cloud_firestore/cloud_firestore.dart'; // For live stats
import 'package:intl/intl.dart'; // For date formatting
import 'logout_splash_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final LinearGradient adaniGradient = const LinearGradient(
    colors: [
      Color(0xFF0066B3), // blue
      Color(0xFF6C3FB5), // purple
      Color(0xFFE91E63), // pink
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // --- STREAMS FOR LIVE ADMIN STATS ---

  // 1. Stream for Today's Sales (from dailyStats doc)
  Stream<DocumentSnapshot> _getDailyStatsStream() {
    String todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return FirebaseFirestore.instance
        .collection('dailyStats')
        .doc(todayId)
        .snapshots();
  }

  // 2. Stream for This Month's Sales (calculates from all bills)
  Stream<double> _getMonthlySalesStream() {
    DateTime now = DateTime.now();
    DateTime startOfMonth = DateTime(now.year, now.month, 1);
    DateTime endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    return FirebaseFirestore.instance
        .collection('bills')
        .where('timestamp', isGreaterThanOrEqualTo: startOfMonth)
        .where('timestamp', isLessThanOrEqualTo: endOfMonth)
        .snapshots()
        .map((snapshot) {
      double total = 0.0;
      for (var doc in snapshot.docs) {
        total += (doc.data()['totalAmount'] as num).toDouble();
      }
      return total;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: AppBar(
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: Container(
            decoration: BoxDecoration(gradient: adaniGradient),
          ),
          title: const Text(
            'Admin Dashboard',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
          elevation: 0,
        ),
      ),
      // --- DRAWER (MODIFIED) ---
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(gradient: adaniGradient),
              accountName: const Text(
                'Canteen Admin',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              accountEmail: Text(
                _currentUser?.email ?? 'Loading...',
                style: const TextStyle(color: Colors.white70),
              ),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.admin_panel_settings,
                    size: 40, color: Color(0xFF0066B3)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month, color: Colors.blue),
              title: const Text('Monthly Cashflow'),
              onTap: () {
                Navigator.pop(context);
                // This is the old page (Income vs Expense)
                Navigator.pushNamed(context, '/funds_received');
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.blue),
              title: const Text('View All Bills'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/all_bills_page');
              },
            ),

            // --- MODIFIED "Profile" to "Download Report" ---
            ListTile(
              leading: const Icon(Icons.download, color: Colors.grey),
              title: const Text('Download Report'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Add functionality to download reports
              },
            ),
            // ---------------------------------------------

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
      // --- BODY (MODIFIED) ---
      body: Stack(
        children: [
          // --- CURVED BACKGROUND ---
          ClipPath(
            clipper: _BottomCurveClipper(),
            child: Container(
              height: 220,
              decoration: BoxDecoration(gradient: adaniGradient),
            ),
          ),
          // --- MAIN CONTENT ---
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- WELCOME TEXT ---
                  const Text(
                    'Welcome, Admin!',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Here is the Canteen Sales summary.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- LIVE STATS CARDS (MODIFIED) ---
                  Row(
                    children: [
                      // --- CARD 1: MONTHLY SALES ---
                      StreamBuilder<double>(
                          stream: _getMonthlySalesStream(),
                          builder: (context, snapshot) {
                            return _buildStatCard(
                                icon: Icons.calendar_month,
                                label: "This Month's Sales",
                                value:
                                "₹ ${snapshot.data?.toStringAsFixed(2) ?? '0.00'}",
                                color: Colors.blue,
                                isExpanded: true,
                                onTap: () {
                                  // --- THIS IS THE FIX ---
                                  // Navigate to the new monthly breakdown page
                                  Navigator.pushNamed(
                                      context, '/monthly_sales_breakdown');
                                  // -----------------------
                                });
                          }),
                      const SizedBox(width: 16),

                      // --- CARD 2: TODAY'S SALES ---
                      StreamBuilder<DocumentSnapshot>(
                          stream: _getDailyStatsStream(),
                          builder: (context, snapshot) {
                            String sales = "₹ 0.00";
                            if (snapshot.hasData && snapshot.data!.exists) {
                              final data =
                              snapshot.data!.data() as Map<String, dynamic>;
                              sales =
                              "₹ ${data['totalSales']?.toStringAsFixed(2) ?? '0.00'}";
                            }
                            return _buildStatCard(
                                icon: Icons.currency_rupee,
                                label: "Today's Sales",
                                value: sales,
                                color: Colors.green,
                                isExpanded: true,
                                onTap: () {
                                  // Navigate to the Daily Report page
                                  Navigator.pushNamed(
                                      context, '/daily_sales_report');
                                });
                          }),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // --- ACTION GRID (MODIFIED) ---
                  const Text(
                    'Management Controls',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF003C8F), // Dark Blue
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
                      _buildBigTile(
                        context,
                        icon: Icons.menu_book,
                        title: 'Menu',
                        gradient: adaniGradient,
                        onTap: () {
                          // Re-use the menu view page
                          Navigator.pushNamed(context, '/view_menu');
                        },
                      ),

                      // --- REPLACED "Manage Staff" with "Analytics" ---
                      _buildBigTile(
                        context,
                        icon: Icons.analytics,
                        title: 'Analytics',
                        isWhite: true,
                        onTap: () {
                          Navigator.pushNamed(context, '/admin_analytics');
                        },
                      ),

                      _buildBigTile(
                        context,
                        icon: Icons.send,
                        title: 'Send Notification',
                        isWhite: true,
                        onTap: () {
                          // TODO: Create and navigate to '/send_notification'
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper for Stat Cards
  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool isExpanded = false,
    VoidCallback? onTap,
  }) {
    final child = Container(
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
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    final clickableChild = onTap != null
        ? InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: child)
        : child;

    return isExpanded ? Expanded(child: clickableChild) : clickableChild;
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
        decoration: decoration,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: contentColor), // Slightly smaller icon
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20, // Slightly smaller text
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

// --- CUSTOM CLIPPER CLASS FOR THE CURVED UI ---
class _BottomCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 50); // Start curve 50px from bottom
    path.quadraticBezierTo(
      size.width / 2, // Control point x
      size.height, // Control point y (the lowest point)
      size.width, // End point x
      size.height - 50, // End point y
    );
    path.lineTo(size.width, 0); // Line back to top-right
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}