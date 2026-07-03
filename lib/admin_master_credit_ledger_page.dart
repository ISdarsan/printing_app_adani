import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'theme.dart';
import 'bill_detail_page.dart';

class AdminMasterCreditLedgerPage extends StatefulWidget {
  const AdminMasterCreditLedgerPage({super.key});

  @override
  State<AdminMasterCreditLedgerPage> createState() =>
      _AdminMasterCreditLedgerPageState();
}

class _AdminMasterCreditLedgerPageState
    extends State<AdminMasterCreditLedgerPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _filterStatus = 'All'; // All, Paid, Pending

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Master Credit Ledger'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) =>
                  setState(() => _searchQuery = val.toLowerCase()),
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by bill no, name, or phone...',
                hintStyle: GoogleFonts.poppins(
                    color: AppColors.textHint, fontSize: 14),
                filled: true,
                fillColor: AppColors.bgCard,
                prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Filter Chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: ['All', 'Pending', 'Paid'].map((status) {
                final isSelected = _filterStatus == status;
                final color = status == 'Paid'
                    ? AppColors.accentGreen
                    : status == 'Pending'
                        ? AppColors.accentOrange
                        : AppColors.accentBlue;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _filterStatus = status),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(alpha: 0.2)
                            : AppColors.bgCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isSelected ? color : AppColors.glassBorder,
                            width: isSelected ? 1.5 : 1),
                      ),
                      child: Text(status,
                          style: GoogleFonts.poppins(
                              color: isSelected ? color : AppColors.textHint,
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('bills')
                  .where('paymentMode', isEqualTo: 'Credit')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentBlue));
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.white)));
                }

                var docs = snapshot.data?.docs ?? [];
                
                // Sort locally to avoid needing a Firestore composite index
                docs.sort((a, b) {
                  final tsA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                  final tsB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                  if (tsA == null && tsB == null) return 0;
                  if (tsA == null) return -1;
                  if (tsB == null) return 1;
                  return tsA.compareTo(tsB); // Ascending order
                });

                if (_searchQuery.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final billNum = (data['billNumber'] ?? '').toString().toLowerCase();
                    final phone = (data['customerPhone'] ?? '').toString().toLowerCase();
                    final name = (data['customerName'] ?? '').toString().toLowerCase();
                    return billNum.contains(_searchQuery) ||
                           phone.contains(_searchQuery) ||
                           name.contains(_searchQuery);
                  }).toList();
                }

                // Apply status filter
                if (_filterStatus != 'All') {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final pending = (data['pendingAmount'] as num?)?.toDouble() ??
                        (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
                    final isPaid = (data['creditStatus'] == 'Paid') || pending <= 0;
                    return _filterStatus == 'Paid' ? isPaid : !isPaid;
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Text('No credit bills found',
                        style: GoogleFonts.poppins(
                            color: AppColors.textHint, fontSize: 16)),
                  );
                }

                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final billId = docs[index].id;
                    final billNum = data['billNumber'] ?? '-';
                    final customerName = data['customerName'] ?? 'Unknown';
                    final customerPhone = data['customerPhone'] ?? '';
                    final total = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
                    final pending = (data['pendingAmount'] as num?)?.toDouble() ?? total;
                    final ts = data['timestamp'] as Timestamp?;
                    final dateStr = ts != null
                        ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate())
                        : 'Unknown Date';
                    final status = data['creditStatus'] ?? 'Pending';
                    final isPaid = status == 'Paid' || pending <= 0;

                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BillDetailPage(billId: billId),
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentBlue.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text('#$billNum', style: GoogleFonts.poppins(color: AppColors.accentBlue, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(dateStr, style: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 12)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isPaid ? AppColors.accentGreen.withValues(alpha: 0.15) : AppColors.accentOrange.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(isPaid ? 'Paid' : 'Pending', style: GoogleFonts.poppins(color: isPaid ? AppColors.accentGreen : AppColors.accentOrange, fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(customerName, style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                      Text(customerPhone, style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Total: ₹${total.toStringAsFixed(0)}', style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 13)),
                                    Text('Due: ₹${pending.toStringAsFixed(0)}', style: GoogleFonts.poppins(color: AppColors.accentRed, fontSize: 16, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
