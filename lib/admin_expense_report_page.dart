import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'expense_detail_page.dart'; // <-- 1. IMPORT THE NEW PAGE

class AdminExpenseReportPage extends StatelessWidget {
  const AdminExpenseReportPage({super.key});

  final LinearGradient adaniGradient = const LinearGradient(
    colors: [
      Color(0xFF0066B3), // blue
      Color(0xFF6C3FB5), // purple
      Color(0xFFE91E63), // pink
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // This function fetches all expenses and groups them by month
  Stream<Map<String, List<QueryDocumentSnapshot>>> _getGroupedExpenses() {
    return FirebaseFirestore.instance
        .collection('expenses')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      Map<String, List<QueryDocumentSnapshot>> groupedExpenses = {};
      for (var doc in snapshot.docs) {
        DateTime date = (doc['timestamp'] as Timestamp).toDate();
        String monthKey = DateFormat('MMMM yyyy').format(date);
        if (!groupedExpenses.containsKey(monthKey)) {
          groupedExpenses[monthKey] = [];
        }
        groupedExpenses[monthKey]!.add(doc);
      }
      return groupedExpenses;
    });
  }

  // This function just calculates the total of ALL expenses
  Stream<double> _getTotalExpense() {
    return FirebaseFirestore.instance
        .collection('expenses')
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
            'Expense Report',
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
      body: Column(
        children: [
          // --- 1. TOTAL EXPENSE CARD (AT THE TOP) ---
          StreamBuilder<double>(
            stream: _getTotalExpense(),
            builder: (context, snapshot) {
              String total = "₹ 0.00";
              if (snapshot.hasData) {
                total = "₹ ${snapshot.data!.toStringAsFixed(2)}";
              }
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Canteen Expenditure',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.black54,
                      ),
                    ),
                    Text(
                      total,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // --- 2. LIST OF EXPENSES (MONTH BY MONTH) ---
          Expanded(
            child: StreamBuilder<Map<String, List<QueryDocumentSnapshot>>>(
              stream: _getGroupedExpenses(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text(
                      'No expenses logged yet.',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                final groupedExpenses = snapshot.data!;
                final months = groupedExpenses.keys.toList();

                return ListView.builder(
                  itemCount: months.length,
                  itemBuilder: (context, index) {
                    String month = months[index];
                    List<QueryDocumentSnapshot> expenses =
                    groupedExpenses[month]!;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        title: Text(
                          month,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text('${expenses.length} expenses'),
                        initiallyExpanded: index == 0,
                        children: expenses.map((doc) { // <-- 'doc' is the DocumentSnapshot
                          var data = doc.data() as Map<String, dynamic>;
                          var date = (data['timestamp'] as Timestamp).toDate();
                          var formattedDate =
                          DateFormat('dd MMM, hh:mm a').format(date);

                          return ListTile(
                            title: Text(
                              data['description'] ?? 'No Description',
                              style:
                              const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(formattedDate),
                            trailing: Text(
                              '₹ ${data['amount'].toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),

                            // --- THIS IS THE FIX ---
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ExpenseDetailPage(
                                    // Pass the whole document, not just the data
                                    expenseDoc: doc,
                                  ),
                                ),
                              );
                            },
                            // -------------------------
                          );
                        }).toList(),
                      ),
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