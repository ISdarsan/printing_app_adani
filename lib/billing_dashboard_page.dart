import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // For user email
import 'package:cloud_firestore/cloud_firestore.dart'; // For live stats
import 'package:intl/intl.dart'; // For today's date
import 'logout_splash_page.dart';

class BillingDashboardPage extends StatefulWidget {
  const BillingDashboardPage({super.key});

  @override
  State<BillingDashboardPage> createState() => _BillingDashboardPageState();
}

class _BillingDashboardPageState extends State<BillingDashboardPage> {
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

  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // Stream for live stats
  Stream<DocumentSnapshot> _getDailyStatsStream() {
    String todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
    // This stream listens to a specific document for today's sales.
    // We will need to create the logic in 'print_bill_page' to update this doc.
    return FirebaseFirestore.instance
        .collection('dailyStats')
        .doc(todayId)
        .snapshots();
  }

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
          elevation: 0, // Removed shadow to blend with curved header
        ),
      ),
      // DRAWER: All non-essential items are here
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // --- NEW PROFESSIONAL DRAWER HEADER ---
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(gradient: adaniGradient),
              accountName: const Text(
                'Canteen Cashier',
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
                child: Icon(Icons.person, size: 40, color: Color(0xFF0066B3)),
              ),
            ),
            // ------------------------------------
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
              leading:
              const Icon(Icons.account_balance_wallet, color: Colors.green),
              title: const Text('Monthly Report'), // Renamed
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/funds_received');
              },
            ),
            ListTile(
              leading: const Icon(Icons.money_off, color: Colors.red),
              title: const Text('Expenses Tracking'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/expenses');
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_box_outlined, color: Colors.blue),
              title: const Text('Add/Edit Item'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/add_item');
              },
            ),

            // --- NOTIFICATION BUTTON ADDED ---
            ListTile(
              leading: const Icon(Icons.notifications, color: Colors.orange),
              title: const Text('Notifications'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/notifications');
              },
            ),
            // ---------------------------------

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
      // BODY: With new curved UI and GridView
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
                    'Welcome, Cashier!',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Here is your daily summary.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- LIVE STATS CARDS ---
                  StreamBuilder<DocumentSnapshot>(
                    stream: _getDailyStatsStream(),
                    builder: (context, snapshot) {
                      String sales = "₹ 0.00";
                      String bills = "0";

                      if (snapshot.hasData && snapshot.data!.exists) {
                        final data =
                        snapshot.data!.data() as Map<String, dynamic>;
                        sales =
                        "₹ ${data['totalSales']?.toStringAsFixed(2) ?? '0.00'}";
                        bills = data['totalBills']?.toString() ?? '0';
                      }

                      return Row(
                        children: [
                          _buildStatCard(
                            icon: Icons.currency_rupee,
                            label: "Today's Sales",
                            value: sales,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 16),
                          _buildStatCard(
                            icon: Icons.receipt,
                            label: "Total Bills",
                            value: bills,
                            color: Colors.orange,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // --- ACTION GRID ---
                  const Text(
                    'Main Actions',
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
                    shrinkWrap: true, // Important for SingleChildScrollView
                    physics:
                    const NeverScrollableScrollPhysics(), // Let the parent scroll
                    children: [
                      _buildBigTile(
                        context,
                        icon: Icons.receipt_long_outlined,
                        title: 'New Bill',
                        gradient: adaniGradient,
                        onTap: () {
                          Navigator.pushNamed(context, '/print_bill');
                        },
                      ),
                      _buildBigTile(
                        context,
                        icon: Icons.menu_book_outlined,
                        title: 'View Menu',
                        isWhite: true,
                        onTap: () {
                          Navigator.pushNamed(context, '/view_menu');
                        },
                      ),
                      // You can easily add more tiles here in the future
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

  // Helper for Big Action Tiles (modified for GridView)
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