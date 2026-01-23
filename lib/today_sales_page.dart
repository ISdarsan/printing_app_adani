import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class TodaySalesPage extends StatelessWidget {
  const TodaySalesPage({super.key});

  // Helper function to get the start and end of today
  (DateTime, DateTime) _getTodayRange() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return (startOfToday, endOfToday);
  }

  // Stream to fetch total sales for today
  Stream<double> _getTotalSales() {
    final (start, end) = _getTodayRange();

    // ASSUMPTION: You have a 'bills' collection where each doc has:
    // - 'totalAmount': a number (double or int)
    // - 'timestamp': a Firebase Timestamp

    return FirebaseFirestore.instance
        .collection('bills')
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThanOrEqualTo: end)
        .snapshots()
        .map((snapshot) {
      double total = 0.0;
      for (var doc in snapshot.docs) {
        total += (doc.data()['totalAmount'] as num).toDouble();
      }
      return total;
    });
  }

  // Stream to fetch the list of bills for today
  Stream<QuerySnapshot> _getBillsStream() {
    final (start, end) = _getTodayRange();

    return FirebaseFirestore.instance
        .collection('bills')
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThanOrEqualTo: end)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String todayDate = DateFormat('MMMM dd, yyyy').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Sales"),
        backgroundColor: theme.primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- 1. Total Sales Summary Card ---
          StreamBuilder<double>(
            stream: _getTotalSales(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}"));
              }

              final double totalSales = snapshot.data ?? 0.0;

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0066B3), Color(0xFF004A80)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todayDate,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "₹ ${totalSales.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      "Total Sales Today",
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // --- 2. List of Bills ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
            child: Text(
              "Recent Bills",
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold
              ),
            ),
          ),
          const Divider(indent: 16, endIndent: 16, height: 1),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getBillsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Text(
                        "No bills recorded yet for today.",
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final bills = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: bills.length,
                  itemBuilder: (context, index) {
                    final bill = bills[index].data() as Map<String, dynamic>;
                    final double amount = (bill['totalAmount'] as num).toDouble();
                    final DateTime time = (bill['timestamp'] as Timestamp).toDate();

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.primaryColorLight,
                          child: const Icon(Icons.receipt, color: Colors.black54),
                        ),
                        title: Text(
                          "Bill #${bills[index].id.substring(0, 6)}...", // Show partial doc ID
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          "Time: ${DateFormat.jm().format(time)}", // Format time e.g., 11:30 AM
                        ),
                        trailing: Text(
                          "₹ ${amount.toStringAsFixed(2)}",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
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