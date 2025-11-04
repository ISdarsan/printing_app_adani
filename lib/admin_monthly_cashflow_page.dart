import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
// We will create this page next
// import 'expense_bill_detail_page.dart';

class AdminMonthlyCashflowPage extends StatefulWidget {
  const AdminMonthlyCashflowPage({super.key});

  @override
  State<AdminMonthlyCashflowPage> createState() =>
      _AdminMonthlyCashflowPageState();
}

class _AdminMonthlyCashflowPageState extends State<AdminMonthlyCashflowPage> {
  final _amountController = TextEditingController();
  bool _isLoading = false;

  final LinearGradient adaniGradient = const LinearGradient(
    colors: [
      Color(0xFF0066B3), // blue
      Color(0xFF6C3FB5), // purple
      Color(0xFFE91E63), // pink
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Function to save the monthly fund
  Future<void> _saveMonthlyFund() async {
    if (_amountController.text.isEmpty) {
      _showSnackBar('Please enter an amount.', Colors.red);
      return;
    }
    final double? amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      _showSnackBar('Please enter a valid amount.', Colors.red);
      return;
    }
    setState(() {
      _isLoading = true;
    });

    final String monthId = DateFormat('yyyy-MM').format(DateTime.now());
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
      _showSnackBar('Monthly fund saved successfully!', Colors.green);
    } catch (e) {
      _showSnackBar('Failed to save fund: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Stream to get the monthly fund (what Admin entered)
  Stream<DocumentSnapshot> _getMonthlyFundStream() {
    final String monthId = DateFormat('yyyy-MM').format(DateTime.now());
    return FirebaseFirestore.instance
        .collection('monthlyFunds')
        .doc(monthId)
        .snapshots();
  }

  // Stream to get all expenses for this month
  Stream<QuerySnapshot> _getExpensesStream() {
    DateTime now = DateTime.now();
    DateTime startOfMonth = DateTime(now.year, now.month, 1);
    DateTime endOfMonth =
    DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    return FirebaseFirestore.instance
        .collection('expenses')
        .where('timestamp', isGreaterThanOrEqualTo: startOfMonth)
        .where('timestamp', isLessThanOrEqualTo: endOfMonth)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: AppBar(
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: Container(
            decoration: BoxDecoration(gradient: adaniGradient),
          ),
          title: const Text(
            'Monthly Cash Flow',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
          elevation: 3,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Card for Admin to enter the fund
            _buildEnterFundCard(),
            const SizedBox(height: 24),

            // 2. Live Summary Card (Fund, Spent, Balance)
            _buildSummaryCard(),
            const SizedBox(height: 24),

            // 3. Live list of all expenses
            const Text(
              'Live Expense Log (This Month)',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF003C8F), // Dark Blue
              ),
            ),
            const SizedBox(height: 8),
            _buildExpenseList(),
          ],
        ),
      ),
    );
  }

  // Card UI for entering the monthly fund
  Widget _buildEnterFundCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set Monthly Canteen Fund',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              decoration: _buildInputDecoration(
                labelText: 'Amount (e.g., 50000)',
                icon: Icons.currency_rupee,
              ),
            ),
            const SizedBox(height: 20),
            // Gradient Save Button
            GestureDetector(
              onTap: _isLoading ? null : _saveMonthlyFund,
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                    gradient: adaniGradient,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: adaniGradient.colors.last.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      )
                    ]),
                child: Center(
                  child: _isLoading
                      ? const CircularProgressIndicator(
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.white),
                  )
                      : const Text(
                    'Save Fund',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // "Cool" Summary Card
  Widget _buildSummaryCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _getMonthlyFundStream(),
      builder: (context, fundSnapshot) {
        double totalFund = 0.0;
        if (fundSnapshot.hasData && fundSnapshot.data!.exists) {
          var fundData = fundSnapshot.data!.data() as Map<String, dynamic>;
          if (fundData.containsKey('fundAmount')) {
            totalFund = (fundData['fundAmount'] as num).toDouble();
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _getExpensesStream(),
          builder: (context, expenseSnapshot) {
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

            return Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade700, Colors.blue.shade500],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      _buildSummaryRow('Total Fund Received:',
                          '₹${totalFund.toStringAsFixed(2)}', Colors.white, 22),
                      const SizedBox(height: 10),
                      _buildSummaryRow(
                          'Total Expenditure:',
                          '₹${totalSpent.toStringAsFixed(2)}',
                          Colors.white.withOpacity(0.9),
                          22),
                      const Divider(color: Colors.white54, height: 20),
                      _buildSummaryRow(
                          'Remaining Balance:',
                          '₹${remainingBalance.toStringAsFixed(2)}',
                          Colors.white,
                          26),
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

  Widget _buildSummaryRow(
      String label, String value, Color color, double fontSize) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: color.withOpacity(0.9),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // StreamBuilder to show the live list of expenses
  Widget _buildExpenseList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getExpensesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                'No expenses logged for this month yet.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          );
        }

        return Card(
          elevation: 2,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ListView.builder(
            itemCount: snapshot.data!.docs.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;

              final String amount = (data['amount'] as num).toStringAsFixed(2);
              final String description =
                  data['description'] ?? 'No description';
              final Timestamp timestamp =
                  data['timestamp'] ?? Timestamp.now();
              final String dateTime =
              DateFormat('dd MMM, hh:mm a').format(timestamp.toDate());
              // final bool hasBillImage = data.containsKey('billImageUrl') && data['billImageUrl'] != null;

              return ListTile(
                leading: const Icon(Icons.payment, color: Colors.redAccent),
                title: Text(
                  "₹$amount - $description",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(dateTime),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                onTap: () {
                  // TODO: Navigate to a new page to show data['billImageUrl']
                  // Navigator.push(context, MaterialPageRoute(builder: (context) =>
                  //   ExpenseBillDetailPage(expenseDoc: doc)
                  // ));
                },
              );
            },
          ),
        );
      },
    );
  }

  // Helper for text field styling
  InputDecoration _buildInputDecoration({
    required String labelText,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: labelText,
      filled: true,
      fillColor: Colors.grey[100],
      prefixIcon: Icon(icon, color: const Color(0xFF0066B3)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0066B3), width: 2),
      ),
    );
  }}
