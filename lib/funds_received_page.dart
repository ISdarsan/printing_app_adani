import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'theme.dart';
import 'stream_cache.dart';
import 'state_views.dart';
import 'expense_detail_page.dart';
import 'canteen_provider.dart';
import 'business_time.dart';
import 'fund_budget.dart';

class FundsReceivedPage extends StatefulWidget {
  final bool isAdmin;
  const FundsReceivedPage({super.key, this.isAdmin = false});

  @override
  State<FundsReceivedPage> createState() => _FundsReceivedPageState();
}

class _FundsReceivedPageState extends State<FundsReceivedPage> {
  final _fundController = TextEditingController();
  bool _isUpdating = false;
  // Only year/month are used; initialised from the business calendar (IST).
  DateTime _selectedMonth = BusinessTime.wallClock(DateTime.now());

  final StreamCache _streams = StreamCache();
  Stream<T> _cached<T>(String name, Stream<T> Function() make) =>
      _streams.get<T>(name, make,
          signature: '${CanteenProvider.selectedCanteenId}|$_monthId');

  String get _monthId => DateFormat('yyyy-MM').format(_selectedMonth);
  String get _monthLabel => DateFormat('MMMM yyyy').format(_selectedMonth);

  /// Budgets are per canteen: this canteen's document for the shown month.
  String get _fundDocId =>
      monthlyFundDocId(CanteenProvider.selectedCanteenId, _monthId);

  Stream<DocumentSnapshot> get _fundStream => FirebaseFirestore.instance
      .collection('monthlyFunds')
      .doc(_fundDocId)
      .snapshots();

  Stream<QuerySnapshot> get _monthExpensesStream {
    final month = BusinessTime.monthRangeForMonth(
        _selectedMonth.year, _selectedMonth.month);
    // Branch-scoped for cashiers; index: expenses(canteenId, timestamp).
    return CanteenProvider.scopeQuery(
            FirebaseFirestore.instance.collection('expenses'))
        .where('timestamp', isGreaterThanOrEqualTo: month.start)
        .where('timestamp', isLessThan: month.end)
        .snapshots();
  }

  Future<void> _updateFund() async {
    final amount = double.tryParse(_fundController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a valid amount', style: AppText.style()),
        backgroundColor: AppColors.accentRed,
      ));
      return;
    }
    setState(() => _isUpdating = true);
    try {
      await FirebaseFirestore.instance
          .collection('monthlyFunds')
          .doc(_fundDocId)
          .set({
        'canteenId': CanteenProvider.selectedCanteenId,
        'canteenName': CanteenProvider.selectedCanteenName,
        'monthYear': _monthId,
        'fundAmount': amount,
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.email ?? 'Admin',
        'monthLabel': _monthLabel,
      });
      _fundController.clear();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Budget for $_monthLabel updated!', style: AppText.style()),
          backgroundColor: const Color(0xFF1B4332),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save the fund. ${friendlyErrorMessage(e, action: 'saving')}', style: AppText.style()),
          backgroundColor: AppColors.accentRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _showUpdateDialog(double currentAmount) {
    _fundController.text =
        currentAmount > 0 ? currentAmount.toStringAsFixed(0) : '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Set Budget - ${CanteenProvider.selectedCanteenName} - $_monthLabel',
            style: AppText.style(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter the monthly budget for this canteen.',
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
            onPressed: _isUpdating ? null : _updateFund,
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
    );
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + offset);
    });
  }

  @override
  void dispose() {
    _fundController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(
        title: widget.isAdmin
            ? 'Canteen Cashflow Control'
            : 'Monthly Budget & Expenses',
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Month Selector Header Control
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: AppColors.bgCard,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () => _changeMonth(-1),
                ),
                const SizedBox(width: 8),
                Text(
                  _monthLabel,
                  style: AppText.style(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),

          // Scrollable Budget Details
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: _cached('fund', () => _fundStream),
              builder: (context, fundSnap) {
                if (fundSnap.hasError) {
                  return AppErrorState(
                      error: fundSnap.error,
                      onRetry: () => setState(_streams.reset));
                }
                double allocatedFund = 0;
                String lastUpdated = widget.isAdmin
                    ? 'No budget set for this canteen yet'
                    : 'No budget set for this canteen yet. Ask the admin.';
                if (fundSnap.hasData && fundSnap.data!.exists) {
                  final d = fundSnap.data!.data() as Map<String, dynamic>;
                  allocatedFund = (d['fundAmount'] as num?)?.toDouble() ?? 0;
                  if (d['lastUpdated'] != null) {
                    lastUpdated =
                        'Updated ${DateFormat('dd MMM, hh:mm a').format((d['lastUpdated'] as Timestamp).toDate())}';
                  }
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _cached('expenses', () => _monthExpensesStream),
                  builder: (context, expensesSnap) {
                    if (expensesSnap.hasError) {
                      return AppErrorState(
                          error: expensesSnap.error,
                          onRetry: () => setState(_streams.reset));
                    }
                    double totalSpent = 0;
                    List<QueryDocumentSnapshot> currentExpenses = [];
                    if (expensesSnap.hasData) {
                      currentExpenses = expensesSnap.data!.docs.where((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        return CanteenProvider.matchesSelectedCanteen(d);
                      }).toList();
                      for (var doc in currentExpenses) {
                        totalSpent +=
                            ((doc.data() as Map<String, dynamic>)['amount'] ??
                                0.0) as num;
                      }
                    }

                    double availableFund = allocatedFund - totalSpent;
                    final isNegative = availableFund < 0;

                    final allocatedStr =
                        '₹${NumberFormat('#,##,###').format(allocatedFund)}';
                    final availableStr =
                        '₹${NumberFormat('#,##,###').format(availableFund)}';
                    final spentStr =
                        '₹${NumberFormat('#,##,###').format(totalSpent)}';

                    return CustomScrollView(
                      slivers: [
                        // Budget Summary Card
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: GestureDetector(
                              onTap: widget.isAdmin
                                  ? () => _showUpdateDialog(allocatedFund)
                                  : null,
                              child: FundSummaryCard(
                                isAdmin: widget.isAdmin,
                                title: widget.isAdmin
                                    ? 'Monthly Budget Console'
                                    : 'Monthly Budget - ${CanteenProvider.selectedCanteenName}',
                                monthLabel: _monthLabel,
                                allocatedStr: allocatedStr,
                                spentStr: spentStr,
                                availableStr: availableStr,
                                isNegative: isNegative,
                                lastUpdated: lastUpdated,
                              ),
                            ),
                          ),
                        ),

                        // Section Title: Expenses This Month
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: sectionTitle('Expenses for $_monthLabel'),
                          ),
                        ),

                        // List of current month's expenses
                        if (currentExpenses.isEmpty)
                          SliverToBoxAdapter(
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              padding: const EdgeInsets.all(20),
                              decoration: glassCard(radius: 16),
                              alignment: Alignment.center,
                              child: Text(
                                'No expenses logged for this month',
                                style: AppText.style(
                                    color: AppColors.textHint, fontSize: 12),
                              ),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                final doc = currentExpenses[i];
                                final d = doc.data() as Map<String, dynamic>;
                                final amount = (d['amount'] ?? 0.0) as num;
                                final desc =
                                    d['description'] ?? 'No Description';
                                final ts = d['timestamp'] as Timestamp?;
                                final dateStr = ts != null
                                    ? DateFormat('dd MMM, hh:mm a')
                                        .format(ts.toDate())
                                    : '-';

                                return Container(
                                  margin:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                  decoration: glassCard(radius: 14),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 4),
                                    title: Text(desc,
                                        style: AppText.style(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                    subtitle: Text(dateStr,
                                        style: AppText.style(
                                            color: AppColors.textSecondary,
                                            fontSize: 11)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '-₹${amount.toStringAsFixed(0)}',
                                          style: AppText.style(
                                              color: AppColors.accentRed,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(Icons.chevron_right,
                                            size: 14,
                                            color: AppColors.textHint),
                                      ],
                                    ),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            ExpenseDetailPage(expenseDoc: doc),
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: currentExpenses.length,
                            ),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


/// The blue fund summary card. Public (and free of Firestore) so its layout
/// can be tested at small screen sizes and large text.
class FundSummaryCard extends StatelessWidget {
  final bool isAdmin;
  final String title;
  final String monthLabel;
  final String allocatedStr;
  final String spentStr;
  final String availableStr;
  final bool isNegative;
  final String lastUpdated;

  const FundSummaryCard({
    super.key,
    required this.isAdmin,
    required this.title,
    required this.monthLabel,
    required this.allocatedStr,
    required this.spentStr,
    required this.availableStr,
    required this.isNegative,
    required this.lastUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: gradientCard(
          gradient: AppGradients.blueAccent,
          radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: 24),
            const SizedBox(width: 8),
            Flexible(
              child:
            Text(title,
                style: AppText.style(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            ),
            const Spacer(),
            if (isAdmin)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius:
                        BorderRadius.circular(20)),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit_rounded,
                          color: Colors.white,
                          size: 12),
                      const SizedBox(width: 4),
                      Text('Edit',
                          style: AppText.style(
                              color: Colors.white,
                              fontSize: 11)),
                    ]),
              ),
          ]),
          const SizedBox(height: 12),
          Text(monthLabel,
              style: AppText.style(
                  color: Colors.white70,
                  fontSize: 12)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text('Allocated Budget',
                      textAlign: TextAlign.start,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.style(
                          color: Colors.white60,
                          fontSize: 11)),
                  const SizedBox(height: 2),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(allocatedStr,
                      style: AppText.style(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight:
                              FontWeight.w800))),
                ],
              ),
              ),
              Expanded(
                child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.center,
                children: [
                  Text('Total Spent',
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.style(
                          color: Colors.white60,
                          fontSize: 11)),
                  const SizedBox(height: 2),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(spentStr,
                      style: AppText.style(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight:
                              FontWeight.w800))),
                ],
              ),
              ),
              Expanded(
                child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.end,
                children: [
                  Text('Available Balance',
                      textAlign: TextAlign.end,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.style(
                          color: Colors.white60,
                          fontSize: 11)),
                  const SizedBox(height: 2),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(availableStr,
                      style: AppText.style(
                          color: isNegative
                              ? AppColors.accentRed
                              : AppColors.accentGreen,
                          fontSize: 20,
                          fontWeight:
                              FontWeight.w800))),
                ],
              ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius:
                    BorderRadius.circular(20)),
            child: Text(lastUpdated,
                style: AppText.style(
                    fontSize: 10,
                    color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
