import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'theme.dart';
import 'stream_cache.dart';
import 'bill_detail_page.dart';
import 'canteen_provider.dart';
import 'business_time.dart';

class DailySalesReportPage extends StatefulWidget {
  final DateTime? selectedDate;
  const DailySalesReportPage({super.key, this.selectedDate});

  @override
  State<DailySalesReportPage> createState() => _DailySalesReportPageState();
}

class _DailySalesReportPageState extends State<DailySalesReportPage> {
  final StreamCache _streams = StreamCache();
  Stream<T> _cached<T>(String name, Stream<T> Function() make, String sig) =>
      _streams.get<T>(name, make,
          signature: '${CanteenProvider.selectedCanteenId}|$sig');

  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate =
        widget.selectedDate ?? BusinessTime.wallClock(DateTime.now());
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.gradBlue,
            onPrimary: Colors.white,
            surface: AppColors.bgCard,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  // _selectedDate is a calendar date (from the picker or "now"); its
  // year/month/day are interpreted in the business timezone.
  Stream<QuerySnapshot> _getBillsStream() {
    final day = BusinessTime.dayRangeForDate(
        _selectedDate.year, _selectedDate.month, _selectedDate.day);
    // Branch-scoped + half-open range. Index: bills(canteenId, timestamp).
    return CanteenProvider.scopeQuery(
            FirebaseFirestore.instance.collection('bills'))
        .where('timestamp', isGreaterThanOrEqualTo: day.start)
        .where('timestamp', isLessThan: day.end)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Daily Sales Report'),
      body: Column(
        children: [
          // ── Date Selector ─────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: GestureDetector(
              onTap: () => _selectDate(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: glassCard(radius: 14),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        color: AppColors.accentBlue, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      DateFormat('EEEE, MMMM dd yyyy').format(_selectedDate),
                      style: AppText.style(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: AppGradients.blueAccent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Change',
                          style: AppText.style(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bills List ─────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _cached('bills', _getBillsStream,
                  _selectedDate.toIso8601String().substring(0, 10)),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.gradBlue));
                }
                if (snap.hasError) {
                  debugPrint('[DailySalesReport] Error: ${snap.error}');
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error loading report:\n${snap.error}',
                        style: AppText.style(
                            color: AppColors.accentRed, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final allDocs = snap.data?.docs ?? [];
                final bills = allDocs.where((b) {
                  final d = b.data() as Map<String, dynamic>;
                  return CanteenProvider.matchesSelectedCanteen(d);
                }).toList();

                if (bills.isEmpty) {
                  return Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.receipt_outlined,
                              size: 56, color: AppColors.textHint),
                          const SizedBox(height: 12),
                          Text('No bills for this date',
                              style: AppText.style(
                                  color: AppColors.textSecondary,
                                  fontSize: 15)),
                          const SizedBox(height: 6),
                          Text(
                            'Canteen: ${CanteenProvider.selectedCanteenName}',
                            style: AppText.style(
                                color: AppColors.textHint, fontSize: 12),
                          ),
                        ]),
                  );
                }

                double total = 0, cash = 0, upi = 0, credit = 0;
                for (final b in bills) {
                  final d = b.data() as Map<String, dynamic>;
                  final amt = ((d['totalAmount'] ?? 0) as num).toDouble();
                  total += amt;
                  final mode = d['paymentMode']?.toString() ?? 'N/A';
                  if (mode == 'Cash') {
                    cash += amt;
                  } else if (mode == 'UPI') {
                    upi += amt;
                  } else if (mode == 'Credit') {
                    credit += amt;
                  }
                }

                return Column(
                  children: [
                    // Summary Card
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: gradientCard(
                            gradient: AppGradients.greenAccent, radius: 18),
                        child: Column(
                          children: [
                            Text('₹${total.toStringAsFixed(2)}',
                                style: AppText.style(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800)),
                            Text('Total Sales',
                                style: AppText.style(
                                    color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 14),
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _statPill(
                                      'Cash', '₹${cash.toStringAsFixed(0)}'),
                                  _statPill(
                                      'UPI', '₹${upi.toStringAsFixed(0)}'),
                                  _statPill('Credit',
                                      '₹${credit.toStringAsFixed(0)}'),
                                  _statPill('Bills', '${bills.length}'),
                                ]),
                          ],
                        ),
                      ),
                    ),

                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemCount: bills.length,
                        itemBuilder: (_, i) {
                          final doc = bills[i];
                          final d = doc.data() as Map<String, dynamic>;
                          final billNum = d['billNumber'] ?? 0;
                          final amt =
                              ((d['totalAmount'] ?? 0) as num).toDouble();
                          final mode = d['paymentMode']?.toString() ?? 'N/A';
                          DateTime ts = DateTime.now();
                          if (d['timestamp'] is Timestamp) {
                            ts = (d['timestamp'] as Timestamp).toDate();
                          }

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
                                          style: AppText.style(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11))),
                                ),
                                title: Text('Bill #$billNum',
                                    style: AppText.style(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                subtitle: Text(DateFormat.jm().format(ts),
                                    style: AppText.style(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                                trailing: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('₹${amt.toStringAsFixed(0)}',
                                          style: AppText.style(
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
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, String value) {
    return Column(children: [
      Text(value,
          style: AppText.style(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      Text(label, style: AppText.style(color: Colors.white70, fontSize: 11)),
    ]);
  }
}
