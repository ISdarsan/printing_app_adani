import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'daily_sales_report_page.dart'; // We will pass the date to this page

// This is a helper class to hold our grouped sales data
class DailySaleSummary {
  final DateTime date;
  final double total;
  DailySaleSummary({required this.date, required this.total});
}

class MonthlySalesBreakdownPage extends StatefulWidget {
  const MonthlySalesBreakdownPage({super.key});

  @override
  State<MonthlySalesBreakdownPage> createState() =>
      _MonthlySalesBreakdownPageState();
}

class _MonthlySalesBreakdownPageState extends State<MonthlySalesBreakdownPage> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // Function to show the month/year picker
  Future<void> _selectMonth(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      // A more advanced picker would only show months
    );
    if (picked != null &&
        (picked.month != _selectedMonth.month ||
            picked.year != _selectedMonth.year)) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
      });
    }
  }

  // This is the core logic. Fetch all bills for the month,
  // then group them by day and sum their totals.
  Stream<List<DailySaleSummary>> _getDailyBreakdown() {
    DateTime startOfMonth =
    DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    DateTime endOfMonth =
    DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);

    return FirebaseFirestore.instance
        .collection('bills') // Make sure this matches your collection name
        .where('timestamp', isGreaterThanOrEqualTo: startOfMonth)
        .where('timestamp', isLessThanOrEqualTo: endOfMonth)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      // Grouping logic happens here
      Map<String, double> dailyTotals = {};
      Map<String, DateTime> dailyDates = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        // Check if 'totalAmount' exists and is a number
        if (data.containsKey('totalAmount') && data['totalAmount'] is num) {
          final total = (data['totalAmount'] as num).toDouble();

          // Check if 'timestamp' exists and is a Timestamp
          if (data.containsKey('timestamp') && data['timestamp'] is Timestamp) {
            final timestamp = (data['timestamp'] as Timestamp).toDate();

            // Use 'yyyy-MM-dd' as a unique key for grouping
            final dayString = DateFormat('yyyy-MM-dd').format(timestamp);

            // Store the full date object to pass later
            dailyDates.putIfAbsent(dayString, () => timestamp);

            // Add to the total for that day
            dailyTotals.update(dayString, (value) => value + total,
                ifAbsent: () => total);
          }
        }
      }

      // Convert the grouped map into a list of objects
      return dailyTotals.entries.map((entry) {
        return DailySaleSummary(
          date: dailyDates[entry.key]!,
          total: entry.value,
        );
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String monthName = DateFormat('MMMM yyyy').format(_selectedMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Monthly Sales Breakdown"),
        backgroundColor: theme.primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          // --- MONTH PICKER UI ---
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
                      _selectedMonth = DateTime(
                          _selectedMonth.year, _selectedMonth.month - 1);
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
                      _selectedMonth = DateTime(
                          _selectedMonth.year, _selectedMonth.month + 1);
                    });
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // --- DAILY TOTALS LIST ---
          Expanded(
            child: StreamBuilder<List<DailySaleSummary>>(
              stream: _getDailyBreakdown(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text(
                      "No sales found for this month.",
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  );
                }

                final dailySales = snapshot.data!;

                return ListView.builder(
                  itemCount: dailySales.length,
                  itemBuilder: (context, index) {
                    final day = dailySales[index];
                    String formattedDate =
                    DateFormat('MMMM dd, yyyy').format(day.date);
                    String formattedTotal =
                        "₹ ${day.total.toStringAsFixed(2)}";

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.primaryColor.withOpacity(0.1),
                          foregroundColor: theme.primaryColor,
                          child: Text(DateFormat('d').format(day.date)),
                        ),
                        title: Text(
                          formattedDate,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        trailing: Text(
                          formattedTotal,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.green,
                          ),
                        ),
                        onTap: () {
                          // This is the key: navigate to the daily report
                          // and pass the specific date to it.
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DailySalesReportPage(
                                selectedDate: day.date, // Pass the date
                              ),
                            ),
                          );
                        },
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
