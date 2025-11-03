import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'bill_detail_page.dart'; // We will create this next

class AllBillsPage extends StatelessWidget {
  const AllBillsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("All Bills"),
        backgroundColor: theme.primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bills')
            .orderBy('timestamp', descending: true) // Newest first
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("No bills found.", style: TextStyle(fontSize: 18, color: Colors.grey)),
            );
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;

              final int billNumber = data['billNumber'] ?? 0;
              final double totalAmount = (data['totalAmount'] as num).toDouble();
              final Timestamp timestamp = data['timestamp'] ?? Timestamp.now();
              final String formattedTime = DateFormat('h:mm a').format(timestamp.toDate());
              final String formattedDate = DateFormat('MMM dd, yyyy').format(timestamp.toDate());

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    child: Text(billNumber.toString()),
                  ),
                  title: Text(
                    "Bill #$billNumber",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("$formattedDate at $formattedTime"),
                  trailing: Text(
                    "₹ ${totalAmount.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.green,
                    ),
                  ),
                  onTap: () {
                    // Navigate to the new detail page
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BillDetailPage(billId: doc.id),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}