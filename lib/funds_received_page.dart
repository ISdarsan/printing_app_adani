import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'theme.dart';
import 'expense_detail_page.dart';

class FundsReceivedPage extends StatefulWidget {
  final bool isAdmin;
  const FundsReceivedPage({super.key, this.isAdmin = false});

  @override
  State<FundsReceivedPage> createState() => _FundsReceivedPageState();
}

class _FundsReceivedPageState extends State<FundsReceivedPage> {
  final _fundController = TextEditingController();
  bool _isUpdating = false;
  DateTime _selectedMonth = DateTime.now();

  String get _monthId => DateFormat('yyyy-MM').format(_selectedMonth);
  String get _monthLabel => DateFormat('MMMM yyyy').format(_selectedMonth);

  Stream<DocumentSnapshot> get _fundStream => FirebaseFirestore.instance
      .collection('monthlyFunds')
      .doc(_monthId)
      .snapshots();

  Stream<QuerySnapshot> get _monthExpensesStream {
    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);
    return FirebaseFirestore.instance
        .collection('expenses')
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThanOrEqualTo: end)
        .snapshots();
  }

  Future<void> _updateFund() async {
    final amount = double.tryParse(_fundController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('Please enter a valid amount', style: GoogleFonts.poppins()),
        backgroundColor: AppColors.accentRed,
      ));
      return;
    }
    setState(() => _isUpdating = true);
    try {
      await FirebaseFirestore.instance
          .collection('monthlyFunds')
          .doc(_monthId)
          .set({
        'fundAmount': amount,
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.email ?? 'Admin',
        'monthLabel': _monthLabel,
      });
      _fundController.clear();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Fund for $_monthLabel updated!',
              style: GoogleFonts.poppins()),
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

  void _showUpdateDialog(double currentAmount) {
    _fundController.text =
        currentAmount > 0 ? currentAmount.toStringAsFixed(0) : '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Set Fund - $_monthLabel',
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
            onPressed: _isUpdating ? null : _updateFund,
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
    );
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + offset);
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
        title: widget.isAdmin ? 'Canteen Cashflow Control' : 'Monthly Budget & Expenses',
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
                  icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
                  onPressed: () => _changeMonth(-1),
                ),
                const SizedBox(width: 8),
                Text(
                  _monthLabel,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),

          // Scrollable Budget Details
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: _fundStream,
              builder: (context, fundSnap) {
                double allocatedFund = 0;
                String lastUpdated = 'Not set yet';
                if (fundSnap.hasData && fundSnap.data!.exists) {
                  final d = fundSnap.data!.data() as Map<String, dynamic>;
                  allocatedFund = (d['fundAmount'] as num?)?.toDouble() ?? 0;
                  if (d['lastUpdated'] != null) {
                    lastUpdated =
                        'Updated ${DateFormat('dd MMM, hh:mm a').format((d['lastUpdated'] as Timestamp).toDate())}';
                  }
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _monthExpensesStream,
                  builder: (context, expensesSnap) {
                    double totalSpent = 0;
                    List<QueryDocumentSnapshot> currentExpenses = [];
                    if (expensesSnap.hasData) {
                      currentExpenses = expensesSnap.data!.docs;
                      for (var doc in currentExpenses) {
                        totalSpent +=
                            ((doc.data() as Map<String, dynamic>)['amount'] ?? 0.0)
                                as num;
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
                              child: Container(
                                padding: const EdgeInsets.all(22),
                                decoration: gradientCard(
                                    gradient: AppGradients.blueAccent, radius: 24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      const Icon(Icons.account_balance_wallet_rounded,
                                          color: Colors.white, size: 24),
                                      const SizedBox(width: 8),
                                      Text('Monthly Budget Console',
                                          style: GoogleFonts.poppins(
                                              color: Colors.white70,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      if (widget.isAdmin)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                              color: Colors.white24,
                                              borderRadius: BorderRadius.circular(20)),
                                          child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.edit_rounded,
                                                    color: Colors.white, size: 12),
                                                const SizedBox(width: 4),
                                                Text('Edit',
                                                    style: GoogleFonts.poppins(
                                                        color: Colors.white,
                                                        fontSize: 11)),
                                              ]),
                                        ),
                                    ]),
                                    const SizedBox(height: 12),
                                    Text(_monthLabel,
                                        style: GoogleFonts.poppins(
                                            color: Colors.white70, fontSize: 12)),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Allocated Fund',
                                                style: GoogleFonts.poppins(
                                                    color: Colors.white60,
                                                    fontSize: 11)),
                                            const SizedBox(height: 2),
                                            Text(allocatedStr,
                                                style: GoogleFonts.poppins(
                                                    color: Colors.white,
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w800)),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Text('Total Spent',
                                                style: GoogleFonts.poppins(
                                                    color: Colors.white60,
                                                    fontSize: 11)),
                                            const SizedBox(height: 2),
                                            Text(spentStr,
                                                style: GoogleFonts.poppins(
                                                    color: Colors.white,
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w800)),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text('Available Balance',
                                                style: GoogleFonts.poppins(
                                                    color: Colors.white60,
                                                    fontSize: 11)),
                                            const SizedBox(height: 2),
                                            Text(availableStr,
                                                style: GoogleFonts.poppins(
                                                    color: isNegative
                                                        ? AppColors.accentRed
                                                        : AppColors.accentGreen,
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w800)),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: Colors.black26,
                                          borderRadius: BorderRadius.circular(20)),
                                      child: Text(lastUpdated,
                                          style: GoogleFonts.poppins(
                                              fontSize: 10, color: Colors.white70)),
                                    ),
                                  ],
                                ),
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
                                style: GoogleFonts.poppins(
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
                                final desc = d['description'] ?? 'No Description';
                                final ts = d['timestamp'] as Timestamp?;
                                final dateStr = ts != null
                                    ? DateFormat('dd MMM, hh:mm a')
                                        .format(ts.toDate())
                                    : '-';

                                return Container(
                                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                  decoration: glassCard(radius: 14),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 4),
                                    title: Text(desc,
                                        style: GoogleFonts.poppins(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                    subtitle: Text(dateStr,
                                        style: GoogleFonts.poppins(
                                            color: AppColors.textSecondary,
                                            fontSize: 11)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '-₹${amount.toStringAsFixed(0)}',
                                          style: GoogleFonts.poppins(
                                              color: AppColors.accentRed,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14),
                                        ),
                                        const SizedBox(width: 6),
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
