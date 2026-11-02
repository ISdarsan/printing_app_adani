import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'state_views.dart';
import 'credit_detail_page.dart';

class AdminCreditCustomersPage extends StatefulWidget {
  const AdminCreditCustomersPage({super.key});

  @override
  State<AdminCreditCustomersPage> createState() =>
      _AdminCreditCustomersPageState();
}

class _AdminCreditCustomersPageState extends State<AdminCreditCustomersPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'All Credit Accounts'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) =>
                  setState(() => _searchQuery = val.toLowerCase()),
              style: AppText.style(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by name or phone...',
                hintStyle:
                    AppText.style(color: AppColors.textHint, fontSize: 14),
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
                  .orderBy('totalPending', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentBlue));
                }
                if (snapshot.hasError) {
                  return AppErrorState(
                      inline: true,
                      error: snapshot.error,
                      onRetry: () => setState(() {}));
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
                    child: Text('No credit accounts found',
                        style: AppText.style(
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
            builder: (_) => CreditDetailPage(
              customerId: customerId,
              customerPhone: phone.toString(),
              customerName: name.toString(),
              canteenId: (data['canteenId'] ?? 'main').toString(),
              canteenName: (data['canteenName'] ?? 'Main Canteen').toString(),
            ),
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
                color: pending <= 0
                    ? AppColors.accentGreen.withValues(alpha: 0.15)
                    : AppColors.accentOrange.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person,
                  color: pending <= 0
                      ? AppColors.accentGreen
                      : AppColors.accentOrange),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: AppText.style(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  Text(phone,
                      style: AppText.style(
                          color: AppColors.textHint, fontSize: 13)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(pending <= 0 ? 'Settled' : 'Pending',
                    style: AppText.style(
                        color: pending <= 0
                            ? AppColors.accentGreen
                            : AppColors.textHint,
                        fontSize: 11)),
                Text('₹${pending.toStringAsFixed(2)}',
                    style: AppText.style(
                        color: pending <= 0
                            ? AppColors.accentGreen
                            : AppColors.accentRed,
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
