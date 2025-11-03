import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class BillDetailPage extends StatelessWidget {
  final String billId;
  const BillDetailPage({super.key, required this.billId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text("Bill Details"),
        backgroundColor: theme.primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('bills').doc(billId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Bill not found."));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final items = List<Map<String, dynamic>>.from(data['items']);
          final billNumber = data['billNumber'] ?? 0;
          final totalAmount = (data['totalAmount'] as num).toDouble();
          final paymentMode = data['paymentMode'] ?? 'N/A';
          final timestamp = data['timestamp'] as Timestamp;
          final formattedDate = DateFormat('MMM dd, yyyy  h:mm a').format(timestamp.toDate());

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Bill Summary Card ---
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Text(
                            "Bill #$billNumber",
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.primaryColor),
                          ),
                          const SizedBox(height: 8),
                          Text(formattedDate, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 16),
                          _buildDetailRow("Total Amount:", "₹ ${totalAmount.toStringAsFixed(2)}", isTotal: true),
                          _buildDetailRow("Payment Mode:", paymentMode),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- Item List ---
                  Text(
                    "Items in this Bill",
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final itemName = item['name'];
                      final itemQty = (item['quantity'] as num).toInt();
                      final itemPrice = (item['price'] as num).toDouble();
                      final itemTotal = itemQty * itemPrice;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(itemName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("$itemQty x ₹${itemPrice.toStringAsFixed(2)}"),
                          trailing: Text(
                            "₹ ${itemTotal.toStringAsFixed(2)}",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isTotal ? Colors.green : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}