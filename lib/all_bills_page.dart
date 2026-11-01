import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'theme.dart';
import 'bill_detail_page.dart';
import 'canteen_provider.dart';

class AllBillsPage extends StatefulWidget {
  const AllBillsPage({super.key});
  @override
  State<AllBillsPage> createState() => _AllBillsPageState();
}

class _AllBillsPageState extends State<AllBillsPage> {
  DateTime _selectedMonth = DateTime.now();

  DateTime get _start => DateTime(_selectedMonth.year, _selectedMonth.month, 1);
  DateTime get _end =>
      DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0, 23, 59, 59);

  Stream<QuerySnapshot> get _stream => FirebaseFirestore.instance
      .collection('bills')
      .where('timestamp', isGreaterThanOrEqualTo: _start)
      .where('timestamp', isLessThanOrEqualTo: _end)
      .orderBy('timestamp', descending: true)
      .snapshots();

  bool get _canGoForward {
    final now = DateTime.now();
    return _selectedMonth.year < now.year ||
        (_selectedMonth.year == now.year && _selectedMonth.month < now.month);
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = _selectedMonth.month == DateTime.now().month &&
        _selectedMonth.year == DateTime.now().year;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Bills History'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.bgDivider)),
              child: Row(children: [
                IconButton(
                    icon: const Icon(Icons.chevron_left,
                        color: AppColors.textSecondary),
                    onPressed: () => setState(() => _selectedMonth = DateTime(
                        _selectedMonth.year, _selectedMonth.month - 1))),
                Expanded(
                  child: Column(children: [
                    Text(DateFormat('MMMM yyyy').format(_selectedMonth),
                        style: AppText.style(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center),
                    if (isCurrent)
                      Text('Current Month',
                          style: AppText.style(
                              color: AppColors.accentBlue, fontSize: 11)),
                  ]),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right,
                      color: _canGoForward
                          ? AppColors.textSecondary
                          : AppColors.textHint),
                  onPressed: _canGoForward
                      ? () => setState(() => _selectedMonth = DateTime(
                          _selectedMonth.year, _selectedMonth.month + 1))
                      : null,
                ),
              ]),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.gradBlue));
                }
                if (snap.hasError) {
                  debugPrint('[AllBills] Error: ${snap.error}');
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error loading bills:\n${snap.error}',
                        style: AppText.style(
                            color: AppColors.accentRed, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final allDocs = snap.data?.docs ?? [];
                final bills = allDocs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  return CanteenProvider.matchesSelectedCanteen(d);
                }).toList();

                if (bills.isEmpty) {
                  return Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        const Icon(Icons.receipt_long_outlined,
                            size: 60, color: AppColors.textHint),
                        const SizedBox(height: 12),
                        Text(
                            'No bills in ${DateFormat('MMMM yyyy').format(_selectedMonth)}',
                            style: AppText.style(
                                color: AppColors.textSecondary, fontSize: 15)),
                        const SizedBox(height: 6),
                        Text(
                          'Canteen: ${CanteenProvider.selectedCanteenName}',
                          style: AppText.style(
                              color: AppColors.textHint, fontSize: 12),
                        ),
                      ]));
                }
                double total = 0, cash = 0, upi = 0, credit = 0;
                for (final doc in bills) {
                  final d = doc.data() as Map<String, dynamic>;
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
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: gradientCard(
                          gradient: AppGradients.greenAccent, radius: 14),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _stat('Total', '₹${total.toStringAsFixed(0)}'),
                            _div(),
                            _stat('Cash', '₹${cash.toStringAsFixed(0)}'),
                            _div(),
                            _stat('UPI', '₹${upi.toStringAsFixed(0)}'),
                            _div(),
                            _stat('Credit', '₹${credit.toStringAsFixed(0)}'),
                            _div(),
                            _stat('Bills', bills.length.toString()),
                          ]),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      itemCount: bills.length,
                      itemBuilder: (_, i) {
                        final doc = bills[i];
                        final data = doc.data() as Map<String, dynamic>;
                        final billNum = data['billNumber'] ?? 0;
                        final amount =
                            ((data['totalAmount'] ?? 0) as num).toDouble();
                        DateTime date = DateTime.now();
                        if (data['timestamp'] is Timestamp) {
                          date = (data['timestamp'] as Timestamp).toDate();
                        }
                        final mode = data['paymentMode']?.toString() ?? 'N/A';
                        return GestureDetector(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      BillDetailPage(billId: doc.id))),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 5),
                            decoration: glassCard(radius: 16),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              leading: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                    gradient: AppGradients.brand,
                                    borderRadius: BorderRadius.circular(12)),
                                child: Center(
                                    child: Text('#$billNum',
                                        style: AppText.style(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12))),
                              ),
                              title: Text('Bill #$billNum',
                                  style: AppText.style(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              subtitle: Text(
                                  '${DateFormat('MMM dd').format(date)}  •  ${DateFormat.jm().format(date)}',
                                  style: AppText.style(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                              trailing: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('INR ${amount.toStringAsFixed(0)}',
                                        style: AppText.style(
                                            color: AppColors.accentGreen,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16)),
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
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: AppText.style(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        Text(label, style: AppText.style(color: Colors.white70, fontSize: 10)),
      ]);

  Widget _div() => Container(height: 24, width: 1, color: Colors.white30);
}
