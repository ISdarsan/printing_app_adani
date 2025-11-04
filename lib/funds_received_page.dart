import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FundsReceivedPage extends StatelessWidget {
  const FundsReceivedPage({super.key});

  // Your Adani brand gradient
  final LinearGradient adaniGradient = const LinearGradient(
    colors: [
      Color(0xFF0066B3), // blue
      Color(0xFF6C3FB5), // purple
      Color(0xFFE91E63), // pink
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Stream to get the monthly fund (entered by Admin)
  Stream<DocumentSnapshot> _getMonthlyFundStream() {
    final String monthId = DateFormat('yyyy-MM').format(DateTime.now());
    return FirebaseFirestore.instance
        .collection('monthlyFunds')
        .doc(monthId)
        .snapshots();
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
            'Monthly Fund Report',
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<DocumentSnapshot>(
          stream: _getMonthlyFundStream(),
          builder: (context, snapshot) {
            String fundAmount = "₹ 0.00";
            String lastUpdated = "Not set yet";

            if (snapshot.connectionState == ConnectionState.waiting) {
              fundAmount = "Loading...";
              lastUpdated = "Checking...";
            } else if (snapshot.hasData && snapshot.data!.exists) {
              var data = snapshot.data!.data() as Map<String, dynamic>;
              if (data.containsKey('fundAmount')) {
                fundAmount =
                "₹ ${(data['fundAmount'] as num).toStringAsFixed(2)}";
              }
              if (data.containsKey('lastUpdated')) {
                lastUpdated =
                "Last updated: ${DateFormat('dd MMM yyyY, hh:mm a').format((data['lastUpdated'] as Timestamp).toDate())}";
              }
            } else if (snapshot.hasError) {
              fundAmount = "Error";
              lastUpdated = "Could not load data";
            } else if (!snapshot.hasData || !snapshot.data!.exists) {
              fundAmount = "₹ 0.00";
              lastUpdated = "No fund entered by Admin for this month.";
            }

            // This is the "cool" card UI for the Cashier
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: adaniGradient, // Use the "cool" gradient
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: adaniGradient.colors.last.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min, // Make card compact
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Total Fund Received This Month",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70, // Lighter text for the label
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    fundAmount,
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    lastUpdated,
                    style: const TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}