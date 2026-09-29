import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'theme.dart';
import 'logout_splash_page.dart';
import 'notifications_page.dart';
import 'sms_broadcast_helper.dart';
import 'canteen_provider.dart';

class BillingDashboardPage extends StatefulWidget {
  const BillingDashboardPage({super.key});
  @override
  State<BillingDashboardPage> createState() => _BillingDashboardPageState();
}

class _BillingDashboardPageState extends State<BillingDashboardPage> {
  final User? _user = FirebaseAuth.instance.currentUser;
  StreamSubscription<QuerySnapshot>? _noticeSub;
  String? _showingNoticeId;

  @override
  void initState() {
    super.initState();
    _listenNotices();
  }

  @override
  void dispose() {
    _noticeSub?.cancel();
    super.dispose();
  }

  void _listenNotices() {
    _noticeSub = FirebaseFirestore.instance
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (!mounted || snap.docs.isEmpty) return;
      final doc = snap.docs.first;
      final data = doc.data();
      final readBy = List<String>.from(data['readBy'] ?? []);
      final uid = _user?.uid ?? '';
      if (!readBy.contains(uid) && _showingNoticeId != doc.id) {
        _showingNoticeId = doc.id;
        _showNoticeAlert(data);
      }
    });
  }

  void _showNoticeAlert(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: AppColors.accentOrange.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                  color: AppColors.accentOrange.withValues(alpha: 0.15),
                  blurRadius: 32,
                  spreadRadius: 2)
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.campaign_rounded,
                  color: AppColors.accentOrange, size: 32),
            ),
            const SizedBox(height: 14),
            Text('New Admin Notice',
                style: GoogleFonts.poppins(
                    color: AppColors.accentOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 6),
            Text(data['title'] ?? 'Notice',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Check the 🔔 bell icon to read the full notice.',
                style: GoogleFonts.poppins(
                    color: Colors.white54, fontSize: 12, height: 1.5),
                textAlign: TextAlign.center),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentOrange,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showingNoticeId = null;
                },
                child: Text('OK, Got it',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Stream<Map<String, String>> get _statsStream {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return FirebaseFirestore.instance
        .collection('dailyStats')
        .doc(today)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return {'sales': '₹0', 'bills': '0'};
      final d = snap.data() as Map<String, dynamic>;
      return {
        'sales': '₹${(d['totalSales'] as num?)?.toStringAsFixed(0) ?? '0'}',
        'bills': '${d['totalBills'] ?? '0'}',
      };
    });
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF080C17),
        drawer: _drawer(),
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _appBar(),
            SliverToBoxAdapter(child: _body()),
          ],
        ),
      ),
    );
  }

  // ── App Bar ──────────────────────────────────────────────
  Widget _appBar() {
    return SliverAppBar(
      expandedHeight: 230,
      pinned: true,
      stretch: true,
      elevation: 0,
      backgroundColor: AppColors.gradBlue,
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [_bellButton(), const SizedBox(width: 4)],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        collapseMode: CollapseMode.pin,
        background: _hero(),
      ),
    );
  }

  Widget _bellButton() {
    return StreamBuilder<int>(
      stream: NotificationsPage.unreadCountStream,
      builder: (_, snap) {
        final n = snap.data ?? 0;
        return GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/notifications'),
          child: Padding(
            padding: const EdgeInsets.only(right: 16, top: 4),
            child: Stack(alignment: Alignment.center, children: [
              Icon(
                n > 0
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: Colors.white,
                size: 26,
              ),
              if (n > 0)
                Positioned(
                  right: 0,
                  top: 10,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.accentRed,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.gradBlue, width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        n > 9 ? '9+' : '$n',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }

  Widget _hero() {
    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.brand),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 46, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting row
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_greeting 👋',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Cashier Dashboard',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -0.5)),
              const SizedBox(height: 4),
              Text(
                'Canteen: ${CanteenProvider.selectedCanteenName}',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                style: GoogleFonts.poppins(color: Colors.white60, fontSize: 11),
              ),
              const SizedBox(height: 12),
              // Stat pills
              StreamBuilder<Map<String, String>>(
                stream: _statsStream,
                builder: (_, snap) {
                  final s = snap.data ?? {'sales': '₹0', 'bills': '0'};
                  return Row(children: [
                    _heroPill(
                      icon: Icons.currency_rupee_rounded,
                      value: s['sales']!,
                      label: "Today's Revenue",
                      onTap: () =>
                          Navigator.pushNamed(context, '/daily_sales_report'),
                    ),
                    const SizedBox(width: 10),
                    _heroPill(
                      icon: Icons.receipt_rounded,
                      value: s['bills']!,
                      label: 'Bills Issued',
                      onTap: () =>
                          Navigator.pushNamed(context, '/all_bills_page'),
                    ),
                  ]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroPill({
    required IconData icon,
    required String value,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 15),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis),
                  Text(label,
                      style: GoogleFonts.poppins(
                          color: Colors.white54, fontSize: 9)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────
  Widget _body() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBudgetAlertBanner(),
          // ① Notice banner (only when unread)
          StreamBuilder<int>(
            stream: NotificationsPage.unreadCountStream,
            builder: (_, snap) {
              final n = snap.data ?? 0;
              if (n == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/notifications'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1100),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color:
                              AppColors.accentOrange.withValues(alpha: 0.55)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.campaign_rounded,
                          color: AppColors.accentOrange, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$n unread admin notice${n > 1 ? 's' : ''} — tap to view',
                          style: GoogleFonts.poppins(
                              color: AppColors.accentOrange,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: AppColors.accentOrange, size: 16),
                    ]),
                  ),
                ),
              );
            },
          ),

          // ② Create New Bill — hero CTA
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/print_bill'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2196F3).withValues(alpha: 0.4),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.add_shopping_cart_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Create New Bill',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3)),
                      Text('Start a new billing session',
                          style: GoogleFonts.poppins(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 16),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 28),

          // ③ Menu section
          _label('MENU'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _tile(
                icon: Icons.menu_book_rounded,
                title: 'View Menu',
                sub: 'Browse all items',
                color: const Color(0xFF9C27B0),
                route: '/view_menu',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _tile(
                icon: Icons.restaurant_menu_rounded,
                title: 'Manage Menu',
                sub: 'Add · Edit · Delete',
                color: const Color(0xFF00C980),
                route: '/add_item',
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // ④ Operations section
          _label('OPERATIONS'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _tile(
                icon: Icons.receipt_long_outlined,
                title: 'All Bills',
                sub: 'Full history',
                color: const Color(0xFF4FC3F7),
                route: '/all_bills_page',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _tile(
                icon: Icons.money_off_rounded,
                title: 'Log Expense',
                sub: 'Record a cost',
                color: const Color(0xFFFF8C42),
                route: '/expenses',
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _tile(
                icon: Icons.credit_score_rounded,
                title: 'Credit Customers',
                sub: 'Manage pending credits',
                color: AppColors.accentOrange,
                route: '/credit_customers',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _tile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Monthly Report',
                sub: 'View fund status',
                color: AppColors.accentGreen,
                route: '/funds_received',
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        color: AppColors.textHint,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String sub,
    required Color color,
    required String route,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, route),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(sub,
                style: GoogleFonts.poppins(
                    color: AppColors.textHint, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── Drawer ────────────────────────────────────────────────
  Widget _drawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0D1120),
      child: Column(children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: AppGradients.brand),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.point_of_sale_rounded,
                          size: 28, color: Colors.white),
                    ),
                    const SizedBox(height: 14),
                    Text('Cashier Panel',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(_user?.email ?? '',
                        style: GoogleFonts.poppins(
                            color: Colors.white60, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ]),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 12),
            children: [
              _dItem(Icons.account_balance_wallet_outlined, 'Monthly Report',
                  AppColors.accentGreen, () => _nav('/funds_received')),
              _dItem(Icons.money_off_rounded, 'Log Expense',
                  AppColors.accentOrange, () => _nav('/expenses')),
              _dItem(
                  Icons.account_balance_rounded,
                  'Cash Reconciliation',
                  const Color(0xFFCE93D8),
                  () => _nav('/cash_reconciliation_cashier')),
              _dItem(Icons.receipt_long_outlined, 'All Bills History',
                  AppColors.accentBlue, () => _nav('/all_bills_page')),
              _dItem(Icons.notifications_outlined, 'Admin Notices',
                  const Color(0xFFFFD54F), () => _nav('/notifications')),
              _dItem(Icons.campaign_rounded, 'SMS Broadcast Specials',
                  AppColors.accentOrange, () {
                Navigator.pop(context);
                showSMSBroadcastDialog(context);
              }),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Divider(color: AppColors.bgDivider, height: 1),
              ),
              _dItem(Icons.logout_rounded, 'Logout', AppColors.accentRed, () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LogoutSplashPage()));
              }),
            ],
          ),
        ),
      ]),
    );
  }

  void _nav(String route) {
    Navigator.pop(context);
    Navigator.pushNamed(context, route);
  }

  Widget _dItem(IconData icon, String title, Color color, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(title,
          style: GoogleFonts.poppins(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500)),
      trailing:
          const Icon(Icons.chevron_right, color: AppColors.textHint, size: 16),
      onTap: onTap,
    );
  }

  Widget _buildBudgetAlertBanner() {
    final now = DateTime.now();
    final monthId = DateFormat('yyyy-MM').format(now);
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('monthlyFunds')
          .doc(monthId)
          .snapshots(),
      builder: (context, fundSnap) {
        if (fundSnap.hasError) {
          debugPrint("Budget Alert Fund Error: ${fundSnap.error}");
          return const SizedBox.shrink();
        }
        if (!fundSnap.hasData || !fundSnap.data!.exists) {
          return const SizedBox.shrink();
        }

        final data = fundSnap.data!.data() as Map<String, dynamic>?;
        if (data == null) return const SizedBox.shrink();
        final allocated = (data['fundAmount'] as num?)?.toDouble() ?? 0.0;
        if (allocated == 0) return const SizedBox.shrink();

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('expenses')
              .where('timestamp', isGreaterThanOrEqualTo: start)
              .where('timestamp', isLessThanOrEqualTo: end)
              .snapshots(),
          builder: (context, expSnap) {
            if (expSnap.hasError) {
              debugPrint("Budget Alert Expenses Error: ${expSnap.error}");
              return const SizedBox.shrink();
            }
            if (!expSnap.hasData) return const SizedBox.shrink();

            double spent = 0;
            for (var doc in expSnap.data!.docs) {
              final d = doc.data() as Map<String, dynamic>?;
              if (d != null) {
                spent += ((d['amount'] ?? 0.0) as num).toDouble();
              }
            }

            double available = allocated - spent;
            double pctRemaining = available / allocated;

            debugPrint(
                "Budget Alert values: allocated=$allocated, spent=$spent, available=$available, pctRemaining=$pctRemaining");

            if (pctRemaining >= 0.15) return const SizedBox.shrink();

            final pctStr = (pctRemaining * 100).toStringAsFixed(0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F0F11),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.accentRed.withValues(alpha: 0.55)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.accentRed, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            available < 0
                                ? 'Budget Overspent!'
                                : 'Low Budget Alert ($pctStr% Left)',
                            style: GoogleFonts.poppins(
                                color: AppColors.accentRed,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            available < 0
                                ? 'You have exceeded the allocated budget by ₹${available.abs().toStringAsFixed(0)}.'
                                : 'Available: ₹${available.toStringAsFixed(0)} left of ₹${allocated.toStringAsFixed(0)} allocated.',
                            style: GoogleFonts.poppins(
                                color: AppColors.textSecondary, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
