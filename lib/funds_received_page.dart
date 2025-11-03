import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Import for date formatting

class FundsReceivedPage extends StatefulWidget {
  const FundsReceivedPage({super.key});

  @override
  State<FundsReceivedPage> createState() => _FundsReceivedPageState();
}

class _FundsReceivedPageState extends State<FundsReceivedPage> {
  // 1. State variable to track the selected month
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // 2. Function to show the month/year picker
  Future<void> _selectMonth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      // Optional: You can customize this to be a month-only picker
      // For simplicity, we use the standard date picker and just use its month/year
    );
    if (picked != null && (picked.month != _selectedMonth.month || picked.year != _selectedMonth.year)) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
      });
    }
  }

  // 3. Helper function to get the start and end of the selected month
  (DateTime, DateTime) _getMonthRange() {
    final DateTime startOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final DateTime endOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59); // Gets last day, 23:59:59
    return (startOfMonth, endOfMonth);
  }

  // 4. Stream to fetch total funds received for the month
  Stream<double> _getTotalReceived() {
    final (start, end) = _getMonthRange();

    return FirebaseFirestore.instance
        .collection('fund_transactions')
        .where('type', isEqualTo: 'credit')
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThanOrEqualTo: end)
        .snapshots()
        .map((snapshot) {
      double total = 0.0;
      for (var doc in snapshot.docs) {
        total += (doc.data()['amount'] as num).toDouble();
      }
      return total;
    });
  }

  // 5. Stream to fetch total expenses for the month
  Stream<double> _getTotalExpenses() {
    final (start, end) = _getMonthRange();

    return FirebaseFirestore.instance
        .collection('expenses')
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThanOrEqualTo: end)
        .snapshots()
        .map((snapshot) {
      double total = 0.0;
      for (var doc in snapshot.docs) {
        total += (doc.data()['amount'] as num).toDouble();
      }
      return total;
    });
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String monthName = DateFormat('MMMM yyyy').format(_selectedMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Monthly Cashflow Report"),
        backgroundColor: theme.primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          // --- 6. MONTH PICKER UI ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                    });
                  },
                ),
                TextButton(
                  onPressed: () => _selectMonth(context),
                  child: Text(
                    monthName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                    });
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // --- 7. SUMMARY CARDS ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: StreamBuilder<double>(
              stream: _getTotalReceived(),
              builder: (context, receivedSnapshot) {
                return StreamBuilder<double>(
                  stream: _getTotalExpenses(),
                  builder: (context, expensesSnapshot) {

                    if (receivedSnapshot.connectionState == ConnectionState.waiting ||
                        expensesSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final double totalReceived = receivedSnapshot.data ?? 0.0;
                    final double totalExpenses = expensesSnapshot.data ?? 0.0;
                    final double balance = totalReceived - totalExpenses;

                    return Column(
                      children: [
                        _buildSummaryCard(
                          title: "Total Funds Received",
                          amount: totalReceived,
                          color: Colors.green,
                        ),
                        const SizedBox(height: 12),
                        _buildSummaryCard(
                          title: "Total Expenses",
                          amount: totalExpenses,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 12),
                        _buildSummaryCard(
                          title: "Balance for $monthName",
                          amount: balance,
                          color: balance >= 0 ? Colors.blue : Colors.orange,
                          isBalance: true,
                        ),
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

  // Helper widget for the summary cards
  Widget _buildSummaryCard({
    required String title,
    required double amount,
    required Color color,
    bool isBalance = false,
  }) {
    return Card(
      elevation: 4,
      color: isBalance ? color : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: isBalance ? Colors.white : Colors.black87,
              ),
            ),
            Text(
              "₹ ${amount.toStringAsFixed(2)}",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isBalance ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}