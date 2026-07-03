import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'theme.dart';
import 'expense_detail_page.dart';

class AdminExpenseReportPage extends StatefulWidget {
  const AdminExpenseReportPage({super.key});

  @override
  State<AdminExpenseReportPage> createState() => _AdminExpenseReportPageState();
}

class _AdminExpenseReportPageState extends State<AdminExpenseReportPage> {
  final _fundController = TextEditingController();
  bool _isUpdating = false;

  Future<void> _updateFund(String monthId, String monthLabel, double amount) async {
    setState(() => _isUpdating = true);
    try {
      await FirebaseFirestore.instance
          .collection('monthlyFunds')
          .doc(monthId)
          .set({
        'fundAmount': amount,
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.email ?? 'Admin',
        'monthLabel': monthLabel,
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Fund for $monthLabel updated!', style: GoogleFonts.poppins()),
          backgroundColor: const Color(0xFF1B4332),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: GoogleFonts.poppins()),
          backgroundColor: AppColors.accentRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _showUpdateDialog(String monthId, String monthLabel, double currentAmount) {
    _fundController.text = currentAmount > 0 ? currentAmount.toStringAsFixed(0) : '';
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Set Fund - $monthLabel',
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter the total fund allocated by management for this month.',
                  style: GoogleFonts.poppins(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: _fundController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.poppins(color: AppColors.textPrimary),
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
                  style: GoogleFonts.poppins(color: AppColors.textSecondary)),
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
                              style: GoogleFonts.poppins()),
                          backgroundColor: AppColors.accentRed,
                        ));
                        return;
                      }
                      _updateFund(monthId, monthLabel, amount);
                    },
              child: _isUpdating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text('Save',
                      style: GoogleFonts.poppins(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Monthly Cashflow & Expenses'),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('monthlyFunds').snapshots(),
        builder: (context, fundsSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('expenses')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, expensesSnapshot) {
              if (fundsSnapshot.connectionState == ConnectionState.waiting ||
                  expensesSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.gradBlue));
              }

              // 1. Process Monthly Funds
              final fundsData = fundsSnapshot.data?.docs ?? [];
              Map<String, double> fundsMap = {};
              Map<String, String> monthLabels = {};
              for (var doc in fundsData) {
                final d = doc.data() as Map<String, dynamic>;
                fundsMap[doc.id] = (d['fundAmount'] ?? 0.0).toDouble();
                monthLabels[doc.id] = d['monthLabel'] ?? doc.id;
              }

              // 2. Process Expenses
              final expenseData = expensesSnapshot.data?.docs ?? [];
              Map<String, List<QueryDocumentSnapshot>> groupedExpenses = {};
              for (var doc in expenseData) {
                final d = doc.data() as Map<String, dynamic>;
                final Timestamp? ts = d['timestamp'] as Timestamp?;
                if (ts == null) continue;
                final date = ts.toDate();
                final monthKey = DateFormat('yyyy-MM').format(date);
                if (!groupedExpenses.containsKey(monthKey)) {
                  groupedExpenses[monthKey] = [];
                }
                groupedExpenses[monthKey]!.add(doc);
              }

              // Ensure the current month is always present even if no expenses/funds are logged yet
              final currentMonthKey = DateFormat('yyyy-MM').format(DateTime.now());
              if (!fundsMap.containsKey(currentMonthKey)) {
                fundsMap[currentMonthKey] = 0.0;
                monthLabels[currentMonthKey] = DateFormat('MMMM yyyy').format(DateTime.now());
              }

              // Combine month keys
              final allMonthKeys = {...fundsMap.keys, ...groupedExpenses.keys}.toList();
              allMonthKeys.sort((a, b) => b.compareTo(a)); // Newest first

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: allMonthKeys.length,
                itemBuilder: (context, index) {
                  final monthKey = allMonthKeys[index];
                  final label = monthLabels[monthKey] ??
                      DateFormat('MMMM yyyy').format(DateTime.parse('$monthKey-01'));
                  final fund = fundsMap[monthKey] ?? 0.0;
                  final expenses = groupedExpenses[monthKey] ?? [];

                  final totalSpent = expenses.fold(
                      0.0,
                      (acc, doc) =>
                          acc + ((doc.data() as Map<String, dynamic>)['amount'] ?? 0.0).toDouble());
                  final balance = fund - totalSpent;
                  final isNegative = balance < 0;

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
                                    style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary),
                                  ),
                                  Text(
                                    '${expenses.length} expenses logged',
                                    style: GoogleFonts.poppins(
                                        color: AppColors.textSecondary, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_note_rounded,
                                  color: AppColors.accentBlue, size: 22),
                              onPressed: () => _showUpdateDialog(monthKey, label, fund),
                            ),
                          ],
                        ),
                        children: [
                          // Financial Summary Panel
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            color: AppColors.bgInput.withValues(alpha: 0.5),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _summaryPill('Fund', fund, AppColors.accentBlue),
                                _summaryPill('Spent', totalSpent, AppColors.accentRed),
                                _summaryPill(
                                  'Remaining',
                                  balance,
                                  isNegative ? AppColors.accentRed : AppColors.accentGreen,
                                ),
                              ],
                            ),
                          ),
                          // List of expenses
                          if (expenses.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'No expenses logged for this month.',
                                style: GoogleFonts.poppins(
                                    color: AppColors.textHint, fontSize: 12),
                              ),
                            )
                          else
                            ...expenses.map((doc) {
                              final d = doc.data() as Map<String, dynamic>;
                              final date = (d['timestamp'] as Timestamp).toDate();
                              final dateStr = DateFormat('dd MMM, hh:mm a').format(date);
                              final amt = (d['amount'] as num).toDouble();

                              return Container(
                                decoration: const BoxDecoration(
                                  border: Border(top: BorderSide(color: AppColors.bgDivider)),
                                ),
                                child: ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                                  title: Text(
                                    d['description'] ?? 'No Description',
                                    style: GoogleFonts.poppins(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    dateStr,
                                    style: GoogleFonts.poppins(
                                        color: AppColors.textSecondary, fontSize: 11),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '₹${amt.toStringAsFixed(0)}',
                                        style: GoogleFonts.poppins(
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
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _summaryPill(String title, double amount, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          '₹${amount.toStringAsFixed(0)}',
          style: GoogleFonts.poppins(color: color, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}