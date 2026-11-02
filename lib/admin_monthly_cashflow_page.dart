import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'theme.dart';
import 'state_views.dart';
import 'stream_cache.dart';
import 'business_time.dart';
import 'expense_detail_page.dart';

class AdminMonthlyCashflowPage extends StatefulWidget {
  const AdminMonthlyCashflowPage({super.key});

  @override
  State<AdminMonthlyCashflowPage> createState() =>
      _AdminMonthlyCashflowPageState();
}

class _AdminMonthlyCashflowPageState extends State<AdminMonthlyCashflowPage> {
  final StreamCache _streams = StreamCache();
  Stream<T> _cached<T>(String name, Stream<T> Function() make, String sig) =>
      _streams.get<T>(name, make, signature: sig);

  final _amountController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _saveMonthlyFund() async {
    if (_amountController.text.isEmpty) {
      _showSnackBar('Please enter an amount.', AppColors.accentRed);
      return;
    }
    final double? amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      _showSnackBar('Please enter a valid amount.', AppColors.accentRed);
      return;
    }
    setState(() => _isLoading = true);

    final String monthId = BusinessTime.monthKey(DateTime.now());
    try {
      await FirebaseFirestore.instance
          .collection('monthlyFunds')
          .doc(monthId)
          .set({
        'fundAmount': amount,
        'lastUpdated': Timestamp.now(),
        'monthYear': monthId,
      }, SetOptions(merge: true));

      _amountController.clear();
      _showSnackBar('Monthly fund saved', const Color(0xFF1B4332));
    } catch (e) {
      _showSnackBar('Failed to save the fund. ${friendlyErrorMessage(e, action: 'saving')}', AppColors.accentRed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Stream<DocumentSnapshot> _getMonthlyFundStream() {
    final String monthId = BusinessTime.monthKey(DateTime.now());
    return FirebaseFirestore.instance
        .collection('monthlyFunds')
        .doc(monthId)
        .snapshots();
  }

  Stream<QuerySnapshot> _getExpensesStream() {
    final month = BusinessTime.monthRange(DateTime.now());

    return FirebaseFirestore.instance
        .collection('expenses')
        .where('timestamp', isGreaterThanOrEqualTo: month.start)
        .where('timestamp', isLessThan: month.end)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message, style: AppText.style()),
          backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Monthly Cash Flow'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Enter Fund Card ───────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: glassCard(radius: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined,
                          color: AppColors.accentBlue, size: 20),
                      const SizedBox(width: 8),
                      sectionTitle('Set Monthly Fund'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppText.style(
                        color: AppColors.textPrimary, fontSize: 14),
                    decoration: darkInput(
                      label: 'Amount (e.g., 50000)',
                      prefixIcon: Icons.currency_rupee,
                    ),
                  ),
                  const SizedBox(height: 16),
                  buildGradientButton(
                    label: 'Save Fund',
                    icon: Icons.save_rounded,
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _saveMonthlyFund,
                    height: 50,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Live Summary Card ─────────────────────
            StreamBuilder<DocumentSnapshot>(
              stream: _cached('fund', _getMonthlyFundStream,
                  BusinessTime.monthKey(DateTime.now())),
              builder: (context, fundSnapshot) {
                if (fundSnapshot.hasError) {
                  return AppErrorState(
                      inline: true,
                      error: fundSnapshot.error,
                      onRetry: () => setState(_streams.reset));
                }
                double totalFund = 0.0;
                if (fundSnapshot.hasData && fundSnapshot.data!.exists) {
                  var fundData =
                      fundSnapshot.data!.data() as Map<String, dynamic>;
                  if (fundData.containsKey('fundAmount')) {
                    totalFund = (fundData['fundAmount'] as num).toDouble();
                  }
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _cached('expensesA', _getExpensesStream,
                      BusinessTime.monthKey(DateTime.now())),
                  builder: (context, expenseSnapshot) {
                    if (expenseSnapshot.hasError) {
                      return AppErrorState(
                          inline: true,
                          error: expenseSnapshot.error,
                          onRetry: () => setState(_streams.reset));
                    }
                    double totalSpent = 0.0;
                    if (expenseSnapshot.hasData) {
                      for (var doc in expenseSnapshot.data!.docs) {
                        var data = doc.data() as Map<String, dynamic>;
                        if (data.containsKey('amount')) {
                          totalSpent += (data['amount'] as num).toDouble();
                        }
                      }
                    }

                    double remainingBalance = totalFund - totalSpent;
                    bool isDeficit = remainingBalance < 0;

                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: gradientCard(
                          gradient: AppGradients.blueAccent, radius: 20),
                      child: Column(
                        children: [
                          _buildSummaryRow(
                              'Total Fund:', totalFund, Colors.white70, 16),
                          const SizedBox(height: 12),
                          _buildSummaryRow(
                              'Expenditure:', totalSpent, Colors.white70, 16),
                          const Divider(color: Colors.white30, height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Balance',
                                  style: AppText.style(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                              Text(
                                '₹${remainingBalance.toStringAsFixed(2)}',
                                style: AppText.style(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: isDeficit
                                      ? AppColors.accentOrange
                                      : Colors.white,
                                ),
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
            const SizedBox(height: 24),

            // ── Live Expense Log ──────────────────────
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined,
                    color: AppColors.textSecondary, size: 18),
                const SizedBox(width: 8),
                sectionTitle('Live Expense Log (This Month)'),
              ],
            ),
            const SizedBox(height: 12),
            _buildExpenseList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
      String label, double amount, Color color, double fontSize) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.style(fontSize: 14, color: color)),
        Text('₹${amount.toStringAsFixed(2)}',
            style: AppText.style(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ],
    );
  }

  Widget _buildExpenseList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _cached('expensesB', _getExpensesStream,
          BusinessTime.monthKey(DateTime.now())),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
              inline: true,
              error: snapshot.error,
              onRetry: () => setState(_streams.reset));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.gradBlue));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: [
                  const Icon(Icons.receipt_outlined,
                      size: 40, color: AppColors.textHint),
                  const SizedBox(height: 10),
                  Text('No expenses logged for this month.',
                      style: AppText.style(
                          color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            var data = doc.data() as Map<String, dynamic>;

            final double amount = (data['amount'] as num).toDouble();
            final String description = data['description'] ?? 'No description';
            final Timestamp timestamp = data['timestamp'] ?? Timestamp.now();
            final String dateTime =
                DateFormat('dd MMM, hh:mm a').format(timestamp.toDate());

            return GestureDetector(
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            ExpenseDetailPage(expenseDoc: doc)));
              },
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 5),
                decoration: glassCard(radius: 14),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.payment,
                        color: AppColors.accentOrange, size: 20),
                  ),
                  title: Text(description,
                      style: AppText.style(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  subtitle: Text(dateTime,
                      style: AppText.style(
                          color: AppColors.textSecondary, fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('₹${amount.toStringAsFixed(0)}',
                          style: AppText.style(
                              color: AppColors.accentRed,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right,
                          size: 16, color: AppColors.textHint),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
