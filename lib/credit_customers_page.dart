import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';
import 'credit_detail_page.dart';

class CreditCustomersPage extends StatefulWidget {
  const CreditCustomersPage({super.key});

  @override
  State<CreditCustomersPage> createState() => _CreditCustomersPageState();
}

class _CreditCustomersPageState extends State<CreditCustomersPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Credit Customers'),
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
                hintText: 'Search by name or phone...',
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
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('creditCustomers')
                  .where('totalPending', isGreaterThan: 0)
                  .orderBy('totalPending', descending: true)
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
                if (_searchQuery.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = (data['name'] ?? '').toString().toLowerCase();
                    final phone =
                        (data['phone'] ?? '').toString().toLowerCase();
                    return name.contains(_searchQuery) ||
                        phone.contains(_searchQuery);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Text('No credit customers found',
                        style: GoogleFonts.poppins(
                            color: AppColors.textHint, fontSize: 16)),
                  );
                }

                return ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    return _CustomerTile(
                        data: data, customerId: docs[index].id);
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

class _CustomerTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String customerId;

  const _CustomerTile({required this.data, required this.customerId});

  @override
  Widget build(BuildContext context) {
    final pending = (data['totalPending'] ?? 0.0) as num;
    final name = data['name'] ?? 'Unknown';
    final phone = data['phone'] ?? 'Unknown';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CreditDetailPage(customerPhone: customerId, customerName: name),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: AppColors.accentOrange),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  Text(phone,
                      style: GoogleFonts.poppins(
                          color: AppColors.textHint, fontSize: 13)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Pending',
                    style: GoogleFonts.poppins(
                        color: AppColors.textHint, fontSize: 11)),
                Text('₹${pending.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                        color: AppColors.accentRed,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
