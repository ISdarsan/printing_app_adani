import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DailySalesReportPage extends StatefulWidget {
  // --- 1. ADD THIS CONSTRUCTOR ---
  // This allows us to pass in a date.
  final DateTime? selectedDate;
  const DailySalesReportPage({super.key, this.selectedDate});
  // -----------------------------

  @override
  State<DailySalesReportPage> createState() => _DailySalesReportPageState();
}

class _DailySalesReportPageState extends State<DailySalesReportPage> {
  // --- 2. MODIFY THIS VARIABLE ---
  late DateTime _selectedDate;
  // -----------------------------

  // --- 3. ADD INITSTATE ---
  @override
  void initState() {
    super.initState();
    // Use the date passed from the constructor, or default to today
    _selectedDate = widget.selectedDate ?? DateTime.now();
  }
  // ------------------------

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // Helper to get start/end of the day
  (DateTime, DateTime) _getDayRange(DateTime date) {
    final DateTime startOfDay =
    DateTime(date.year, date.month, date.day, 0, 0, 0);
    final DateTime endOfDay =
    DateTime(date.year, date.month, date.day, 23, 59, 59);
    return (startOfDay, endOfDay);
  }

  // Fetches aggregated stats: total, cash, upi
  Stream<Map<String, double>> _getAggregatedStats() {
    final (start, end) = _getDayRange(_selectedDate);

    return FirebaseFirestore.instance
        .collection('bills') // Make sure this matches your collection name
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThanOrEqualTo: end)
        .snapshots()
        .map((snapshot) {
      double total = 0.0;
      double cash = 0.0;
      double upi = 0.0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data.containsKey('totalAmount') && data['totalAmount'] is num) {
          final billTotal = (data['totalAmount'] as num).toDouble();
          final paymentMode = data['paymentMethod'] as String? ?? 'Cash'; // Use 'paymentMethod'

          total += billTotal;
          if (paymentMode == 'Cash') {
            cash += billTotal;
          } else if (paymentMode == 'UPI') {
            upi += billTotal;
          }
        }
      }
      return {'total': total, 'cash': cash, 'upi': upi};
    });
  }

  // Fetches all items sold and aggregates them
  Stream<Map<String, int>> _getAggregatedItems() {
    final (start, end) = _getDayRange(_selectedDate);

    return FirebaseFirestore.instance
        .collection('bills') // Make sure this matches your collection name
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThanOrEqualTo: end)
        .snapshots()
        .map((snapshot) {
      final Map<String, int> itemCounts = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data.containsKey('items') && data['items'] is List) {
          final items = List<Map<String, dynamic>>.from(data['items']);
          for (var item in items) {
            if (item.containsKey('name') && item.containsKey('quantity')) {
              final String name = item['name'];
              final int quantity = (item['quantity'] as num).toInt();
              itemCounts.update(name, (value) => value + quantity,
                  ifAbsent: () => quantity);
            }
          }
        }
      }
      return itemCounts;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String dayName = DateFormat('MMMM dd, yyyy').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Daily Sales Report"),
        backgroundColor: theme.primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          // --- DATE PICKER UI ---
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
                      _selectedDate =
                          _selectedDate.subtract(const Duration(days: 1));
                    });
                  },
                ),
                TextButton(
                  onPressed: () => _selectDate(context),
                  child: Text(
                    dayName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  // Disable going to a future date
                  onPressed: DateFormat('yyyyMMdd').format(_selectedDate) == DateFormat('yyyyMMdd').format(DateTime.now())
                      ? null
                      : () {
                    setState(() {
                      _selectedDate =
                          _selectedDate.add(const Duration(days: 1));
                    });
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // --- STATS CARDS ---
          StreamBuilder<Map<String, double>>(
            stream: _getAggregatedStats(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (!snapshot.hasData) return const SizedBox.shrink();

              final stats = snapshot.data!;
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildStatCard(
                        "Total Revenue", stats['total'] ?? 0.0, Colors.green),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: _buildStatCard(
                                "Total Cash", stats['cash'] ?? 0.0, Colors.blue)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _buildStatCard(
                                "Total UPI", stats['upi'] ?? 0.0, Colors.purple)),
                      ],
                    )
                  ],
                ),
              );
            },
          ),
          const Divider(),
          // --- ITEM LIST HEADER ---
          Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Item Sold",
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text("Quantity",
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // --- AGGREGATED ITEM LIST ---
          Expanded(
            child: StreamBuilder<Map<String, int>>(
              stream: _getAggregatedItems(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                      child: Text("No items sold on this day.",
                          style: TextStyle(fontSize: 16, color: Colors.grey)));
                }

                final itemCounts = snapshot.data!;
                final sortedItems = itemCounts.entries.toList()
                  ..sort((a, b) =>
                      b.value.compareTo(a.value)); // Sort by quantity

                return ListView.builder(
                  itemCount: sortedItems.length,
                  itemBuilder: (context, index) {
                    final item = sortedItems[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(item.key,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500)),
                            Text(item.value.toString(),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ],
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

  Widget _buildStatCard(String title, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
            TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            "₹ ${amount.toStringAsFixed(2)}",
            style:
            TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
