import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart';

import 'business_time.dart';
import 'financial_metrics.dart';
import 'report_records.dart';

/// Builds the admin Excel workbook from plain [ReportData]. No Firestore, no
/// UI: the same code runs in the app and in tests that generate and inspect a
/// real .xlsx file.
///
/// Sheets (names and order unchanged): Dashboard Summary, All Bills,
/// one "Branch Bills" sheet per branch, All Expenses, one "Branch Expenses"
/// sheet per branch, Credit Accounts, Repayment Logs, Cash Reconciliations, Top Selling Items.
/// Existing columns keep their position; new columns are only appended.
/// All timestamps are rendered in IST (UTC+05:30).
class ExcelReportBuilder {
  ExcelReportBuilder._();

  static const _headerBg = 'FF1F3864';
  static const _titleBg = 'FFD9E2F3';
  static const _moneyFmt = NumFormat.standard_2; // 0.00

  static String _fmtTs(DateTime? ts) => ts == null
      ? 'N/A'
      : DateFormat('yyyy-MM-dd HH:mm').format(BusinessTime.wallClock(ts));

  static double _r2(double v) => (v * 100).roundToDouble() / 100;

  static CellStyle get _header => CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString(_headerBg),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );

  static CellStyle get _title => CellStyle(
        bold: true,
        fontSize: 14,
        backgroundColorHex: ExcelColor.fromHexString(_titleBg),
      );

  static CellStyle get _section => CellStyle(bold: true, fontSize: 12);

  static CellStyle get _money => CellStyle(numberFormat: _moneyFmt);

  static CellStyle get _moneyBold =>
      CellStyle(numberFormat: _moneyFmt, bold: true);

  static CellStyle get _wrap =>
      CellStyle(textWrapping: TextWrapping.WrapText, verticalAlign: VerticalAlign.Top);

  static void _put(Sheet s, int col, int row, CellValue v, [CellStyle? st]) {
    final c = s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    c.value = v;
    if (st != null) c.cellStyle = st;
  }

  static void _headerRow(Sheet s, List<String> cols, List<double> widths) {
    for (var i = 0; i < cols.length; i++) {
      _put(s, i, 0, TextCellValue(cols[i]), _header);
      s.setColumnWidth(i, i < widths.length ? widths[i] : 16);
    }
    s.setRowHeight(0, 32);
  }

  /// Excel sheet names: max 31 chars, none of : \ / ? * [ ], unique.
  static String _sheetName(String base, String suffix, Set<String> used) {
    final clean = base
        .replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final room = 31 - suffix.length;
    var name = '${clean.length > room ? clean.substring(0, room) : clean}$suffix';
    var n = 2;
    while (used.contains(name.toLowerCase())) {
      final tag = ' ($n)';
      final r = room - tag.length;
      name = '${clean.length > r ? clean.substring(0, r) : clean}$tag$suffix';
      n++;
    }
    used.add(name.toLowerCase());
    return name;
  }

  /// Returns the workbook. [generatedAt] is injectable for deterministic tests.
  static Excel build(ReportData data, {DateTime? generatedAt}) {
    final excel = Excel.createExcel();
    final used = <String>{};
    String nameOf(String id) {
      if (id.isEmpty || id == 'main') return data.canteenNames['main'] ?? 'Main Canteen';
      return data.canteenNames[id] ?? id;
    }

    // Branch ids exactly as before: 'main' first, then those seen in bills,
    // then in expenses.
    final branchIds = <String>{'main'};
    for (final b in data.bills) {
      branchIds.add(b.canteenId);
    }
    for (final e in data.expenses) {
      branchIds.add(e.canteenId);
    }

    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, 'Dashboard Summary');
    used.add('dashboard summary');
    final dash = excel['Dashboard Summary'];

    // ---------- source -> summaries ----------
    final sales = data.bills.map((b) => SaleRecord(b.amount, b.paymentMode));
    final reps = data.repayments.map((r) => RepaymentRecord(r.amount, r.paymentMode));
    final all = FinancialSummary.fromRecords(sales, reps);
    final totalExpenses = data.expenses.fold<double>(0, (t, e) => t + e.amount);
    final totalDue = data.credits.fold<double>(0, (t, c) => t + c.totalPending);
    final totalDisc = data.recons.fold<double>(0, (t, r) => t + r.discrepancy);
    final rows = buildExecutiveSummaryRows(all,
        expenses: totalExpenses,
        creditStillDue: totalDue,
        cumulativeDiscrepancy: totalDisc);

    // ---------- Dashboard Summary ----------
    _put(dash, 0, 0, TextCellValue('CANTEEN MANAGEMENT SUMMARY - ALL BRANCHES'), _title);
    _put(dash, 1, 0, TextCellValue(''), _title);
    _put(dash, 2, 0, TextCellValue(''), _title);
    final gen = generatedAt ?? DateTime.now();
    _put(dash, 0, 1, TextCellValue(
        'Report Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(BusinessTime.wallClock(gen))} IST'));
    _put(dash, 0, 2, TextCellValue(
        'Period: ${data.periodLabel}. All dates and times are Indian Standard Time (IST, UTC+05:30).'));
    const sumHeaderRow = 3;
    _put(dash, 0, sumHeaderRow, TextCellValue('Metric'), _header);
    _put(dash, 1, sumHeaderRow, TextCellValue('Total Value (INR)'), _header);
    _put(dash, 2, sumHeaderRow, TextCellValue('Basis / Formula'), _header);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final key = r.label.contains('Position') || r.label.contains('Movement');
      _put(dash, 0, 4 + i, TextCellValue(r.label),
          key ? CellStyle(bold: true) : null);
      _put(dash, 1, 4 + i, DoubleCellValue(_r2(r.value)),
          key ? _moneyBold : _money);
      _put(dash, 2, 4 + i, TextCellValue(r.formula), _wrap);
    }
    dash.setColumnWidth(0, 50);
    dash.setColumnWidth(1, 20);
    dash.setColumnWidth(2, 80);

    var bRow = 4 + rows.length + 2;
    _put(dash, 0, bRow++, TextCellValue('BRANCH-WISE BREAKDOWN'), _section);
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
    for (var c = 0; c < branchHeaders.length; c++) {
      _put(dash, c, bRow, TextCellValue(branchHeaders[c]), _header);
      if (c > 2) dash.setColumnWidth(c, 20);
    }
    dash.setRowHeight(bRow, 32);
    bRow++;
    for (final bId in branchIds) {
      final bs = FinancialSummary.fromRecords(
        data.bills.where((b) => b.canteenId == bId).map((b) => SaleRecord(b.amount, b.paymentMode)),
        data.repayments.where((r) => r.canteenId == bId).map((r) => RepaymentRecord(r.amount, r.paymentMode)),
      );
      final bExp = data.expenses
          .where((e) => e.canteenId == bId)
          .fold<double>(0, (t, e) => t + e.amount);
      final vals = <CellValue>[
        TextCellValue(nameOf(bId)),
        DoubleCellValue(_r2(bs.salesRevenue)),
        IntCellValue(bs.billCount),
        DoubleCellValue(_r2(bExp)),
        DoubleCellValue(_r2(bs.cashSales)),
        DoubleCellValue(_r2(bs.upiSales)),
        DoubleCellValue(_r2(bs.creditSales)),
        DoubleCellValue(_r2(bs.cashRepayments)),
        DoubleCellValue(_r2(bs.upiRepayments)),
        DoubleCellValue(_r2(accrualOperatingPosition(bs, bExp))),
        DoubleCellValue(_r2(cashBasisMovement(bs, bExp))),
      ];
      for (var c = 0; c < vals.length; c++) {
        _put(dash, c, bRow, vals[c], c == 0 || c == 2 ? null : _money);
      }
      bRow++;
    }

    // ---------- All Bills ----------
    final billsSheet = excel['All Bills'];
    used.add('all bills');
    _headerRow(billsSheet, [
      'Date & Time',
      'Bill Number',
      'Canteen Branch',
      'Customer Name',
      'Customer Phone',
      'Payment Mode',
      'Total Amount (INR)',
    ], [18, 13, 22, 24, 16, 14, 18]);
    for (var i = 0; i < data.bills.length; i++) {
      final b = data.bills[i];
      _put(billsSheet, 0, i + 1, TextCellValue(_fmtTs(b.timestamp)));
      _put(billsSheet, 1, i + 1, IntCellValue(b.billNumber));
      _put(billsSheet, 2, i + 1, TextCellValue(nameOf(b.canteenId)));
      _put(billsSheet, 3, i + 1, TextCellValue(b.customerName));
      _put(billsSheet, 4, i + 1, TextCellValue(b.customerPhone));
      _put(billsSheet, 5, i + 1, TextCellValue(b.paymentMode));
      _put(billsSheet, 6, i + 1, DoubleCellValue(_r2(b.amount)), _money);
    }

    for (final bId in branchIds) {
      final name = _sheetName(nameOf(bId), ' Bills', used);
      final sh = excel[name];
      _headerRow(sh, [
        'Date & Time',
        'Bill Number',
        'Customer Name',
        'Customer Phone',
        'Payment Mode',
        'Total Amount (INR)',
      ], [18, 13, 24, 16, 14, 18]);
      var row = 1;
      for (final b in data.bills.where((b) => b.canteenId == bId)) {
        _put(sh, 0, row, TextCellValue(_fmtTs(b.timestamp)));
        _put(sh, 1, row, IntCellValue(b.billNumber));
        _put(sh, 2, row, TextCellValue(b.customerName));
        _put(sh, 3, row, TextCellValue(b.customerPhone));
        _put(sh, 4, row, TextCellValue(b.paymentMode));
        _put(sh, 5, row, DoubleCellValue(_r2(b.amount)), _money);
        row++;
      }
    }

    // ---------- All Expenses ----------
    final expSheet = excel['All Expenses'];
    used.add('all expenses');
    _headerRow(expSheet,
        ['Date & Time', 'Canteen Branch', 'Description', 'Amount (INR)'],
        [18, 22, 40, 16]);
    for (var i = 0; i < data.expenses.length; i++) {
      final e = data.expenses[i];
      _put(expSheet, 0, i + 1, TextCellValue(_fmtTs(e.timestamp)));
      _put(expSheet, 1, i + 1, TextCellValue(nameOf(e.canteenId)));
      _put(expSheet, 2, i + 1, TextCellValue(e.description));
      _put(expSheet, 3, i + 1, DoubleCellValue(_r2(e.amount)), _money);
    }
    for (final bId in branchIds) {
      final name = _sheetName(nameOf(bId), ' Expenses', used);
      final sh = excel[name];
      _headerRow(sh, ['Date & Time', 'Description', 'Amount (INR)'], [18, 40, 16]);
      var row = 1;
      for (final e in data.expenses.where((e) => e.canteenId == bId)) {
        _put(sh, 0, row, TextCellValue(_fmtTs(e.timestamp)));
        _put(sh, 1, row, TextCellValue(e.description));
        _put(sh, 2, row, DoubleCellValue(_r2(e.amount)), _money);
        row++;
      }
    }

    // ---------- Credit Accounts ----------
    final creditSheet = excel['Credit Accounts'];
    used.add('credit accounts');
    _headerRow(creditSheet,
        ['Customer Name', 'Phone Number', 'Total Pending Due (INR)', 'Canteen Branch'],
        [26, 16, 22, 22]);
    for (var i = 0; i < data.credits.length; i++) {
      final c = data.credits[i];
      _put(creditSheet, 0, i + 1, TextCellValue(c.name));
      _put(creditSheet, 1, i + 1, TextCellValue(c.phone));
      _put(creditSheet, 2, i + 1, DoubleCellValue(_r2(c.totalPending)), _money);
      _put(creditSheet, 3, i + 1, TextCellValue(nameOf(c.canteenId)));
    }

    // ---------- Repayment Logs ----------
    final repSheet = excel['Repayment Logs'];
    used.add('repayment logs');
    _headerRow(repSheet, [
      'Date & Time',
      'Customer Name',
      'Customer Phone',
      'Cleared Mode',
      'Repayment Amount (INR)',
      'Processed By',
      'Canteen Branch',
    ], [18, 24, 16, 14, 22, 28, 22]);
    for (var i = 0; i < data.repayments.length; i++) {
      final r = data.repayments[i];
      _put(repSheet, 0, i + 1, TextCellValue(_fmtTs(r.timestamp)));
      _put(repSheet, 1, i + 1, TextCellValue(r.customerName));
      _put(repSheet, 2, i + 1, TextCellValue(r.customerPhone));
      _put(repSheet, 3, i + 1, TextCellValue(r.paymentMode));
      _put(repSheet, 4, i + 1, DoubleCellValue(_r2(r.amount)), _money);
      _put(repSheet, 5, i + 1, TextCellValue(r.processedBy));
      _put(repSheet, 6, i + 1, TextCellValue(nameOf(r.canteenId)));
    }

    // ---------- Cash Reconciliations ----------
    final reconSheet = excel['Cash Reconciliations'];
    used.add('cash reconciliations');
    _headerRow(reconSheet, [
      'Reconciled Date',
      'System Cash (INR)',
      'Actual Cash (INR)',
      'Discrepancy (INR)',
      'Audited By',
      'Notes',
      'Timestamp',
      'Canteen Branch',
    ], [16, 18, 18, 18, 28, 36, 18, 22]);
    for (var i = 0; i < data.recons.length; i++) {
      final r = data.recons[i];
      _put(reconSheet, 0, i + 1, TextCellValue(r.date));
      _put(reconSheet, 1, i + 1, DoubleCellValue(_r2(r.systemCash)), _money);
      _put(reconSheet, 2, i + 1, DoubleCellValue(_r2(r.actualCash)), _money);
      _put(reconSheet, 3, i + 1, DoubleCellValue(_r2(r.discrepancy)), _money);
      _put(reconSheet, 4, i + 1, TextCellValue(r.submittedBy));
      _put(reconSheet, 5, i + 1, TextCellValue(r.note));
      _put(reconSheet, 6, i + 1, TextCellValue(_fmtTs(r.timestamp)));
      _put(reconSheet, 7, i + 1, TextCellValue(nameOf(r.canteenId)));
    }

    // ---------- Top Selling Items ----------
    final topSheet = excel['Top Selling Items'];
    used.add('top selling items');
    _headerRow(topSheet, ['Menu Item Name', 'Portions Sold (Total)'], [32, 22]);
    final sorted = data.topItems.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    for (var i = 0; i < sorted.length; i++) {
      _put(topSheet, 0, i + 1, TextCellValue(sorted[i].key));
      _put(topSheet, 1, i + 1, IntCellValue(sorted[i].value));
    }

    return excel;
  }
}
