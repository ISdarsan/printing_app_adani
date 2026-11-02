import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'theme.dart';
import 'stream_cache.dart';
import 'state_views.dart';
import 'business_time.dart';
import 'fund_budget.dart';
import 'expense_detail_page.dart';

/// Admin: monthly budgets and expenses.
///
/// Budgets are assigned PER CANTEEN. Pick a canteen to see and set its budget
/// for each month; "All canteens" shows the total of the budgets that have
/// been set against everything spent (budgets can only be edited per canteen).
class AdminExpenseReportPage extends StatefulWidget {
  const AdminExpenseReportPage({super.key});

  @override
  State<AdminExpenseReportPage> createState() => _AdminExpenseReportPageState();
}

class _CanteenOption {
  final String id;
  final String name;
  const _CanteenOption(this.id, this.name);
}

class _AdminExpenseReportPageState extends State<AdminExpenseReportPage> {
  static const _all = 'all';

  final StreamCache _streams = StreamCache();
  final _fundController = TextEditingController();
  bool _isUpdating = false;
  String _selected = _all;

  Future<void> _updateFund(String canteenId, String canteenName,
      String monthId, String monthLabel, double amount) async {
    setState(() => _isUpdating = true);
    try {
      await FirebaseFirestore.instance
          .collection('monthlyFunds')
          .doc(monthlyFundDocId(canteenId, monthId))
          .set({
        'canteenId': canteenId,
        'canteenName': canteenName,
        'monthYear': monthId,
        'fundAmount': amount,
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.email ?? 'Admin',
        'monthLabel': monthLabel,
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Budget for $canteenName, $monthLabel updated!',
              style: AppText.style()),
          backgroundColor: const Color(0xFF1B4332),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Could not save the budget. ${friendlyErrorMessage(e, action: 'saving')}',
              style: AppText.style()),
          backgroundColor: AppColors.accentRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _showUpdateDialog(_CanteenOption canteen, String monthId,
      String monthLabel, double currentAmount) {
    _fundController.text =
        currentAmount > 0 ? currentAmount.toStringAsFixed(0) : '';
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Set Budget - $monthLabel',
              style: AppText.style(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Monthly budget for ${canteen.name}.',
                  style: AppText.style(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: _fundController,
                keyboardType: TextInputType.number,
                style: AppText.style(color: AppColors.textPrimary),
                decoration: darkInput(
                    label: 'Amount (INR)', prefixIcon: Icons.currency_rupee),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: AppText.style(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gradBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isUpdating
                  ? null
                  : () {
                      final amount = double.tryParse(_fundController.text);
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Please enter a valid amount',
                              style: AppText.style()),
                          backgroundColor: AppColors.accentRed,
                        ));
                        return;
                      }
                      _updateFund(
                          canteen.id, canteen.name, monthId, monthLabel, amount);
                    },
              child: _isUpdating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text('Save',
                      style: AppText.style(
                          color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fundController.dispose();
    super.dispose();
  }

  /// "Main Canteen" plus every canteen in the database.
  List<_CanteenOption> _options(QuerySnapshot? canteens) {
    final out = <_CanteenOption>[const _CanteenOption('main', 'Main Canteen')];
    for (final doc in canteens?.docs ?? const <QueryDocumentSnapshot>[]) {
      if (doc.id == 'main') continue;
      final d = doc.data() as Map<String, dynamic>;
      final name = (d['name'] ?? doc.id).toString();
      out.add(_CanteenOption(doc.id, name));
    }
    return out;
  }

  Widget _selector(List<_CanteenOption> options) {
    final value = options.any((o) => o.id == _selected) ? _selected : _all;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: darkInputDecoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.bgCard,
          iconEnabledColor: AppColors.textSecondary,
          style: AppText.style(color: AppColors.textPrimary, fontSize: 14),
          items: [
            DropdownMenuItem(
                value: _all,
                child: Text('All canteens',
                    overflow: TextOverflow.ellipsis,
                    style: AppText.style(color: AppColors.textPrimary))),
            for (final o in options)
              DropdownMenuItem(
                  value: o.id,
                  child: Text(o.name,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.style(color: AppColors.textPrimary))),
          ],
          onChanged: (v) => setState(() => _selected = v ?? _all),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Monthly Budget & Expenses'),
      body: StreamBuilder<QuerySnapshot>(
        stream: _streams.get(
            'funds',
            () => FirebaseFirestore.instance
                .collection('monthlyFunds')
                .snapshots()),
        builder: (context, fundsSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: _streams.get(
                'expenses',
                () => FirebaseFirestore.instance
                    .collection('expenses')
                    .orderBy('timestamp', descending: true)
                    .snapshots()),
            builder: (context, expensesSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: _streams.get(
                    'canteens',
                    () => FirebaseFirestore.instance
                        .collection('canteens')
                        .snapshots()),
                builder: (context, canteensSnapshot) {
                  final error = fundsSnapshot.error ??
                      expensesSnapshot.error ??
                      canteensSnapshot.error;
                  if (error != null) {
                    return AppErrorState(
                        error: error,
                        onRetry: () => setState(_streams.reset));
                  }
                  if (fundsSnapshot.connectionState ==
                          ConnectionState.waiting ||
                      expensesSnapshot.connectionState ==
                          ConnectionState.waiting ||
                      canteensSnapshot.connectionState ==
                          ConnectionState.waiting) {
                    return const AppLoading();
                  }
                  return _content(fundsSnapshot.data, expensesSnapshot.data,
                      canteensSnapshot.data);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _content(QuerySnapshot? funds, QuerySnapshot? expenses,
      QuerySnapshot? canteens) {
    final options = _options(canteens);
    final selectedOption = options.cast<_CanteenOption?>().firstWhere(
        (o) => o!.id == _selected,
        orElse: () => null);
    final isAll = selectedOption == null;

    // 1. Budgets per month per canteen. Older documents without a canteen are
    //    the previous shared fund: not a budget for any canteen, so skipped.
    final budgets = <String, Map<String, double>>{}; // month -> canteen -> amount
    final monthLabels = <String, String>{};
    var legacy = 0;
    for (final doc in funds?.docs ?? const <QueryDocumentSnapshot>[]) {
      final d = doc.data() as Map<String, dynamic>;
      final canteenId = (d['canteenId'] ?? '').toString();
      final month = (d['monthYear'] ?? '').toString();
      if (canteenId.isEmpty || month.isEmpty) {
        legacy++;
        continue;
      }
      (budgets[month] ??= {})[canteenId] =
          (d['fundAmount'] as num?)?.toDouble() ?? 0.0;
      monthLabels[month] = (d['monthLabel'] ?? month).toString();
    }

    // 2. Expenses grouped by month (only the selected canteen when one is picked)
    final grouped = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in expenses?.docs ?? const <QueryDocumentSnapshot>[]) {
      final d = doc.data() as Map<String, dynamic>;
      final ts = d['timestamp'] as Timestamp?;
      if (ts == null) continue;
      if (!isAll && (d['canteenId'] ?? 'main').toString() != _selected) {
        continue;
      }
      (grouped[BusinessTime.monthKey(ts.toDate())] ??= []).add(doc);
    }

    // The current month is always shown, even with nothing logged yet.
    final currentMonthKey = BusinessTime.monthKey(DateTime.now());
    monthLabels.putIfAbsent(
        currentMonthKey, () => DateFormat('MMMM yyyy').format(DateTime.now()));
    final monthKeys = {...budgets.keys, ...grouped.keys, currentMonthKey}
        .toList()
      ..sort((a, b) => b.compareTo(a)); // newest first

    return Column(
      children: [
        _selector(options),
        if (isAll)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded,
                  size: 16, color: AppColors.accentBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Budgets are set per canteen. Choose a canteen above to set or change its monthly budget. '
                  '"All canteens" shows the totals only.',
                  style: AppText.style(
                      color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                ),
              ),
            ]),
          ),
        if (legacy > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              'Older shared budgets ($legacy) are no longer used. '
              'Set each canteen\'s budget below.',
              style: AppText.style(color: AppColors.textHint, fontSize: 11),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: monthKeys.length,
            itemBuilder: (context, index) {
              final monthKey = monthKeys[index];
              final label = monthLabels[monthKey] ??
                  DateFormat('MMMM yyyy')
                      .format(DateTime.parse('$monthKey-01'));
              final monthBudgets = budgets[monthKey] ?? const <String, double>{};
              final fund = isAll
                  ? monthBudgets.values.fold(0.0, (a, b) => a + b)
                  : (monthBudgets[_selected] ?? 0.0);
              final monthExpenses = grouped[monthKey] ?? [];

              var spentPaise = 0;
              for (final doc in monthExpenses) {
                final amount =
                    ((doc.data() as Map<String, dynamic>)['amount'] ?? 0) as num;
                spentPaise += (amount * 100).round();
              }
              final totalSpent = spentPaise / 100;
              final balance = ((fund * 100).round() - spentPaise) / 100;
              final isNegative = balance < 0;

              return _monthCard(
                context: context,
                monthKey: monthKey,
                label: label,
                fund: fund,
                totalSpent: totalSpent,
                balance: balance,
                isNegative: isNegative,
                expenses: monthExpenses,
                isAll: isAll,
                canteen: selectedOption,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _monthCard({
    required BuildContext context,
    required String monthKey,
    required String label,
    required double fund,
    required double totalSpent,
    required double balance,
    required bool isNegative,
    required List<QueryDocumentSnapshot> expenses,
    required bool isAll,
    required _CanteenOption? canteen,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: glassCard(radius: 18),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppColors.accentBlue,
          collapsedIconColor: AppColors.textSecondary,
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppText.style(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),
                    Text(
                      '${expenses.length} expenses logged',
                      style: AppText.style(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: isAll
                    ? 'Choose a canteen to set its budget'
                    : 'Set budget',
                icon: Icon(Icons.edit_note_rounded,
                    color: isAll ? AppColors.textHint : AppColors.accentBlue,
                    size: 22),
                onPressed: () {
                  if (isAll || canteen == null) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Choose a canteen above to set its monthly budget.',
                          style: AppText.style()),
                    ));
                    return;
                  }
                  _showUpdateDialog(canteen, monthKey, label, fund);
                },
              ),
            ],
          ),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppColors.bgInput.withValues(alpha: 0.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _summaryPill(isAll ? 'Budgets' : 'Budget', fund,
                      AppColors.accentBlue),
                  _summaryPill('Spent', totalSpent, AppColors.accentRed),
                  _summaryPill(
                    'Remaining',
                    balance,
                    isNegative ? AppColors.accentRed : AppColors.accentGreen,
                  ),
                ],
              ),
            ),
            if (expenses.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No expenses logged for this month.',
                  style: AppText.style(color: AppColors.textHint, fontSize: 12),
                ),
              )
            else
              ...expenses.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final date = (d['timestamp'] as Timestamp).toDate();
                final dateStr = DateFormat('dd MMM, hh:mm a').format(date);
                // an expense with a missing amount shows 0 instead of crashing the page
                final amt = ((d['amount'] ?? 0) as num).toDouble();

                return Container(
                  decoration: const BoxDecoration(
                    border:
                        Border(top: BorderSide(color: AppColors.bgDivider)),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                    title: Text(
                      d['description'] ?? 'No Description',
                      style: AppText.style(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 13),
                    ),
                    subtitle: Text(
                      dateStr,
                      style: AppText.style(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '₹${amt.toStringAsFixed(0)}',
                          style: AppText.style(
                              color: AppColors.accentRed,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right,
                            size: 14, color: AppColors.textHint),
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExpenseDetailPage(expenseDoc: doc),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _summaryPill(String title, double amount, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: AppText.style(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          '₹${amount.toStringAsFixed(0)}',
          style: AppText.style(
              color: color, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
