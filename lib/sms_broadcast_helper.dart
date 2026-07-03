import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';

void showSMSBroadcastDialog(BuildContext context) {
  final controller = TextEditingController();

  showDialog(
    context: context,
    builder: (dialogCtx) {
      return AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
        title: Row(
          children: [
            const Icon(Icons.campaign_rounded, color: AppColors.accentOrange),
            const SizedBox(width: 10),
            Text(
              'SMS Broadcast Specials',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will retrieve all credit customer phone numbers and pre-fill them in your default SMS app to broadcast today\'s menu.',
              style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 4,
              maxLength: 140,
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: "Enter menu specials (e.g. Biryani ₹120, Tea ₹10...)",
                hintStyle: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 12),
                filled: true,
                fillColor: AppColors.bgDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
                counterStyle: const TextStyle(color: AppColors.textHint),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: GoogleFonts.poppins(color: AppColors.textHint)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentOrange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a message'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(dialogCtx);

              // Show loading overlay
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(
                  child: CircularProgressIndicator(color: AppColors.accentOrange),
                ),
              );

              try {
                // Fetch credit customers
                final snap = await FirebaseFirestore.instance.collection('creditCustomers').get();
                if (context.mounted) {
                  Navigator.pop(context); // Pop loading
                }

                final phoneNumbers = snap.docs
                    .map((doc) => (doc.data()['phone'] ?? '').toString().trim())
                    .where((phone) => phone.isNotEmpty)
                    .toList();

                if (phoneNumbers.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No credit customers found with phone numbers'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }

                // Launch SMS app
                final Uri smsUri = Uri(
                  scheme: 'sms',
                  path: phoneNumbers.join(','),
                  queryParameters: <String, String>{
                    'body': text,
                  },
                );

                if (await canLaunchUrl(smsUri)) {
                  await launchUrl(smsUri);
                } else {
                  // Fallback: try joining with semicolon
                  final Uri smsUriFallback = Uri(
                    scheme: 'sms',
                    path: phoneNumbers.join(';'),
                    queryParameters: <String, String>{
                      'body': text,
                    },
                  );
                  if (await canLaunchUrl(smsUriFallback)) {
                    await launchUrl(smsUriFallback);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open default SMS application'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context); // Pop loading if still showing
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text(
              'Launch SMS',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    },
  );
}
