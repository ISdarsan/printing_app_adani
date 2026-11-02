import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'stream_cache.dart';
import 'state_views.dart';
import 'credit_detail_page.dart';
import 'canteen_provider.dart';

class CreditCustomersPage extends StatefulWidget {
  const CreditCustomersPage({super.key});

  @override
  State<CreditCustomersPage> createState() => _CreditCustomersPageState();
}

class _CreditCustomersPageState extends State<CreditCustomersPage> {
  final StreamCache _streams = StreamCache();

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
      appBar: buildGradientAppBar(title: 'Credit Customers'),
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
              stream: _streams.get('customers', () => FirebaseFirestore.instance
                  .collection('creditCustomers')
                  .where('canteenId',
                      isEqualTo: CanteenProvider.selectedCanteenId)
                  .snapshots()),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentBlue));
                }
                if (snapshot.hasError) {
                  debugPrint(
                      '[CreditCustomers] Firestore error: ${snapshot.error}');
                  return AppErrorState(
                      error: snapshot.error,
                      onRetry: () => setState(_streams.reset));
                }

                debugPrint(
                    '[CreditCustomers] canteenId=${CanteenProvider.selectedCanteenId}, '
                    'total docs=${snapshot.data?.docs.length ?? 0}');

                // Filter and sort client-side to avoid composite index requirement
                var docs = (snapshot.data?.docs ?? []).where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final pending =
                      ((data['totalPending'] ?? 0) as num).toDouble();
                  return pending > 0;
                }).toList()
                  ..sort((a, b) {
                    final pa =
                        ((a.data() as Map<String, dynamic>)['totalPending'] ??
                            0) as num;
                    final pb =
                        ((b.data() as Map<String, dynamic>)['totalPending'] ??
                            0) as num;
                    return pb.compareTo(pa); // descending
                  });

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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.credit_score_rounded,
                            color: AppColors.textHint, size: 48),
                        const SizedBox(height: 12),
                        Text('No credit customers found',
                            style: AppText.style(
                                color: AppColors.textHint, fontSize: 16)),
                        const SizedBox(height: 6),
                        Text(
                          'Canteen: ${CanteenProvider.selectedCanteenName}',
                          style: AppText.style(
                              color: AppColors.textHint, fontSize: 12),
                        ),
                      ],
                    ),
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
                        data: data,
                        customerId: docs[index].id,
                        canteenId: (data['canteenId'] ??
                                CanteenProvider.selectedCanteenId)
                            .toString());
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
  final String canteenId;

  const _CustomerTile({
    required this.data,
    required this.customerId,
    required this.canteenId,
  });

  @override
  Widget build(BuildContext context) {
    final pending = (data['totalPending'] ?? 0.0) as num;
    final name = data['name'] ?? 'Unknown';
    final phone = (data['phone'] ?? '').toString();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreditDetailPage(
              customerId: customerId,
              customerPhone: phone,
              customerName: name,
              canteenId: canteenId,
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
                Text('Pending',
                    style:
                        AppText.style(color: AppColors.textHint, fontSize: 11)),
                Text('₹${pending.toStringAsFixed(2)}',
                    style: AppText.style(
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
