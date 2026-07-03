import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'theme.dart';


class NotificationDetailPage extends StatelessWidget {
  final String title;
  final String message;
  final String? sentBy;
  final DateTime? timestamp;

  const NotificationDetailPage({
    super.key,
    required this.title,
    required this.message,
    this.sentBy,
    this.timestamp,
  });


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Notice Detail'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: gradientCard(gradient: AppGradients.brand, radius: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.campaign_outlined, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 16),
                  Text(title,
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (sentBy != null || timestamp != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: glassCard(radius: 14),
                child: Row(
                  children: [
                    if (sentBy != null) ...[  
                      const Icon(Icons.person_rounded, color: AppColors.accentBlue, size: 16),
                      const SizedBox(width: 6),
                      Text('From: ${sentBy!.split('@').first}',
                          style: GoogleFonts.poppins(
                              color: AppColors.accentBlue, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 16),
                    ],
                    if (timestamp != null) ...[  
                      const Icon(Icons.access_time_rounded, color: AppColors.textHint, size: 14),
                      const SizedBox(width: 4),
                      Text(DateFormat('dd MMM yyyy, hh:mm a').format(timestamp!),
                          style: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 11)),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: glassCard(radius: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MESSAGE',
                      style: GoogleFonts.poppins(
                          color: AppColors.textSecondary, fontSize: 10,
                          fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  const SizedBox(height: 10),
                  Text(message,
                      style: GoogleFonts.poppins(
                          color: AppColors.textPrimary, fontSize: 16, height: 1.7)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}