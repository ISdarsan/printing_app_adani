import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ExpenseDetailPage extends StatelessWidget {
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

  final DocumentSnapshot expenseDoc;
  const ExpenseDetailPage({super.key, required this.expenseDoc});

  @override
  Widget build(BuildContext context) {
    // Extract data from the document
    final Map<String, dynamic> expenseData =
    expenseDoc.data() as Map<String, dynamic>;

    final String description = expenseData['description'] ?? 'No Description';
    final double amount = (expenseData['amount'] as num).toDouble();

    // Safely get the image string
    final String? base64ImageString = expenseData['proofImageBase64'];

    // Safely get the date
    final DateTime date = (expenseData['timestamp'] as Timestamp).toDate();
    final String formattedDate =
    DateFormat('dd MMMM yyyy, hh:mm a').format(date);

    // Function to convert the Base64 string back to an image
    Widget buildImage() {
      if (base64ImageString == null || base64ImageString.isEmpty) {
        return Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Text(
              'No Bill Image Uploaded',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        );
      }

      try {
        // This decodes the string back into image data
        final Uint8List imageBytes = base64Decode(base64ImageString);
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            imageBytes,
            fit: BoxFit.cover,
            width: double.infinity,
          ),
        );
      } catch (e) {
        // If the string is corrupted
        return Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Text(
              'Error loading image.',
              style: TextStyle(color: Colors.red),
            ),
          ),
        );
      }
    }

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
            'Expense Details',
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

      // --- THIS IS THE FIX ---
      // We wrap the body in a SafeArea widget
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Card for the Bill Image ---
              const Text(
                'Proof of Expense',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003C8F),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
                clipBehavior: Clip.antiAlias, // Ensures image respects border
                child: buildImage(),
              ),
              const SizedBox(height: 24),

              // --- Card for the Details ---
              const Text(
                'Details',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003C8F),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
                child: Column(
                  children: [
                    ListTile(
                      leading:
                      Icon(Icons.description, color: Colors.blue.shade700),
                      title: const Text(
                        'Description',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        description,
                        style: const TextStyle(fontSize: 16, color: Colors.black),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: Icon(Icons.calendar_today,
                          color: Colors.blue.shade700),
                      title: const Text(
                        'Date',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        formattedDate,
                        style: const TextStyle(fontSize: 16, color: Colors.black),
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading:
                      Icon(Icons.currency_rupee, color: Colors.green.shade700),
                      title: const Text(
                        'Amount',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '₹ ${amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // --- END OF FIX ---
    );
  }
}