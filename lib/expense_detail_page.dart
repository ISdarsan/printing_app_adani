import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'theme.dart';

class ExpenseDetailPage extends StatelessWidget {
  final DocumentSnapshot expenseDoc;
  const ExpenseDetailPage({super.key, required this.expenseDoc});

  @override
  Widget build(BuildContext context) {
    final data = expenseDoc.data() as Map<String, dynamic>;
    final String description = data['description'] ?? 'No Description';
    final String category = data['category'] ?? '';
    final double amount = (data['amount'] as num).toDouble();
    final String? base64Img = data['proofImageBase64'];
    final DateTime date = (data['timestamp'] as Timestamp).toDate();
    final String formattedDate =
        DateFormat('dd MMMM yyyy, hh:mm a').format(date);

    Widget buildImage() {
      if (base64Img == null || base64Img.isEmpty) {
        return Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
              color: AppColors.bgInput,
              borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.image_not_supported_outlined,
                color: AppColors.textHint, size: 44),
            const SizedBox(height: 8),
            Text('No Image Uploaded',
                style: GoogleFonts.poppins(
                    color: AppColors.textSecondary, fontSize: 13)),
          ]),
        );
      }
      try {
        final Uint8List bytes = base64Decode(base64Img);
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(bytes, fit: BoxFit.cover, width: double.infinity),
        );
      } catch (_) {
        return Container(
          height: 180,
          decoration: BoxDecoration(
            color: AppColors.accentRed.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.accentRed.withValues(alpha: 0.4)),
          ),
          child: Center(
              child: Text('Error loading image',
                  style: GoogleFonts.poppins(color: AppColors.accentRed))),
        );
      }
    }

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Expense Details'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Category + Amount Banner ──────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration:
                    gradientCard(gradient: AppGradients.redAccent, radius: 18),
                child: Row(
                  children: [
                    const Icon(Icons.money_off_rounded,
                        color: Colors.white, size: 40),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category,
                            style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        Text('₹ ${amount.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Details Card ──────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: glassCard(radius: 18),
                child: Column(
                  children: [
                    _detailRow(Icons.description_outlined, 'Description',
                        description, AppColors.accentBlue),
                    const Divider(color: AppColors.bgDivider, height: 20),
                    _detailRow(Icons.calendar_today_outlined, 'Date',
                        formattedDate, AppColors.accentOrange),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Proof Image ───────────────────────────────
              sectionTitle('Proof of Expense'),
              const SizedBox(height: 10),
              Container(
                decoration: glassCard(radius: 18),
                clipBehavior: Clip.antiAlias,
                child: buildImage(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: GoogleFonts.poppins(
                  color: AppColors.textSecondary, fontSize: 11)),
          Text(value,
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ]),
      ],
    );
  }
}
