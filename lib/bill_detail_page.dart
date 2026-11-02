import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'theme.dart';
import 'state_views.dart';

class BillDetailPage extends StatelessWidget {
  final String billId;
  const BillDetailPage({super.key, required this.billId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Bill Details'),
      body: RetryScope(
        builder: (context, attempt, retry) => FutureBuilder<DocumentSnapshot>(
          key: ValueKey(attempt),
          future:
              FirebaseFirestore.instance.collection('bills').doc(billId).get(),
          builder: (context, snap) {
            if (snap.hasError) {
              // A failed load is not "not found": say so and offer Retry.
              return AppErrorState(error: snap.error, onRetry: retry);
            }
            if (snap.connectionState == ConnectionState.waiting) {
              return const AppLoading();
            }
            if (!snap.hasData || !snap.data!.exists) {
              return Center(
                  child: Text('Bill not found.',
                      style: AppText.style(color: AppColors.textSecondary)));
            }

            final data = snap.data!.data() as Map<String, dynamic>;
            final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
            final billNum = data['billNumber'] ?? 0;
            final total = ((data['totalAmount'] ?? 0) as num).toDouble();
            final mode = data['paymentMode'] ?? 'N/A';
            DateTime dateObj = DateTime.now();
            if (data['timestamp'] is Timestamp) {
              dateObj = (data['timestamp'] as Timestamp).toDate();
            }
            final date = DateFormat('MMM dd, yyyy  •  h:mm a').format(dateObj);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ── Bill Header ───────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration:
                        gradientCard(gradient: AppGradients.brand, radius: 20),
                    child: Column(children: [
                      const Icon(Icons.receipt_long_rounded,
                          color: Colors.white, size: 36),
                      const SizedBox(height: 10),
                      Text('Bill #$billNum',
                          style: AppText.style(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(date,
                          style: AppText.style(
                              color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 16),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _headerStat(
                                'Total', '₹${total.toStringAsFixed(2)}'),
                            Container(
                                width: 1, height: 36, color: Colors.white30),
                            _headerStat('Payment', mode),
                            Container(
                                width: 1, height: 36, color: Colors.white30),
                            _headerStat('Items', '${items.length}'),
                          ]),
                    ]),
                  ),
                  const SizedBox(height: 18),

                  // ── Items List ────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: glassCard(radius: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        sectionTitle('Items in this Bill'),
                        const SizedBox(height: 12),
                        const Divider(color: AppColors.bgDivider, height: 1),
                        ...items.map((item) {
                          final name = item['name'] ?? 'Item';
                          final qty = ((item['quantity'] ?? 0) as num).toInt();
                          final price =
                              ((item['price'] ?? 0) as num).toDouble();
                          final subtotal = qty * price;
                          return Column(
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Row(children: [
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(name,
                                              style: AppText.style(
                                                  color: AppColors.textPrimary,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14)),
                                          Text(
                                              '$qty × ₹${price.toStringAsFixed(2)}',
                                              style: AppText.style(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 12)),
                                        ]),
                                  ),
                                  Text('₹${subtotal.toStringAsFixed(2)}',
                                      style: AppText.style(
                                          color: AppColors.accentGreen,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15)),
                                ]),
                              ),
                              const Divider(
                                  color: AppColors.bgDivider, height: 1),
                            ],
                          );
                        }),
                        const SizedBox(height: 12),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('TOTAL',
                                  style: AppText.style(
                                      color: AppColors.textSecondary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              Text('₹${total.toStringAsFixed(2)}',
                                  style: AppText.style(
                                      color: AppColors.accentGreen,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800)),
                            ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _headerStat(String label, String value) {
    return Column(children: [
      Text(value,
          style: AppText.style(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      Text(label, style: AppText.style(color: Colors.white70, fontSize: 11)),
    ]);
  }
}
