import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'theme.dart';
import 'logout_splash_page.dart';
import 'admin_master_credit_ledger_page.dart';
import 'bill_detail_page.dart';
import 'sms_broadcast_helper.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  Stream<DocumentSnapshot> _getDailyStatsStream() {
    final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return FirebaseFirestore.instance
        .collection('dailyStats')
        .doc(todayId)
        .snapshots();
  }

  Stream<double> _getMonthlySalesStream() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    return FirebaseFirestore.instance
        .collection('bills')
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThanOrEqualTo: end)
        .snapshots()
        .map((s) => s.docs.fold(0.0,
            (acc, d) => acc + (d.data()['totalAmount'] as num).toDouble()));
  }

  Stream<double> _getTotalPendingCreditStream() {
    return FirebaseFirestore.instance
        .collection('creditCustomers')
        .snapshots()
        .map((s) => s.docs.fold(
            0.0,
            (acc, d) => acc +
                ((d.data()['totalPending'] ?? 0.0) as num).toDouble()));
  }

  Stream<double> _getMonthlyExpensesStream() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    return FirebaseFirestore.instance
        .collection('expenses')
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThanOrEqualTo: end)
        .snapshots()
        .map((s) => s.docs.fold(0.0,
            (acc, d) => acc + ((d.data()['amount'] ?? 0.0) as num).toDouble()));
  }

  Stream<QuerySnapshot> _getRecentBillsStream() {
    return FirebaseFirestore.instance
        .collection('bills')
        .orderBy('timestamp', descending: true)
        .limit(4)
        .snapshots();
  }

  Stream<List<DocumentSnapshot>> _getWeeklyStatsStream() {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final startDateStr = DateFormat('yyyy-MM-dd').format(sevenDaysAgo);
    return FirebaseFirestore.instance
        .collection('dailyStats')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: startDateStr)
        .snapshots()
        .map((s) {
          final docs = s.docs;
          docs.sort((a, b) => a.id.compareTo(b.id));
          return docs;
        });
  }

  Future<void> _exportExcelReport(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.accentBlue),
      ),
    );

    try {
      final db = FirebaseFirestore.instance;

      // Fetch data
      final billsSnap = await db.collection('bills').orderBy('timestamp', descending: true).get();
      final expensesSnap = await db.collection('expenses').orderBy('timestamp', descending: true).get();
      final creditSnap = await db.collection('creditCustomers').orderBy('totalPending', descending: true).get();
      final repaymentsSnap = await db.collection('repayments').orderBy('timestamp', descending: true).get();
      final reconSnap = await db.collection('cashReconciliations').orderBy('timestamp', descending: true).get();

      // Create workbook
      var excel = Excel.createExcel();
      String defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(defaultSheet, 'Dashboard Summary');
      Sheet dashboardSheet = excel['Dashboard Summary'];

      // Summary Header
      dashboardSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('CANTEEN MANAGEMENT SUMMARY');
      dashboardSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('Report Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');

      // Aggregations
      double totalSales = 0.0;
      double cashSales = 0.0;
      double upiSales = 0.0;
      double creditSales = 0.0;
      for (var doc in billsSnap.docs) {
        final d = doc.data();
        final amt = ((d['totalAmount'] ?? 0.0) as num).toDouble();
        totalSales += amt;
        final mode = d['paymentMode'] ?? '';
        if (mode == 'Cash') {
          cashSales += amt;
        } else if (mode == 'UPI') {
          upiSales += amt;
        } else if (mode == 'Credit') {
          creditSales += amt;
        }
      }

      double totalExpenses = 0.0;
      for (var doc in expensesSnap.docs) {
        final d = doc.data();
        final amt = ((d['amount'] ?? 0.0) as num).toDouble();
        totalExpenses += amt;
      }

      double totalOutstandingCredit = 0.0;
      for (var doc in creditSnap.docs) {
        final d = doc.data();
        final amt = ((d['totalPending'] ?? 0.0) as num).toDouble();
        totalOutstandingCredit += amt;
      }

      double totalRepayments = 0.0;
      for (var doc in repaymentsSnap.docs) {
        final d = doc.data();
        final amt = ((d['amount'] ?? 0.0) as num).toDouble();
        totalRepayments += amt;
      }

      double totalDiscrepancy = 0.0;
      for (var doc in reconSnap.docs) {
        final d = doc.data();
        final amt = ((d['discrepancy'] ?? 0.0) as num).toDouble();
        totalDiscrepancy += amt;
      }

      // Populate summary sheet
      dashboardSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)).value = TextCellValue('Financial Metrics');
      dashboardSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3)).value = TextCellValue('Total Value (INR)');

      List<List<dynamic>> summaryData = [
        ['Overall Revenue (All Sales)', totalSales],
        ['Cash Collected from Sales', cashSales],
        ['UPI Collected from Sales', upiSales],
        ['Outstanding Credits Issued', creditSales],
        ['Total Credits Due', totalOutstandingCredit],
        ['Total Credit Repayments Received', totalRepayments],
        ['Overall Expenses Spent', totalExpenses],
        ['Cumulative Register Cash Discrepancy', totalDiscrepancy],
        ['Net Position (Sales + Repayments - Expenses)', totalSales + totalRepayments - totalExpenses],
      ];

      for (int i = 0; i < summaryData.length; i++) {
        dashboardSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4 + i)).value = TextCellValue(summaryData[i][0] as String);
        dashboardSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 4 + i)).value = DoubleCellValue(summaryData[i][1] as double);
      }

      // Sheet 2: Sales Ledger
      Sheet billsSheet = excel['Sales Bills'];
      billsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Date & Time');
      billsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('Bill Number');
      billsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = TextCellValue('Customer Name');
      billsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0)).value = TextCellValue('Customer Phone');
      billsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0)).value = TextCellValue('Payment Mode');
      billsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 0)).value = TextCellValue('Total Amount (INR)');

      for (int i = 0; i < billsSnap.docs.length; i++) {
        final d = billsSnap.docs[i].data();
        final ts = d['timestamp'] as Timestamp?;
        final dateStr = ts != null ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate()) : 'N/A';
        
        billsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue(dateStr);
        billsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = IntCellValue((d['billNumber'] ?? 0) as int);
        billsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = TextCellValue((d['customerName'] ?? 'Walk-in') as String);
        billsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1)).value = TextCellValue((d['customerPhone'] ?? '-') as String);
        billsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1)).value = TextCellValue((d['paymentMode'] ?? '') as String);
        billsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1)).value = DoubleCellValue(((d['totalAmount'] ?? 0.0) as num).toDouble());
      }

      // Sheet 3: Expenses
      Sheet expSheet = excel['Expenses'];
      expSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Date & Time');
      expSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('Description');
      expSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = TextCellValue('Amount (INR)');

      for (int i = 0; i < expensesSnap.docs.length; i++) {
        final d = expensesSnap.docs[i].data();
        final ts = d['timestamp'] as Timestamp?;
        final dateStr = ts != null ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate()) : 'N/A';

        expSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue(dateStr);
        expSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = TextCellValue((d['description'] ?? '') as String);
        expSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = DoubleCellValue(((d['amount'] ?? 0.0) as num).toDouble());
      }

      // Sheet 4: Credit Balances
      Sheet creditSheet = excel['Credit Accounts'];
      creditSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Customer Name');
      creditSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('Phone Number');
      creditSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = TextCellValue('Total Pending Due (INR)');

      for (int i = 0; i < creditSnap.docs.length; i++) {
        final d = creditSnap.docs[i].data();
        creditSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue((d['name'] ?? 'Unknown') as String);
        creditSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = TextCellValue((d['phone'] ?? '') as String);
        creditSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = DoubleCellValue(((d['totalPending'] ?? 0.0) as num).toDouble());
      }

      // Sheet 5: Repayment Logs
      Sheet repSheet = excel['Repayment Logs'];
      repSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Date & Time');
      repSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('Customer Name');
      repSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = TextCellValue('Customer Phone');
      repSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0)).value = TextCellValue('Cleared Mode');
      repSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0)).value = TextCellValue('Repayment Amount (INR)');
      repSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 0)).value = TextCellValue('Processed By');

      for (int i = 0; i < repaymentsSnap.docs.length; i++) {
        final d = repaymentsSnap.docs[i].data();
        final ts = d['timestamp'] as Timestamp?;
        final dateStr = ts != null ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate()) : 'N/A';

        repSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue(dateStr);
        repSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = TextCellValue((d['customerName'] ?? 'Unknown') as String);
        repSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = TextCellValue((d['customerPhone'] ?? '-') as String);
        repSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1)).value = TextCellValue((d['paymentMode'] ?? '') as String);
        repSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1)).value = DoubleCellValue(((d['amount'] ?? 0.0) as num).toDouble());
        repSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1)).value = TextCellValue((d['processedBy'] ?? '') as String);
      }

      // Sheet 6: Cash Reconciliations
      Sheet reconSheet = excel['Cash Reconciliations'];
      reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Reconciled Date');
      reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('Expected (System) Cash (INR)');
      reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = TextCellValue('Actual (Counted) Cash (INR)');
      reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0)).value = TextCellValue('Discrepancy (INR)');
      reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0)).value = TextCellValue('Audited By');
      reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 0)).value = TextCellValue('Audit Notes');
      reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 0)).value = TextCellValue('Timestamp');

      for (int i = 0; i < reconSnap.docs.length; i++) {
        final d = reconSnap.docs[i].data();
        final ts = d['timestamp'] as Timestamp?;
        final dateStr = ts != null ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate()) : 'N/A';

        reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue((d['date'] ?? '') as String);
        reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = DoubleCellValue(((d['systemCash'] ?? 0.0) as num).toDouble());
        reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = DoubleCellValue(((d['actualCash'] ?? 0.0) as num).toDouble());
        reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1)).value = DoubleCellValue(((d['discrepancy'] ?? 0.0) as num).toDouble());
        reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1)).value = TextCellValue((d['submittedBy'] ?? '') as String);
        reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1)).value = TextCellValue((d['note'] ?? '') as String);
        reconSheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: i + 1)).value = TextCellValue(dateStr);
      }

      // Sheet 7: Top Selling Items
      Sheet topSheet = excel['Top Selling Items'];
      topSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Menu Item Name');
      topSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('Portions Sold (Total)');

      Map<String, int> topItemsMap = {};
      for (var doc in billsSnap.docs) {
        final d = doc.data();
        final items = List<Map<String, dynamic>>.from(d['items'] ?? []);
        for (var item in items) {
          final name = item['name'] ?? 'Unknown';
          final qty = (item['quantity'] ?? 0) as int;
          topItemsMap[name] = (topItemsMap[name] ?? 0) + qty;
        }
      }

      final sortedTopItems = topItemsMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (int i = 0; i < sortedTopItems.length; i++) {
        final entry = sortedTopItems[i];
        topSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue(entry.key);
        topSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = IntCellValue(entry.value);
      }

      final bytes = excel.encode();
      if (bytes != null) {
        final tempDir = await getTemporaryDirectory();
        final file = await File('${tempDir.path}/Canteen_Ledger_Report.xlsx').create();
        await file.writeAsBytes(bytes);

        if (context.mounted) {
          Navigator.pop(context); // Pop loading indicator
          final xFile = XFile(file.path);
          await Share.shareXFiles([xFile], text: 'Canteen Full Ledger & Analytics');
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export Excel: $e', style: GoogleFonts.poppins()),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    }
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.bgCard,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppGradients.brand),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.admin_panel_settings,
                          size: 36, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Text('Admin Command Center',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text(_currentUser?.email ?? '',
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _drawerTile(Icons.restaurant_menu_rounded, 'Manage Menu Items',
              AppColors.accentBlue, () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/add_item');
          }),
          _drawerTile(Icons.campaign_rounded, 'Broadcast Notice',
              AppColors.accentPurple, () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/send_notification');
          }),
          _drawerTile(Icons.history_edu_rounded, 'Master Credit Ledger',
              AppColors.accentOrange, () {
            Navigator.pop(context);
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AdminMasterCreditLedgerPage()));
          }),
          _drawerTile(Icons.bar_chart_rounded, 'Analytics & Graphs',
              AppColors.accentBlue, () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/admin_analytics');
          }),
          _drawerTile(Icons.receipt_long_outlined, 'Monthly Budget & Expenses',
              AppColors.accentRed, () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/admin_expense_report');
          }),
          _drawerTile(Icons.account_balance_rounded, 'Cash Reconciliation Logs',
              const Color(0xFFCE93D8), () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/cash_reconciliation_admin');
          }),
          _drawerTile(Icons.receipt_long_outlined, 'View All Bills History',
              AppColors.accentBlue, () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/all_bills_page');
          }),
          _drawerTile(Icons.campaign_rounded, 'SMS Broadcast Specials',
              AppColors.accentOrange, () {
            Navigator.pop(context);
            showSMSBroadcastDialog(context);
          }),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(color: AppColors.bgDivider),
          ),
          _drawerTile(Icons.logout_rounded, 'Logout', AppColors.accentRed, () {
            Navigator.pop(context);
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const LogoutSplashPage()));
          }),
        ],
      ),
    );
  }

  Widget _drawerTile(
      IconData icon, String title, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title,
          style: GoogleFonts.poppins(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      trailing:
          const Icon(Icons.chevron_right, color: AppColors.textHint, size: 18),
      onTap: onTap,
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: glassCard(
          radius: 18,
          borderColor: AppColors.glassBorder.withValues(alpha: 0.05),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    size: 14, color: AppColors.textSecondary),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyChartSection() {
    return StreamBuilder<List<DocumentSnapshot>>(
      stream: _getWeeklyStatsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 220,
            child: Center(
                child: CircularProgressIndicator(color: AppColors.accentBlue)),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Container(
            height: 180,
            alignment: Alignment.center,
            decoration: glassCard(radius: 18),
            child: Text(
              'No trends data available yet',
              style: GoogleFonts.poppins(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          );
        }

        final docs = snapshot.data!;

        List<FlSpot> salesSpots = [];
        List<FlSpot> creditSpots = [];

        double maxVal = 1000.0;

        for (int i = 0; i < docs.length; i++) {
          final data = docs[i].data() as Map<String, dynamic>;
          final sales = (data['totalSales'] ?? 0.0).toDouble();
          final credit = (data['totalCredit'] ?? 0.0).toDouble();

          salesSpots.add(FlSpot(i.toDouble(), sales));
          creditSpots.add(FlSpot(i.toDouble(), credit));

          if (sales > maxVal) maxVal = sales;
          if (credit > maxVal) maxVal = credit;
        }

        maxVal = maxVal * 1.15; // padding top

        return Container(
          padding: const EdgeInsets.fromLTRB(12, 16, 18, 12),
          decoration: glassCard(radius: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8.0, bottom: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weekly Revenue vs Credit',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Comparison of sales & outstanding credit',
                          style: GoogleFonts.poppins(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _chartLegendItem('Sales', AppColors.accentBlue),
                        const SizedBox(width: 12),
                        _chartLegendItem('Credit', AppColors.accentOrange),
                      ],
                    )
                  ],
                ),
              ),
              SizedBox(
                height: 180,
                child: LineChart(
                  LineChartData(
                    lineTouchData: LineTouchData(
                      handleBuiltInTouches: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (touchedSpot) => AppColors.bgCard,
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            final isSales = spot.barIndex == 0;
                            return LineTooltipItem(
                              '${isSales ? "Sales" : "Credit"}: ₹${spot.y.toStringAsFixed(0)}',
                              GoogleFonts.poppins(
                                color: isSales
                                    ? AppColors.accentBlue
                                    : AppColors.accentOrange,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: AppColors.bgDivider.withValues(alpha: 0.5),
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: 1,
                          getTitlesWidget: (double value, TitleMeta meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= docs.length) {
                              return const SizedBox();
                            }
                            final dateStr = docs[index].id;
                            final date = DateTime.parse(dateStr);
                            return SideTitleWidget(
                              meta: meta,
                              space: 4,
                              child: Text(
                                DateFormat('dd MMM').format(date),
                                style: GoogleFonts.poppins(
                                  color: AppColors.textSecondary,
                                  fontSize: 9,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (double value, TitleMeta meta) {
                            if (value == 0) return const SizedBox();
                            return SideTitleWidget(
                              meta: meta,
                              space: 4,
                              child: Text(
                                value >= 1000
                                    ? '${(value / 1000).toStringAsFixed(1)}k'
                                    : value.toStringAsFixed(0),
                                style: GoogleFonts.poppins(
                                  color: AppColors.textHint,
                                  fontSize: 9,
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
                    minX: 0,
                    maxX: (docs.length - 1).toDouble(),
                    minY: 0,
                    maxY: maxVal,
                    lineBarsData: [
                      LineChartBarData(
                        spots: salesSpots,
                        isCurved: true,
                        gradient: const LinearGradient(
                            colors: [Color(0xFF2196F3), Color(0xFF4FC3F7)]),
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF2196F3).withValues(alpha: 0.2),
                              Color(0xFF2196F3).withValues(alpha: 0.0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      LineChartBarData(
                        spots: creditSpots,
                        isCurved: true,
                        gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B35), Color(0xFFFF8C42)]),
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFFFF6B35).withValues(alpha: 0.15),
                              Color(0xFFFF6B35).withValues(alpha: 0.0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chartLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      drawer: _buildDrawer(),
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverAppBar(
              expandedHeight: 140,
              pinned: true,
              backgroundColor: AppColors.bgDark,
              iconTheme: const IconThemeData(color: Colors.white),
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.file_download_outlined, color: Colors.white, size: 24),
                  tooltip: 'Export Excel Report',
                  onPressed: () => _exportExcelReport(context),
                ),
                const SizedBox(width: 8),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.bgDark, Color(0xFF0F1524)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'Console Panel',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AppColors.accentGreen,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Operational Mode',
                                    style: GoogleFonts.poppins(
                                      color: AppColors.accentGreen,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.bgCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: Text(
                              DateFormat('dd MMM yyyy').format(DateTime.now()),
                              style: GoogleFonts.poppins(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ];
        },
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBudgetAlertBanner(),
                // Live Analytics Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    sectionTitle('System Performance'),
                    const Icon(Icons.insights,
                        size: 16, color: AppColors.accentBlue),
                  ],
                ),
                const SizedBox(height: 12),

                // Metrics Grid (2x2)
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.45,
                  children: [
                    // Today's Sales
                    StreamBuilder<DocumentSnapshot>(
                      stream: _getDailyStatsStream(),
                      builder: (context, snap) {
                        String sales = '₹0';
                        if (snap.hasData && snap.data!.exists) {
                          final d = snap.data!.data() as Map<String, dynamic>;
                          sales =
                              '₹${(d['totalSales'] ?? 0).toStringAsFixed(0)}';
                        }
                        return _buildMetricCard(
                          icon: Icons.today_rounded,
                          label: "Today's Sales",
                          value: sales,
                          gradient: AppGradients.greenAccent,
                          onTap: () => Navigator.pushNamed(
                              context, '/daily_sales_report'),
                        );
                      },
                    ),

                    // Monthly Sales
                    StreamBuilder<double>(
                      stream: _getMonthlySalesStream(),
                      builder: (context, snap) {
                        return _buildMetricCard(
                          icon: Icons.calendar_month_rounded,
                          label: "Month's Revenue",
                          value: "₹${snap.data?.toStringAsFixed(0) ?? '0'}",
                          gradient: AppGradients.blueAccent,
                          onTap: () => Navigator.pushNamed(
                              context, '/monthly_sales_breakdown'),
                        );
                      },
                    ),

                    // Total Pending Credit
                    StreamBuilder<double>(
                      stream: _getTotalPendingCreditStream(),
                      builder: (context, snap) {
                        return _buildMetricCard(
                          icon: Icons.account_balance_wallet_rounded,
                          label: "Total Credit Due",
                          value: "₹${snap.data?.toStringAsFixed(0) ?? '0'}",
                          gradient: AppGradients.orangeAccent,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const AdminMasterCreditLedgerPage())),
                        );
                      },
                    ),

                    // Monthly Expenses
                    StreamBuilder<double>(
                      stream: _getMonthlyExpensesStream(),
                      builder: (context, snap) {
                        return _buildMetricCard(
                          icon: Icons.receipt_long_rounded,
                          label: "Month's Expenses",
                          value: "₹${snap.data?.toStringAsFixed(0) ?? '0'}",
                          gradient: AppGradients.redAccent,
                          onTap: () => Navigator.pushNamed(
                              context, '/admin_expense_report'),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Weekly Revenue & Credit Graphical Comparison
                _buildWeeklyChartSection(),
                const SizedBox(height: 24),

                // Recent sales section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    sectionTitle('Live Canteen Feed'),
                    GestureDetector(
                      onTap: () =>
                          Navigator.pushNamed(context, '/all_bills_page'),
                      child: Text(
                        'See All Feed',
                        style: GoogleFonts.poppins(
                          color: AppColors.accentBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                StreamBuilder<QuerySnapshot>(
                  stream: _getRecentBillsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(
                              color: AppColors.accentBlue),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: glassCard(radius: 16),
                        alignment: Alignment.center,
                        child: Text(
                          'No recent bills recorded.',
                          style: GoogleFonts.poppins(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      );
                    }

                    final bills = snapshot.data!.docs;

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: bills.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final doc = bills[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final billNum = data['billNumber'] ?? '-';
                        final customerName = data['customerName'] ?? 'Walk-in';
                        final total =
                            (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
                        final mode = data['paymentMode'] ?? 'N/A';
                        final ts = data['timestamp'] as Timestamp?;
                        final timeStr = ts != null
                            ? DateFormat.jm().format(ts.toDate())
                            : '-';

                        final isCredit = mode == 'Credit';

                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BillDetailPage(billId: doc.id),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: glassCard(radius: 16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.bgInput,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '#$billNum',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customerName,
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        timeStr,
                                        style: GoogleFonts.poppins(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₹${total.toStringAsFixed(0)}',
                                      style: GoogleFonts.poppins(
                                        color: isCredit
                                            ? AppColors.accentOrange
                                            : AppColors.accentGreen,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    buildBadge(
                                      mode,
                                      isCredit
                                          ? AppColors.accentOrange
                                          : mode == 'Cash'
                                              ? AppColors.accentGreen
                                              : AppColors.accentBlue,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBudgetAlertBanner() {
    final now = DateTime.now();
    final monthId = DateFormat('yyyy-MM').format(now);
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('monthlyFunds').doc(monthId).snapshots(),
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
          stream: FirebaseFirestore.instance.collection('expenses')
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

            debugPrint("Budget Alert values: allocated=$allocated, spent=$spent, available=$available, pctRemaining=$pctRemaining");

            if (pctRemaining >= 0.15) return const SizedBox.shrink();

            final pctStr = (pctRemaining * 100).toStringAsFixed(0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F0F11),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.accentRed.withValues(alpha: 0.55)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.accentRed, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            available < 0 ? 'Budget Overspent!' : 'Low Budget Alert ($pctStr% Left)',
                            style: GoogleFonts.poppins(color: AppColors.accentRed, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            available < 0 
                                ? 'You have exceeded the allocated budget by ₹${available.abs().toStringAsFixed(0)}.'
                                : 'Available: ₹${available.toStringAsFixed(0)} left of ₹${allocated.toStringAsFixed(0)} allocated.',
                            style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 10),
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
