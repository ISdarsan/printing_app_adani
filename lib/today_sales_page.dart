import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'theme.dart';
import 'bill_detail_page.dart';

class TodaySalesPage extends StatelessWidget {
  const TodaySalesPage({super.key});

  (DateTime, DateTime) _getTodayRange() {
    final now = DateTime.now();
    return (
      DateTime(now.year, now.month, now.day, 0, 0, 0),
      DateTime(now.year, now.month, now.day, 23, 59, 59)
    );
  }

  Stream<QuerySnapshot> _getBillsStream() {
    final (s, e) = _getTodayRange();
    return FirebaseFirestore.instance
        .collection('bills')
        .where('timestamp', isGreaterThanOrEqualTo: s)
        .where('timestamp', isLessThanOrEqualTo: e)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: "Today's Sales"),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getBillsStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.gradBlue));
          }
          if (snap.hasError) {
            return Center(
                child: Text('Error: ${snap.error}',
                    style: GoogleFonts.poppins(color: AppColors.accentRed)));
          }

          final bills = snap.data?.docs ?? [];
          double total = 0, cash = 0, upi = 0;
          for (final b in bills) {
            final d = b.data() as Map<String, dynamic>;
            final amt = (d['totalAmount'] as num).toDouble();
            total += amt;
            if (d['paymentMode'] == 'Cash') {
              cash += amt;
            } else {
              upi += amt;
            }
          }

          return Column(
            children: [
              // ── Summary Header ─────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: gradientCard(
                      gradient: AppGradients.greenAccent, radius: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('MMMM dd, yyyy').format(DateTime.now()),
                          style: GoogleFonts.poppins(
                              color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('₹ ${total.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w800)),
                      Text("Total Sales Today",
                          style: GoogleFonts.poppins(
                              color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 16),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            _pill('💵 Cash', '₹${cash.toStringAsFixed(0)}'),
                            const SizedBox(width: 16),
                            _pill('📱 UPI', '₹${upi.toStringAsFixed(0)}'),
                            const SizedBox(width: 16),
                            _pill('🧾 Bills', '${bills.length}'),
                          ]),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(children: [
                  const Icon(Icons.receipt_long_outlined,
                      color: AppColors.textSecondary, size: 16),
                  const SizedBox(width: 6),
                  sectionTitle('Recent Bills'),
                ]),
              ),

              Expanded(
                child: bills.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            const Icon(Icons.receipt_outlined,
                                size: 56, color: AppColors.textHint),
                            const SizedBox(height: 12),
                            Text('No bills today yet.',
                                style: GoogleFonts.poppins(
                                    color: AppColors.textSecondary,
                                    fontSize: 15)),
                          ]))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemCount: bills.length,
                        itemBuilder: (_, i) {
                          final doc = bills[i];
                          final d = doc.data() as Map<String, dynamic>;
                          final amt = (d['totalAmount'] as num).toDouble();
                          final ts = (d['timestamp'] as Timestamp).toDate();
                          final billNum = d['billNumber'] ?? 0;
                          final mode = d['paymentMode'] ?? 'N/A';

                          return GestureDetector(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        BillDetailPage(billId: doc.id))),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              decoration: glassCard(radius: 14),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                      gradient: AppGradients.brand,
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Center(
                                      child: Text('#$billNum',
                                          style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11))),
                                ),
                                title: Text('Bill #$billNum',
                                    style: GoogleFonts.poppins(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                subtitle: Text(DateFormat.jm().format(ts),
                                    style: GoogleFonts.poppins(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                                trailing: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('₹${amt.toStringAsFixed(0)}',
                                          style: GoogleFonts.poppins(
                                              color: AppColors.accentGreen,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15)),
                                      buildBadge(
                                          mode,
                                          mode == 'Cash'
                                              ? AppColors.accentGreen
                                              : AppColors.accentBlue),
                                    ]),
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

  Widget _pill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        Text(value,
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        Text(label,
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10)),
      ]),
    );
  }
}
