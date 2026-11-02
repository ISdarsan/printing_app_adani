import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'canteen_provider.dart';
import 'business_time.dart';
import 'financial_metrics.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  String _selectedCanteenFilter = 'all'; // 'all' or canteenId e.g. 'canteen_1'

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Warm the logo so the logout splash shows it instantly.
    precacheBrandLogo(context);
  }

  Stream<Map<String, dynamic>> _getDailyStatsStream() {
    final day = BusinessTime.dayRange(DateTime.now());

    return FirebaseFirestore.instance
        .collection('bills')
        .where('timestamp', isGreaterThanOrEqualTo: day.start)
        .where('timestamp', isLessThan: day.end)
        .snapshots()
        .map((s) {
      double sales = 0.0;
      double credit = 0.0;
      double cash = 0.0;
      double upi = 0.0;
      int count = 0;
      for (var d in s.docs) {
        final data = d.data();
        final cId = (data['canteenId'] ?? 'main').toString();
        if (_selectedCanteenFilter != 'all' &&
            cId != _selectedCanteenFilter &&
            !(_selectedCanteenFilter == 'main' && cId.isEmpty)) {
          continue;
        }

        final amount = ((data['totalAmount'] ?? 0.0) as num).toDouble();
        sales += amount;
        count++;
        switch (data['paymentMode']) {
          case 'Cash':
            cash += amount;
          case 'UPI':
            upi += amount;
          case 'Credit':
            credit += amount;
        }
      }
      return {
        'totalSales': sales,
        'totalCredit': credit,
        'totalCash': cash,
        'totalUpi': upi,
        'billCount': count,
      };
    });
  }

  Stream<double> _getMonthlySalesStream() {
    final month = BusinessTime.monthRange(DateTime.now());
    return FirebaseFirestore.instance
        .collection('bills')
        .where('timestamp', isGreaterThanOrEqualTo: month.start)
        .where('timestamp', isLessThan: month.end)
        .snapshots()
        .map((s) => s.docs.fold(0.0, (acc, d) {
              final data = d.data();
              if (_selectedCanteenFilter != 'all') {
                final cId = (data['canteenId'] ?? 'main').toString();
                if (cId != _selectedCanteenFilter &&
                    !(_selectedCanteenFilter == 'main' && cId.isEmpty)) {
                  return acc;
                }
              }
              return acc + ((data['totalAmount'] ?? 0.0) as num).toDouble();
            }));
  }

  Stream<double> _getTotalPendingCreditStream() {
    return FirebaseFirestore.instance
        .collection('creditCustomers')
        .snapshots()
        .map((s) => s.docs.fold(0.0, (acc, d) {
              final data = d.data();
              if (_selectedCanteenFilter != 'all') {
                final cId = (data['canteenId'] ?? 'main').toString();
                if (cId != _selectedCanteenFilter &&
                    !(_selectedCanteenFilter == 'main' && cId.isEmpty)) {
                  return acc;
                }
              }
              return acc + ((data['totalPending'] ?? 0.0) as num).toDouble();
            }));
  }

  Stream<double> _getMonthlyExpensesStream() {
    final month = BusinessTime.monthRange(DateTime.now());
    return FirebaseFirestore.instance
        .collection('expenses')
        .where('timestamp', isGreaterThanOrEqualTo: month.start)
        .where('timestamp', isLessThan: month.end)
        .snapshots()
        .map((s) => s.docs.fold(0.0, (acc, d) {
              final data = d.data();
              if (_selectedCanteenFilter != 'all') {
                final cId = (data['canteenId'] ?? 'main').toString();
                if (cId != _selectedCanteenFilter &&
                    !(_selectedCanteenFilter == 'main' && cId.isEmpty)) {
                  return acc;
                }
              }
              return acc + ((data['amount'] ?? 0.0) as num).toDouble();
            }));
  }

  Stream<List<DocumentSnapshot>> _getRecentBillsStream() {
    return FirebaseFirestore.instance
        .collection('bills')
        .orderBy('timestamp', descending: true)
        // Only the latest few bills are shown; never stream the whole
        // collection. A wider window is used when filtering by branch because
        // the filter is applied client-side (avoids a new composite index).
        .limit(_selectedCanteenFilter == 'all' ? 4 : 100)
        .snapshots()
        .map((s) {
      if (_selectedCanteenFilter == 'all') {
        return s.docs.take(4).toList();
      }
      return s.docs
          .where((d) {
            final cId = (d.data()['canteenId'] ?? 'main').toString();
            return cId == _selectedCanteenFilter ||
                (_selectedCanteenFilter == 'main' && cId.isEmpty);
          })
          .take(4)
          .toList();
    });
  }

  Stream<List<MapEntry<String, Map<String, dynamic>>>> _getWeeklyStatsStream() {
    final startDateStr = BusinessTime.dateKeyDaysAgo(DateTime.now(), 7);
    return FirebaseFirestore.instance
        .collection('dailyStats')
        // Filter on the 'date' field (set on every dailyStats doc). Doc IDs are
        // "<canteenId>_<date>", so a documentId range matched all history.
        .where('date', isGreaterThanOrEqualTo: startDateStr)
        .snapshots()
        .map((s) {
      final totalsByDate = <String, Map<String, dynamic>>{};
      for (final doc in s.docs) {
        final data = doc.data();
        final date = (data['date'] ??
                CanteenProvider.dateFromDailyStatsDocumentId(doc.id))
            .toString();
        if (date.compareTo(startDateStr) < 0) continue;

        final totals = totalsByDate.putIfAbsent(
            date,
            () => {
                  'totalSales': 0.0,
                  'totalCredit': 0.0,
                });
        totals['totalSales'] = (totals['totalSales'] as double) +
            ((data['totalSales'] ?? 0.0) as num).toDouble();
        totals['totalCredit'] = (totals['totalCredit'] as double) +
            ((data['totalCredit'] ?? 0.0) as num).toDouble();
      }
      final dates = totalsByDate.keys.toList()..sort();
      return dates.map((date) => MapEntry(date, totalsByDate[date]!)).toList();
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

      // Fetch all data
      final billsSnap = await db
          .collection('bills')
          .orderBy('timestamp', descending: true)
          .get();
      final expensesSnap = await db
          .collection('expenses')
          .orderBy('timestamp', descending: true)
          .get();
      final creditSnap = await db
          .collection('creditCustomers')
          .orderBy('totalPending', descending: true)
          .get();
      final repaymentsSnap = await db
          .collection('repayments')
          .orderBy('timestamp', descending: true)
          .get();
      final reconSnap = await db
          .collection('cashReconciliations')
          .orderBy('timestamp', descending: true)
          .get();
      final canteensSnap = await db.collection('canteens').get();

      // Build canteen name map: id -> name
      final Map<String, String> canteenNames = {'main': 'Main Canteen'};
      for (final doc in canteensSnap.docs) {
        final d = doc.data();
        canteenNames[doc.id] = d['name'] ?? doc.id;
      }

      String resolveCanteenName(String? cId) {
        if (cId == null || cId.isEmpty || cId == 'main') return 'Main Canteen';
        return canteenNames[cId] ?? cId;
      }

      // Collect unique canteen IDs present in bills/expenses
      final Set<String> branchIds = {'main'};
      for (final doc in billsSnap.docs) {
        final cId = (doc.data()['canteenId'] ?? 'main').toString();
        branchIds.add(cId.isEmpty ? 'main' : cId);
      }
      for (final doc in expensesSnap.docs) {
        final cId = (doc.data()['canteenId'] ?? 'main').toString();
        branchIds.add(cId.isEmpty ? 'main' : cId);
      }

      var excel = Excel.createExcel();
      String defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(defaultSheet, 'Dashboard Summary');
      Sheet dashboardSheet = excel['Dashboard Summary'];

      void writeHeader(Sheet s, List<String> cols) {
        for (int c = 0; c < cols.length; c++) {
          s
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
              .value = TextCellValue(cols[c]);
        }
      }

      // SHEET 1: Dashboard Summary
      dashboardSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .value = TextCellValue('CANTEEN MANAGEMENT SUMMARY - ALL BRANCHES');
      dashboardSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
              .value =
          TextCellValue(
              'Report Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(BusinessTime.wallClock(DateTime.now()))} IST');

      // Source records -> pure FinancialSummary (see financial_metrics.dart).
      // Sales and repayments are kept separate: repayments are never revenue.
      String branchOf(Map<String, dynamic> d) {
        final c = (d['canteenId'] ?? 'main').toString();
        return c.isEmpty ? 'main' : c;
      }

      SaleRecord saleOf(Map<String, dynamic> d) => SaleRecord(
          ((d['totalAmount'] ?? 0.0) as num).toDouble(),
          (d['paymentMode'] ?? '').toString());
      RepaymentRecord repaymentOf(Map<String, dynamic> d) => RepaymentRecord(
          ((d['amount'] ?? 0.0) as num).toDouble(),
          (d['paymentMode'] ?? '').toString());

      final allSummary = FinancialSummary.fromRecords(
        billsSnap.docs.map((d) => saleOf(d.data())),
        repaymentsSnap.docs.map((d) => repaymentOf(d.data())),
      );
      final double totalExpenses = expensesSnap.docs.fold(
          0.0, (s, d) => s + ((d.data()['amount'] ?? 0.0) as num).toDouble());
      final double totalOutstandingCredit = creditSnap.docs.fold(0.0,
          (s, d) => s + ((d.data()['totalPending'] ?? 0.0) as num).toDouble());
      final double totalDiscrepancy = reconSnap.docs.fold(0.0,
          (s, d) => s + ((d.data()['discrepancy'] ?? 0.0) as num).toDouble());

      final summaryRows = buildExecutiveSummaryRows(
        allSummary,
        expenses: totalExpenses,
        creditStillDue: totalOutstandingCredit,
        cumulativeDiscrepancy: totalDiscrepancy,
      );

      dashboardSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
          .value = TextCellValue(
          'All dates and times are Indian Standard Time (IST, UTC+05:30).');
      dashboardSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3))
          .value = TextCellValue('Metric');
      dashboardSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3))
          .value = TextCellValue('Total Value (INR)');
      dashboardSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 3))
          .value = TextCellValue('Basis / Formula');
      for (int i = 0; i < summaryRows.length; i++) {
        dashboardSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4 + i))
            .value = TextCellValue(summaryRows[i].label);
        dashboardSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 4 + i))
            .value = DoubleCellValue(summaryRows[i].value);
        dashboardSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 4 + i))
            .value = TextCellValue(summaryRows[i].formula);
      }

      // Per-branch summary in the dashboard sheet
      int bRow = 4 + summaryRows.length + 2;
      dashboardSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: bRow++))
          .value = TextCellValue('BRANCH-WISE BREAKDOWN');
      const branchHeaders = [
        'Branch',
        'Sales (INR)',
        'Bills Count',
        'Expenses (INR)',
        'Cash Sales (INR)',
        'UPI Sales (INR)',
        'Credit Issued (INR)',
        'Cash Repayments (INR)',
        'UPI Repayments (INR)',
        'Accrual Operating Position (INR)',
        'Cash-Basis Movement (INR)',
      ];
      for (int c = 0; c < branchHeaders.length; c++) {
        dashboardSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: bRow))
            .value = TextCellValue(branchHeaders[c]);
      }
      bRow++;
      for (final bId in branchIds) {
        final bSummary = FinancialSummary.fromRecords(
          billsSnap.docs
              .where((d) => branchOf(d.data()) == bId)
              .map((d) => saleOf(d.data())),
          repaymentsSnap.docs
              .where((d) => branchOf(d.data()) == bId)
              .map((d) => repaymentOf(d.data())),
        );
        final bExp = expensesSnap.docs
            .where((d) => branchOf(d.data()) == bId)
            .fold<double>(
                0.0,
                (total, d) =>
                    total + ((d.data()['amount'] ?? 0.0) as num).toDouble());
        final cells = <CellValue>[
          TextCellValue(resolveCanteenName(bId)),
          DoubleCellValue(bSummary.salesRevenue),
          IntCellValue(bSummary.billCount),
          DoubleCellValue(bExp),
          DoubleCellValue(bSummary.cashSales),
          DoubleCellValue(bSummary.upiSales),
          DoubleCellValue(bSummary.creditSales),
          DoubleCellValue(bSummary.cashRepayments),
          DoubleCellValue(bSummary.upiRepayments),
          DoubleCellValue(accrualOperatingPosition(bSummary, bExp)),
          DoubleCellValue(cashBasisMovement(bSummary, bExp)),
        ];
        for (int c = 0; c < cells.length; c++) {
          dashboardSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: bRow))
              .value = cells[c];
        }
        bRow++;
      }

      // SHEET: All Bills (combined with canteen column)
      Sheet billsSheet = excel['All Bills'];
      writeHeader(billsSheet, [
        'Date & Time',
        'Bill Number',
        'Canteen Branch',
        'Customer Name',
        'Customer Phone',
        'Payment Mode',
        'Total Amount (INR)'
      ]);
      for (int i = 0; i < billsSnap.docs.length; i++) {
        final d = billsSnap.docs[i].data();
        final ts = d['timestamp'] as Timestamp?;
        final dateStr = ts != null
            ? DateFormat('yyyy-MM-dd HH:mm')
                .format(BusinessTime.wallClock(ts.toDate()))
            : 'N/A';
        final cId = (d['canteenId'] ?? 'main').toString();
        billsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
            .value = TextCellValue(dateStr);
        billsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
            .value = IntCellValue((d['billNumber'] ?? 0) as int);
        billsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
            .value = TextCellValue(resolveCanteenName(cId));
        billsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1))
            .value = TextCellValue((d['customerName'] ?? 'Walk-in').toString());
        billsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1))
            .value = TextCellValue((d['customerPhone'] ?? '-').toString());
        billsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1))
            .value = TextCellValue((d['paymentMode'] ?? '').toString());
        billsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: i + 1))
            .value = DoubleCellValue(((d['totalAmount'] ?? 0.0)
                as num)
            .toDouble());
      }

      // Per-branch Bills sheets
      for (final bId in branchIds) {
        final bName = resolveCanteenName(bId);
        final sheetName =
            '${bName.length > 22 ? bName.substring(0, 22) : bName} Bills';
        Sheet branchSheet = excel[sheetName];
        writeHeader(branchSheet, [
          'Date & Time',
          'Bill Number',
          'Customer Name',
          'Customer Phone',
          'Payment Mode',
          'Total Amount (INR)'
        ]);
        int row = 1;
        for (final doc in billsSnap.docs) {
          final d = doc.data();
          final cId = (d['canteenId'] ?? 'main').toString();
          if ((cId.isEmpty ? 'main' : cId) != bId) continue;
          final ts = d['timestamp'] as Timestamp?;
          final dateStr = ts != null
              ? DateFormat('yyyy-MM-dd HH:mm')
                .format(BusinessTime.wallClock(ts.toDate()))
              : 'N/A';
          branchSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
              .value = TextCellValue(dateStr);
          branchSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
              .value = IntCellValue((d['billNumber'] ?? 0) as int);
          branchSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
              .value = TextCellValue((d['customerName'] ??
                  'Walk-in')
              .toString());
          branchSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
              .value = TextCellValue((d['customerPhone'] ?? '-').toString());
          branchSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
              .value = TextCellValue((d['paymentMode'] ?? '').toString());
          branchSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
              .value = DoubleCellValue(((d['totalAmount'] ?? 0.0)
                  as num)
              .toDouble());
          row++;
        }
      }

      // SHEET: All Expenses (combined with canteen column)
      Sheet expSheet = excel['All Expenses'];
      writeHeader(expSheet,
          ['Date & Time', 'Canteen Branch', 'Description', 'Amount (INR)']);
      for (int i = 0; i < expensesSnap.docs.length; i++) {
        final d = expensesSnap.docs[i].data();
        final ts = d['timestamp'] as Timestamp?;
        final dateStr = ts != null
            ? DateFormat('yyyy-MM-dd HH:mm')
                .format(BusinessTime.wallClock(ts.toDate()))
            : 'N/A';
        final cId = (d['canteenId'] ?? 'main').toString();
        expSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
            .value = TextCellValue(dateStr);
        expSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
            .value = TextCellValue(resolveCanteenName(cId));
        expSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
            .value = TextCellValue((d['description'] ?? '').toString());
        expSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1))
            .value = DoubleCellValue(((d['amount'] ?? 0.0) as num).toDouble());
      }

      // Per-branch Expenses sheets
      for (final bId in branchIds) {
        final bName = resolveCanteenName(bId);
        final sheetName =
            '${bName.length > 19 ? bName.substring(0, 19) : bName} Expenses';
        Sheet branchExp = excel[sheetName];
        writeHeader(branchExp, ['Date & Time', 'Description', 'Amount (INR)']);
        int row = 1;
        for (final doc in expensesSnap.docs) {
          final d = doc.data();
          final cId = (d['canteenId'] ?? 'main').toString();
          if ((cId.isEmpty ? 'main' : cId) != bId) continue;
          final ts = d['timestamp'] as Timestamp?;
          final dateStr = ts != null
              ? DateFormat('yyyy-MM-dd HH:mm')
                .format(BusinessTime.wallClock(ts.toDate()))
              : 'N/A';
          branchExp
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
              .value = TextCellValue(dateStr);
          branchExp
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
              .value = TextCellValue((d['description'] ?? '').toString());
          branchExp
              .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
              .value = DoubleCellValue(((d['amount'] ?? 0.0)
                  as num)
              .toDouble());
          row++;
        }
      }

      // Credit Accounts
      Sheet creditSheet = excel['Credit Accounts'];
      writeHeader(creditSheet,
          ['Customer Name', 'Phone Number', 'Total Pending Due (INR)']);
      for (int i = 0; i < creditSnap.docs.length; i++) {
        final d = creditSnap.docs[i].data();
        creditSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
            .value = TextCellValue((d['name'] ?? 'Unknown').toString());
        creditSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
            .value = TextCellValue((d['phone'] ?? '').toString());
        creditSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
            .value = DoubleCellValue(((d['totalPending'] ?? 0.0)
                as num)
            .toDouble());
      }

      // Repayment Logs
      Sheet repSheet = excel['Repayment Logs'];
      writeHeader(repSheet, [
        'Date & Time',
        'Customer Name',
        'Customer Phone',
        'Cleared Mode',
        'Repayment Amount (INR)',
        'Processed By'
      ]);
      for (int i = 0; i < repaymentsSnap.docs.length; i++) {
        final d = repaymentsSnap.docs[i].data();
        final ts = d['timestamp'] as Timestamp?;
        final dateStr = ts != null
            ? DateFormat('yyyy-MM-dd HH:mm')
                .format(BusinessTime.wallClock(ts.toDate()))
            : 'N/A';
        repSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
            .value = TextCellValue(dateStr);
        repSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
            .value = TextCellValue((d['customerName'] ?? 'Unknown').toString());
        repSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
            .value = TextCellValue((d['customerPhone'] ?? '-').toString());
        repSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1))
            .value = TextCellValue((d['paymentMode'] ?? '').toString());
        repSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1))
            .value = DoubleCellValue(((d['amount'] ?? 0.0) as num).toDouble());
        repSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1))
            .value = TextCellValue((d['processedBy'] ?? '').toString());
      }

      // Cash Reconciliations
      Sheet reconSheet = excel['Cash Reconciliations'];
      writeHeader(reconSheet, [
        'Reconciled Date',
        'System Cash (INR)',
        'Actual Cash (INR)',
        'Discrepancy (INR)',
        'Audited By',
        'Notes',
        'Timestamp'
      ]);
      for (int i = 0; i < reconSnap.docs.length; i++) {
        final d = reconSnap.docs[i].data();
        final ts = d['timestamp'] as Timestamp?;
        final dateStr = ts != null
            ? DateFormat('yyyy-MM-dd HH:mm')
                .format(BusinessTime.wallClock(ts.toDate()))
            : 'N/A';
        reconSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
            .value = TextCellValue((d['date'] ?? '').toString());
        reconSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
            .value = DoubleCellValue(((d['systemCash'] ?? 0.0)
                as num)
            .toDouble());
        reconSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
            .value = DoubleCellValue(((d['actualCash'] ?? 0.0)
                as num)
            .toDouble());
        reconSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1))
            .value = DoubleCellValue(((d['discrepancy'] ?? 0.0)
                as num)
            .toDouble());
        reconSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1))
            .value = TextCellValue((d['submittedBy'] ?? '').toString());
        reconSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1))
            .value = TextCellValue((d['note'] ?? '').toString());
        reconSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: i + 1))
            .value = TextCellValue(dateStr);
      }

      // Top Selling Items
      Sheet topSheet = excel['Top Selling Items'];
      writeHeader(topSheet, ['Menu Item Name', 'Portions Sold (Total)']);
      Map<String, int> topItemsMap = {};
      for (var doc in billsSnap.docs) {
        final items =
            List<Map<String, dynamic>>.from(doc.data()['items'] ?? []);
        for (var item in items) {
          final name = item['name']?.toString() ?? 'Unknown';
          final qty = (item['quantity'] ?? 0) as int;
          topItemsMap[name] = (topItemsMap[name] ?? 0) + qty;
        }
      }
      final sortedTopItems = topItemsMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (int i = 0; i < sortedTopItems.length; i++) {
        topSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
            .value = TextCellValue(sortedTopItems[i].key);
        topSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
            .value = IntCellValue(sortedTopItems[i].value);
      }

      // Save & Share
      final bytes = excel.encode();
      if (bytes != null) {
        final tempDir = await getTemporaryDirectory();
        final file = await File(
                '${tempDir.path}/Canteen_Report_${BusinessTime.dateKey(DateTime.now()).replaceAll('-', '')}.xlsx')
            .create();
        await file.writeAsBytes(bytes);
        if (context.mounted) {
          Navigator.pop(context);
          final xFile = XFile(file.path);
          await Share.shareXFiles([xFile],
              text: 'Canteen Full Ledger & Analytics - All Branches');
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export Excel: $e', style: AppText.style()),
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
                        style: AppText.style(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text(_currentUser?.email ?? '',
                        style:
                            AppText.style(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _drawerTile(Icons.storefront_rounded, 'Manage Canteens & Staff',
              AppColors.accentGreen, () {
            Navigator.pop(context);
            _showManageCanteensAndStaffDialog();
          }),
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
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminMasterCreditLedgerPage()));
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
              AppColors.accentPurple, () {
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
          style: AppText.style(
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
              style: AppText.style(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppText.style(
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
    return StreamBuilder<List<MapEntry<String, Map<String, dynamic>>>>(
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
              style:
                  AppText.style(color: AppColors.textSecondary, fontSize: 13),
            ),
          );
        }

        final docs = snapshot.data!;

        List<FlSpot> salesSpots = [];
        List<FlSpot> creditSpots = [];

        double maxVal = 1000.0;

        for (int i = 0; i < docs.length; i++) {
          final data = docs[i].value;
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
                          style: AppText.style(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Comparison of sales & outstanding credit',
                          style: AppText.style(
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
                              AppText.style(
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
                            final date = DateTime.parse(docs[index].key);
                            return SideTitleWidget(
                              meta: meta,
                              space: 4,
                              child: Text(
                                DateFormat('dd MMM').format(date),
                                style: AppText.style(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
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
                                style: AppText.style(
                                  color: AppColors.textHint,
                                  fontSize: 10,
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
                            colors: [AppColors.gradBlue, AppColors.accentBlue]),
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              AppColors.gradBlue.withValues(alpha: 0.2),
                              AppColors.gradBlue.withValues(alpha: 0.0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      LineChartBarData(
                        spots: creditSpots,
                        isCurved: true,
                        gradient: const LinearGradient(colors: [
                          AppColors.accentOrange,
                          AppColors.accentOrange
                        ]),
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              AppColors.accentOrange.withValues(alpha: 0.15),
                              AppColors.accentOrange.withValues(alpha: 0.0),
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
          style: AppText.style(
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
                  icon: const Icon(Icons.file_download_outlined,
                      color: Colors.white, size: 24),
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
                                style: AppText.style(
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
                                    style: AppText.style(
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
                              style: AppText.style(
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
                // Multi-Canteen Switcher Bar
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('canteens')
                      .snapshots(),
                  builder: (context, snapshot) {
                    List<Map<String, String>> canteenOptions = [
                      {'id': 'all', 'name': 'All Canteens (Overall)'},
                      {'id': 'main', 'name': 'Main Canteen'},
                    ];
                    if (snapshot.hasData) {
                      for (var doc in snapshot.data!.docs) {
                        if (doc.id != 'main') {
                          canteenOptions.add({
                            'id': doc.id,
                            'name':
                                (doc.data() as Map<String, dynamic>)['name'] ??
                                    doc.id,
                          });
                        }
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: glassCard(
                        radius: 16,
                        borderColor:
                            AppColors.accentBlue.withValues(alpha: 0.3),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.accentBlue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.storefront_rounded,
                                color: AppColors.accentBlue, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ACTIVE CANTEEN VIEW',
                                  style: AppText.style(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: canteenOptions.any((c) =>
                                            c['id'] == _selectedCanteenFilter)
                                        ? _selectedCanteenFilter
                                        : 'all',
                                    isExpanded: true,
                                    dropdownColor: AppColors.bgCard,
                                    icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Colors.white),
                                    items: canteenOptions.map((c) {
                                      return DropdownMenuItem<String>(
                                        value: c['id'],
                                        child: Text(
                                          c['name']!,
                                          style: AppText.style(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (newVal) {
                                      if (newVal != null) {
                                        setState(() {
                                          _selectedCanteenFilter = newVal;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
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
                    StreamBuilder<Map<String, dynamic>>(
                      stream: _getDailyStatsStream(),
                      builder: (context, snap) {
                        String sales = '₹0';
                        if (snap.hasData) {
                          final d = snap.data!;
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
                        style: AppText.style(
                          color: AppColors.accentBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                StreamBuilder<List<DocumentSnapshot>>(
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
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: glassCard(radius: 16),
                        alignment: Alignment.center,
                        child: Text(
                          'No recent bills recorded.',
                          style: AppText.style(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      );
                    }

                    final bills = snapshot.data!;

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
                                    style: AppText.style(
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
                                        style: AppText.style(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        timeStr,
                                        style: AppText.style(
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
                                      style: AppText.style(
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
    final monthId = BusinessTime.monthKey(now);
    final month = BusinessTime.monthRange(now);

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
              .where('timestamp', isGreaterThanOrEqualTo: month.start)
              .where('timestamp', isLessThan: month.end)
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
                            style: AppText.style(
                                color: AppColors.accentRed,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            available < 0
                                ? 'You have exceeded the allocated budget by ₹${available.abs().toStringAsFixed(0)}.'
                                : 'Available: ₹${available.toStringAsFixed(0)} left of ₹${allocated.toStringAsFixed(0)} allocated.',
                            style: AppText.style(
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

  // ─────────────────────────────────────────────────────────────────────────
  // MANAGE CANTEENS & STAFF — full CRUD dialog
  // ─────────────────────────────────────────────────────────────────────────

  void _showManageCanteensAndStaffDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ManageCanteensSheet(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM SHEET WIDGET — Manage Canteens & Staff
// ─────────────────────────────────────────────────────────────────────────────

class _ManageCanteensSheet extends StatefulWidget {
  const _ManageCanteensSheet();

  @override
  State<_ManageCanteensSheet> createState() => _ManageCanteensSheetState();
}

class _ManageCanteensSheetState extends State<_ManageCanteensSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accentGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.storefront_rounded,
                        color: AppColors.accentGreen, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Manage Canteens & Staff',
                    style: AppText.style(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              indicatorColor: AppColors.accentGreen,
              labelColor: AppColors.accentGreen,
              unselectedLabelColor: Colors.white54,
              labelStyle:
                  AppText.style(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(
                    icon: Icon(Icons.store_rounded, size: 18),
                    text: 'Canteens'),
                Tab(icon: Icon(Icons.people_rounded, size: 18), text: 'Staff'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _CanteensTab(),
                  _StaffTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — CANTEENS
// ─────────────────────────────────────────────────────────────────────────────

class _CanteensTab extends StatefulWidget {
  const _CanteensTab();

  @override
  State<_CanteensTab> createState() => _CanteensTabState();
}

class _CanteensTabState extends State<_CanteensTab> {
  String? _expandedCanteenId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accentGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Add Branch',
            style: AppText.style(
                color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () => _showAddCanteenDialog(context),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('canteens').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.accentGreen));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.store_rounded,
                      size: 56, color: Colors.white24),
                  const SizedBox(height: 12),
                  Text('No canteen branches yet',
                      style:
                          AppText.style(color: Colors.white54, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text('Tap + Add Branch to create one',
                      style:
                          AppText.style(color: Colors.white38, fontSize: 12)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final name = data['name'] ?? doc.id;
              final isMain = doc.id == 'main';
              final isExpanded = _expandedCanteenId == doc.id;
              return Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() {
                      _expandedCanteenId = isExpanded ? null : doc.id;
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isMain
                              ? AppColors.accentGreen.withValues(alpha: 0.4)
                              : AppColors.glassBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.accentGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.store_rounded,
                                color: AppColors.accentGreen, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(name,
                                        style: AppText.style(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    if (isMain) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentGreen
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text('Default',
                                            style: AppText.style(
                                                color: AppColors.accentGreen,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                    ]
                                  ],
                                ),
                                Text('ID: ${doc.id}',
                                    style: AppText.style(
                                        color: Colors.white38, fontSize: 10)),
                              ],
                            ),
                          ),
                          if (!isMain)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded,
                                      color: AppColors.accentBlue, size: 18),
                                  onPressed: () => _showEditCanteenDialog(
                                      context, doc.id, name),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      color: AppColors.accentRed, size: 18),
                                  onPressed: () => _confirmDeleteCanteen(
                                      context, doc.id, name),
                                ),
                              ],
                            ),
                          AnimatedRotation(
                            turns: isExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: const Icon(Icons.expand_more_rounded,
                                color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isExpanded) _AssignedCanteenStaff(canteenId: doc.id),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _showAddCanteenDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Add Canteen Branch',
        icon: Icons.add_business_rounded,
        iconColor: AppColors.accentGreen,
        fields: [
          _FieldDef(
              ctrl: nameCtrl,
              label: 'Branch Name',
              hint: 'e.g. Canteen 2 – North Wing'),
        ],
        onConfirm: () async {
          final name = nameCtrl.text.trim();
          if (name.isEmpty) return;
          // Generate a clean ID from name
          final id = name
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
              .replaceAll(RegExp(r'_+'), '_')
              .replaceAll(RegExp(r'^_|_$'), '');
          await FirebaseFirestore.instance.collection('canteens').doc(id).set({
            'name': name,
            'createdAt': FieldValue.serverTimestamp(),
          });
        },
      ),
    );
  }

  void _showEditCanteenDialog(
      BuildContext context, String id, String currentName) {
    final nameCtrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (_) => _InputDialog(
        title: 'Rename Branch',
        icon: Icons.edit_rounded,
        iconColor: AppColors.accentBlue,
        fields: [
          _FieldDef(ctrl: nameCtrl, label: 'Branch Name', hint: ''),
        ],
        onConfirm: () async {
          final name = nameCtrl.text.trim();
          if (name.isEmpty) return;
          await FirebaseFirestore.instance
              .collection('canteens')
              .doc(id)
              .update({'name': name});
          // Also update all staff assigned to this canteen
          final staffSnap = await FirebaseFirestore.instance
              .collection('canteenStaff')
              .where('canteenId', isEqualTo: id)
              .get();
          final batch = FirebaseFirestore.instance.batch();
          for (final s in staffSnap.docs) {
            batch.update(s.reference, {'canteenName': name});
          }
          await batch.commit();
        },
      ),
    );
  }

  void _confirmDeleteCanteen(BuildContext context, String id, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "$name"?',
            style: AppText.style(
                color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          'This removes the branch record. Staff assigned here will fall back to Main Canteen. Existing bills are not deleted.',
          style: AppText.style(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  Text('Cancel', style: AppText.style(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentRed,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance
                  .collection('canteens')
                  .doc(id)
                  .delete();
              // Unassign staff from this canteen
              final staffSnap = await FirebaseFirestore.instance
                  .collection('canteenStaff')
                  .where('canteenId', isEqualTo: id)
                  .get();
              final batch = FirebaseFirestore.instance.batch();
              for (final s in staffSnap.docs) {
                batch.update(s.reference, {
                  'canteenId': 'main',
                  'canteenName': 'Main Canteen',
                });
              }
              await batch.commit();
            },
            child: Text('Delete',
                style: AppText.style(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _AssignedCanteenStaff extends StatelessWidget {
  final String canteenId;

  const _AssignedCanteenStaff({required this.canteenId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('canteenStaff').snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: CircularProgressIndicator(
                    color: AppColors.accentGreen, strokeWidth: 2)),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Unable to load assigned staff.',
                style: AppText.style(color: AppColors.accentRed, fontSize: 12)),
          );
        }

        final staff = (snap.data?.docs ?? []).where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['canteenId'] ?? 'main').toString() == canteenId;
        }).toList()
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            return (aData['email'] ?? '').toString().compareTo(
                  (bData['email'] ?? '').toString(),
                );
          });

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups_rounded,
                      color: AppColors.accentBlue, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Assigned Staff (${staff.length})',
                    style: AppText.style(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (staff.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'No staff assigned to this canteen.',
                    style: AppText.style(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                )
              else ...[
                const SizedBox(height: 8),
                for (final doc in staff) ...[
                  if (doc != staff.first)
                    const Divider(color: AppColors.bgDivider, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline_rounded,
                            color: AppColors.textSecondary, size: 18),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            ((doc.data() as Map<String, dynamic>)['email'] ??
                                    'No email')
                                .toString(),
                            style: AppText.style(
                                color: AppColors.textPrimary, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          (((doc.data() as Map<String, dynamic>)['role'] ??
                                  'cashier') as String)
                              .toUpperCase(),
                          style: AppText.style(
                              color: AppColors.accentBlue,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — STAFF
// ─────────────────────────────────────────────────────────────────────────────

class _StaffTab extends StatelessWidget {
  const _StaffTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accentBlue,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: Text('Add Staff',
            style: AppText.style(
                color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () => _showAddStaffDialog(context),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('canteenStaff')
            .orderBy('email')
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.accentBlue));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_outline_rounded,
                      size: 56, color: Colors.white24),
                  const SizedBox(height: 12),
                  Text('No staff accounts yet',
                      style:
                          AppText.style(color: Colors.white54, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text('Tap + Add Staff to create one',
                      style:
                          AppText.style(color: Colors.white38, fontSize: 12)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final email = data['email'] ?? 'No email';
              final role = data['role'] ?? 'cashier';
              final canteenName = data['canteenName'] ?? 'Main Canteen';
              final isAdmin = role == 'admin';
              final roleColor =
                  isAdmin ? AppColors.accentOrange : AppColors.accentBlue;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: roleColor.withValues(alpha: 0.15),
                      child: Text(
                        (email.isNotEmpty ? email[0] : '?').toUpperCase(),
                        style: AppText.style(
                          color: roleColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(email,
                              style: AppText.style(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: roleColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  role.toUpperCase(),
                                  style: AppText.style(
                                      color: roleColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  canteenName,
                                  style: AppText.style(
                                      color: Colors.white54, fontSize: 10),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      color: AppColors.bgInput,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      icon: const Icon(Icons.more_vert,
                          color: Colors.white54, size: 20),
                      onSelected: (val) {
                        if (val == 'reassign') {
                          _showReassignDialog(context, doc.id, data);
                        } else if (val == 'reset_pass') {
                          _sendPasswordReset(context, email);
                        } else if (val == 'delete') {
                          _confirmDeleteStaff(context, doc.id, email);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'reassign',
                          child: Row(children: [
                            const Icon(Icons.swap_horiz_rounded,
                                size: 16, color: AppColors.accentBlue),
                            const SizedBox(width: 8),
                            Text('Reassign Canteen',
                                style: AppText.style(
                                    color: Colors.white, fontSize: 13)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'reset_pass',
                          child: Row(children: [
                            const Icon(Icons.lock_reset_rounded,
                                size: 16, color: AppColors.accentOrange),
                            const SizedBox(width: 8),
                            Text('Send Password Reset',
                                style: AppText.style(
                                    color: Colors.white, fontSize: 13)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            const Icon(Icons.person_remove_rounded,
                                size: 16, color: AppColors.accentRed),
                            const SizedBox(width: 8),
                            Text('Remove Staff',
                                style: AppText.style(
                                    color: AppColors.accentRed, fontSize: 13)),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ── Add Staff (uses secondary FirebaseApp so admin stays logged in) ──────
  void _showAddStaffDialog(BuildContext context) {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = 'cashier';
    String selectedCanteenId = 'main';
    String selectedCanteenName = 'Main Canteen';
    bool isLoading = false;
    String errorMsg = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.bgCard,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_add_rounded,
                    color: AppColors.accentBlue, size: 20),
              ),
              const SizedBox(width: 10),
              Text('Add Staff Account',
                  style: AppText.style(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ]),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (errorMsg.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.accentRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color:
                                  AppColors.accentRed.withValues(alpha: 0.4)),
                        ),
                        child: Text(errorMsg,
                            style: AppText.style(
                                color: AppColors.accentRed, fontSize: 12)),
                      ),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: AppText.style(color: Colors.white, fontSize: 13),
                      decoration:
                          _inputDeco('Email Address', Icons.email_outlined),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      style: AppText.style(color: Colors.white, fontSize: 13),
                      decoration: _inputDeco(
                          'Password (min 6 chars)', Icons.lock_outline),
                    ),
                    const SizedBox(height: 12),
                    // Role picker
                    Text('Role',
                        style:
                            AppText.style(color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 6),
                    Row(children: [
                      _roleChip('cashier', selectedRole,
                          (v) => setDialogState(() => selectedRole = v)),
                      const SizedBox(width: 8),
                      _roleChip('admin', selectedRole,
                          (v) => setDialogState(() => selectedRole = v)),
                    ]),
                    const SizedBox(height: 12),
                    // Canteen picker
                    Text('Assign to Canteen',
                        style:
                            AppText.style(color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 6),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('canteens')
                          .snapshots(),
                      builder: (_, snap) {
                        final List<DropdownMenuItem<String>> items = [];
                        if (snap.hasData) {
                          for (final doc in snap.data!.docs) {
                            final d = doc.data() as Map<String, dynamic>;
                            items.add(DropdownMenuItem(
                              value: doc.id,
                              child: Text(
                                d['name'] ?? doc.id,
                                style: AppText.style(
                                    color: Colors.white, fontSize: 13),
                              ),
                            ));
                          }
                        }
                        if (items.isEmpty) {
                          items.add(DropdownMenuItem(
                            value: 'main',
                            child: Text('Main Canteen',
                                style: AppText.style(
                                    color: Colors.white, fontSize: 13)),
                          ));
                        }
                        return DropdownButtonFormField<String>(
                          initialValue: selectedCanteenId,
                          dropdownColor: AppColors.bgInput,
                          decoration: _inputDeco(
                              'Select Branch', Icons.storefront_rounded),
                          items: items,
                          onChanged: (val) {
                            if (val == null) return;
                            final d = (snap.data?.docs
                                .where((e) => e.id == val)
                                .firstOrNull
                                ?.data() as Map<String, dynamic>?);
                            setDialogState(() {
                              selectedCanteenId = val;
                              selectedCanteenName =
                                  d?['name'] ?? 'Main Canteen';
                            });
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(dialogCtx),
                child:
                    Text('Cancel', style: AppText.style(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: isLoading
                    ? null
                    : () async {
                        final email = emailCtrl.text.trim();
                        final pass = passCtrl.text.trim();
                        if (email.isEmpty || pass.isEmpty) {
                          setDialogState(() =>
                              errorMsg = 'Email and password are required.');
                          return;
                        }
                        if (pass.length < 6) {
                          setDialogState(() => errorMsg =
                              'Password must be at least 6 characters.');
                          return;
                        }
                        setDialogState(() {
                          isLoading = true;
                          errorMsg = '';
                        });
                        try {
                          // Use secondary FirebaseApp to create user without
                          // signing out the currently logged-in admin.
                          FirebaseApp? secondaryApp;
                          try {
                            secondaryApp = Firebase.app('StaffCreator');
                          } catch (_) {
                            secondaryApp = await Firebase.initializeApp(
                              name: 'StaffCreator',
                              options: Firebase.app().options,
                            );
                          }
                          final secondaryAuth =
                              FirebaseAuth.instanceFor(app: secondaryApp);
                          final cred = await secondaryAuth
                              .createUserWithEmailAndPassword(
                                  email: email, password: pass);
                          await secondaryAuth.signOut();
                          final uid = cred.user!.uid;
                          // Write staff Firestore doc
                          await FirebaseFirestore.instance
                              .collection('canteenStaff')
                              .doc(uid)
                              .set({
                            'email': email,
                            'role': selectedRole,
                            'canteenId': selectedCanteenId,
                            'canteenName': selectedCanteenName,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        } on FirebaseAuthException catch (e) {
                          setDialogState(() {
                            isLoading = false;
                            errorMsg = e.message ?? 'Failed to create account.';
                          });
                        } catch (e) {
                          setDialogState(() {
                            isLoading = false;
                            errorMsg = 'Error: $e';
                          });
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Create',
                        style: AppText.style(
                            color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        });
      },
    );
  }

  // ── Reassign canteen ─────────────────────────────────────────────────────
  void _showReassignDialog(
      BuildContext context, String uid, Map<String, dynamic> data) {
    String selectedId = data['canteenId'] ?? 'main';
    String selectedName = data['canteenName'] ?? 'Main Canteen';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setSt) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Reassign Canteen',
              style: AppText.style(
                  color: Colors.white, fontWeight: FontWeight.w700)),
          content: StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance.collection('canteens').snapshots(),
            builder: (_, snap) {
              final List<DropdownMenuItem<String>> items = [];
              if (snap.hasData) {
                for (final doc in snap.data!.docs) {
                  final d = doc.data() as Map<String, dynamic>;
                  items.add(DropdownMenuItem(
                    value: doc.id,
                    child: Text(d['name'] ?? doc.id,
                        style:
                            AppText.style(color: Colors.white, fontSize: 13)),
                  ));
                }
              }
              if (items.isEmpty) {
                items.add(DropdownMenuItem(
                  value: 'main',
                  child: Text('Main Canteen',
                      style: AppText.style(color: Colors.white, fontSize: 13)),
                ));
              }
              return DropdownButtonFormField<String>(
                initialValue: selectedId,
                dropdownColor: AppColors.bgInput,
                decoration:
                    _inputDeco('Select Branch', Icons.storefront_rounded),
                items: items,
                onChanged: (val) {
                  if (val == null) return;
                  final d = (snap.data?.docs
                      .where((e) => e.id == val)
                      .firstOrNull
                      ?.data() as Map<String, dynamic>?);
                  setSt(() {
                    selectedId = val;
                    selectedName = d?['name'] ?? 'Main Canteen';
                  });
                },
              );
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Cancel',
                    style: AppText.style(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('canteenStaff')
                    .doc(uid)
                    .update({
                  'canteenId': selectedId,
                  'canteenName': selectedName,
                });
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              },
              child: Text('Save',
                  style: AppText.style(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Send password reset email ─────────────────────────────────────────────
  void _sendPasswordReset(BuildContext context, String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Password reset email sent to $email',
              style: AppText.style()),
          backgroundColor: AppColors.accentGreen,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e', style: AppText.style()),
          backgroundColor: AppColors.accentRed,
        ));
      }
    }
  }

  // ── Delete staff Firestore doc ────────────────────────────────────────────
  void _confirmDeleteStaff(BuildContext context, String uid, String email) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove "$email"?',
            style: AppText.style(
                color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          'This removes their staff access record, so they can no longer use the app or read any data. Their login credentials still exist in Firebase Authentication and can be deleted from the Firebase console.',
          style: AppText.style(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  Text('Cancel', style: AppText.style(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentRed,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance
                  .collection('canteenStaff')
                  .doc(uid)
                  .delete();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text('Staff "$email" removed.', style: AppText.style()),
                  backgroundColor: AppColors.accentGreen,
                ));
              }
            },
            child: Text('Remove',
                style: AppText.style(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED HELPERS
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
      labelText: label,
      labelStyle: AppText.style(color: Colors.white54, fontSize: 12),
      prefixIcon: Icon(icon, color: Colors.white38, size: 18),
      filled: true,
      fillColor: AppColors.bgInput,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.bgDivider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.bgDivider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accentBlue, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

Widget _roleChip(String role, String selectedRole, ValueChanged<String> onTap) {
  final selected = role == selectedRole;
  final color = role == 'admin' ? AppColors.accentOrange : AppColors.accentBlue;
  return GestureDetector(
    onTap: () => onTap(role),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.2) : AppColors.bgInput,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? color : AppColors.bgDivider,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Text(
        role[0].toUpperCase() + role.substring(1),
        style: AppText.style(
          color: selected ? color : Colors.white54,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    ),
  );
}

// ── Generic multi-field input dialog ─────────────────────────────────────────
class _FieldDef {
  final TextEditingController ctrl;
  final String label;
  final String hint;
  const _FieldDef(
      {required this.ctrl, required this.label, required this.hint});
}

class _InputDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<_FieldDef> fields;
  final Future<void> Function() onConfirm;

  const _InputDialog({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.fields,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(title,
              style: AppText.style(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: fields
            .expand((f) => [
                  TextField(
                    controller: f.ctrl,
                    style: AppText.style(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: f.label,
                      hintText: f.hint,
                      labelStyle:
                          AppText.style(color: Colors.white54, fontSize: 12),
                      hintStyle:
                          AppText.style(color: Colors.white24, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.bgInput,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.bgDivider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.bgDivider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: iconColor, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                ])
            .toList(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppText.style(color: Colors.white54))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: iconColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          onPressed: () async {
            await onConfirm();
            if (context.mounted) Navigator.pop(context);
          },
          child: Text('Save',
              style: AppText.style(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
