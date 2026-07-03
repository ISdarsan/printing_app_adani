import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'notification_detail_page.dart';
import 'theme.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

  static Stream<QuerySnapshot> get noticesStream => FirebaseFirestore.instance
      .collection('notifications')
      .orderBy('timestamp', descending: true)
      .limit(50)
      .snapshots();

  /// Returns the count of unread notices for the current user.
  static Stream<int> get unreadCountStream =>
      noticesStream.map((snap) => snap.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final title = (data['title'] as String?)?.trim() ?? '';
            final message = (data['message'] as String?)?.trim() ?? '';
            // Ignore completely empty dummy notifications
            if (title.isEmpty && message.isEmpty) return false;
            final readBy = List<String>.from(data['readBy'] ?? []);
            return !readBy.contains(_uid);
          }).length);

  Future<void> _markAsRead(String docId) async {
    await FirebaseFirestore.instance.collection('notifications').doc(docId).update({
      'readBy': FieldValue.arrayUnion([_uid]),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Notices from Admin'),
      body: StreamBuilder<QuerySnapshot>(
        stream: noticesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.gradBlue));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications_off_rounded,
                        size: 64, color: AppColors.textHint),
                  ),
                  const SizedBox(height: 24),
                  Text('No Notices Yet',
                      style: GoogleFonts.poppins(
                          fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text('Admin messages will appear here.',
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: AppColors.textSecondary)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          final unreadDocs =
              docs.where((d) => !List<String>.from((d.data() as Map)['readBy'] ?? []).contains(_uid)).toList();
          final unreadCount = unreadDocs.length;

          return Column(
            children: [
              // ââ Unread summary banner ââââââââââââââ
              if (unreadCount > 0)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.accentRed.withValues(alpha: 0.15), AppColors.accentOrange.withValues(alpha: 0.1)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.accentRed.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.accentRed.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.mark_email_unread_rounded,
                            color: AppColors.accentRed, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$unreadCount unread notice${unreadCount > 1 ? "s" : ""}',
                        style: GoogleFonts.poppins(
                            color: AppColors.accentRed,
                            fontSize: 14,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    final date = (data['timestamp'] as Timestamp? ?? Timestamp.now()).toDate();
                    final titleRaw = data['title']?.toString().trim() ?? '';
                    final title = titleRaw.isEmpty ? 'Notice from Admin' : titleRaw;
                    final messageRaw = data['message']?.toString().trim() ?? '';
                    final message = messageRaw.isEmpty ? 'No message content' : messageRaw;
                    final sentBy = data['sentBy']?.toString().trim() ?? 'Admin';
                    final readBy = List<String>.from(data['readBy'] ?? []);
                    final isUnread = !readBy.contains(_uid);

                    return GestureDetector(
                      onTap: () async {
                        if (isUnread) await _markAsRead(doc.id);
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NotificationDetailPage(
                                title: title,
                                message: message,
                                sentBy: sentBy,
                                timestamp: date,
                              ),
                            ),
                          );
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isUnread
                              ? const Color(0xFF1A1500)
                              : const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isUnread
                                ? const Color(0xFFFF8C42)
                                : const Color(0xFF1E2D45),
                            width: isUnread ? 1.5 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left icon
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isUnread
                                      ? const Color(0xFFFF8C42).withValues(alpha: 0.2)
                                      : const Color(0xFF1E2D45),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isUnread ? Icons.campaign_rounded : Icons.notifications_none_rounded,
                                  color: isUnread ? const Color(0xFFFF8C42) : const Color(0xFF4A5568),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Main content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Title row + badge
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
                                              fontSize: 15,
                                              color: isUnread ? const Color(0xFFF0F4FF) : const Color(0xFF8899AA),
                                            ),
                                          ),
                                        ),
                                        if (isUnread) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFF4C6A),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: const Text(
                                              'NEW',
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                color: Color(0xFFFFFFFF),
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // Message snippet
                                    Text(
                                      message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        height: 1.4,
                                        color: isUnread ? const Color(0xFFD0D8E8) : const Color(0xFF4A5568),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Timestamp row
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.access_time_rounded,
                                          size: 12,
                                          color: Color(0xFF4A5568),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          DateFormat('dd MMM yyyy, hh:mm a').format(date),
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            color: Color(0xFF4A5568),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, color: Color(0xFF4A5568), size: 18),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
