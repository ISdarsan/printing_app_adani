import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';

class SendNotificationPage extends StatefulWidget {
  const SendNotificationPage({super.key});

  @override
  State<SendNotificationPage> createState() => _SendNotificationPageState();
}

class _SendNotificationPageState extends State<SendNotificationPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendNotification() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final String title = _titleController.text;
      final String message = _messageController.text;

      await FirebaseFirestore.instance.collection('notifications').add({
        'title': title,
        'message': message,
        'timestamp': Timestamp.now(),
        'sentBy': user?.email ?? 'Admin',
      });

      _titleController.clear();
      _messageController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ Notification sent', style: GoogleFonts.poppins()), backgroundColor: const Color(0xFF1B4332)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e', style: GoogleFonts.poppins()), backgroundColor: AppColors.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Send Notification'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: glassCard(radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.campaign_outlined, color: AppColors.accentBlue, size: 22),
                        const SizedBox(width: 8),
                        sectionTitle('New Message Details'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _titleController,
                      style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
                      decoration: darkInput(label: 'Title', prefixIcon: Icons.title),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _messageController,
                      maxLines: 5,
                      style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
                      decoration: darkInput(label: 'Message', prefixIcon: Icons.message_outlined),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              buildGradientButton(
                label: 'Send to All Staff',
                icon: Icons.send_rounded,
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _sendNotification,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
