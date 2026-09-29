import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';
import 'canteen_provider.dart';

class MenuViewPage extends StatefulWidget {
  const MenuViewPage({super.key});
  @override
  State<MenuViewPage> createState() => _MenuViewPageState();
}

class _MenuViewPageState extends State<MenuViewPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() =>
        setState(() => _searchQuery = _searchController.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Full Menu & Prices'),
      body: Column(
        children: [
          // ── Search Bar ─────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary, fontSize: 14),
              decoration: darkInput(
                  label: 'Search by name or code...', prefixIcon: Icons.search),
            ),
          ),

          // ── Menu List ──────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('menuItems')
                  .where('canteenId',
                      isEqualTo: CanteenProvider.selectedCanteenId)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.gradBlue));
                }
                if (snap.hasError) {
                  return Center(
                      child: Text('Error: ${snap.error}',
                          style:
                              GoogleFonts.poppins(color: AppColors.accentRed)));
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.restaurant_menu,
                              size: 60, color: AppColors.textHint),
                          const SizedBox(height: 12),
                          Text('No items in menu yet.',
                              style: GoogleFonts.poppins(
                                  color: AppColors.textSecondary,
                                  fontSize: 15)),
                          Text('Add items via "Add/Edit Item"',
                              style: GoogleFonts.poppins(
                                  color: AppColors.textHint, fontSize: 13)),
                        ]),
                  );
                }

                final all = snap.data!.docs.map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return {
                    'code': data['code'] ?? '',
                    'name': data['name'] ?? '',
                    'fullPrice': (data['fullPrice'] ?? 0.0).toDouble(),
                    'halfPrice': data['halfPrice'] != null
                        ? (data['halfPrice']).toDouble()
                        : null,
                  };
                }).toList();

                final filtered = _searchQuery.isEmpty
                    ? all
                    : all
                        .where((i) =>
                            (i['name'] as String)
                                .toLowerCase()
                                .contains(_searchQuery) ||
                            (i['code'] as String)
                                .toLowerCase()
                                .contains(_searchQuery))
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                      child: Text('No items match your search.',
                          style: GoogleFonts.poppins(
                              color: AppColors.textSecondary)));
                }

                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final item = filtered[i];
                    final double? half = item['halfPrice'] as double?;
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      decoration: glassCard(radius: 16),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                              gradient: AppGradients.brand,
                              borderRadius: BorderRadius.circular(12)),
                          child: Center(
                            child: Text(
                              item['code'] as String,
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        title: Text(item['name'] as String,
                            style: GoogleFonts.poppins(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            buildBadge(
                                'Full  ₹${(item['fullPrice'] as double).toStringAsFixed(0)}',
                                AppColors.accentGreen),
                            if (half != null && half > 0) ...[
                              const SizedBox(height: 4),
                              buildBadge('Half  ₹${half.toStringAsFixed(0)}',
                                  AppColors.accentOrange),
                            ],
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
