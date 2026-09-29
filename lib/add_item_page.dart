import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';
import 'canteen_provider.dart';

class AddItemPage extends StatefulWidget {
  const AddItemPage({super.key});
  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _fullPriceController = TextEditingController();
  final _halfPriceController = TextEditingController();
  final _searchController = TextEditingController();

  bool _isLoading = false;
  bool _isEditing = false;
  String _editingCode = '';
  String _searchQuery = '';

  // Cached list of existing codes/names for duplicate validation
  List<Map<String, dynamic>> _allItems = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() => setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    _fullPriceController.dispose();
    _halfPriceController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadForEdit(Map<String, dynamic> data) {
    setState(() {
      _isEditing = true;
      _editingCode = data['code'] ?? '';
      _codeController.text = data['code'] ?? '';
      _nameController.text = data['name'] ?? '';
      _fullPriceController.text = (data['fullPrice'] ?? '').toString();
      _halfPriceController.text =
          data['halfPrice'] != null ? data['halfPrice'].toString() : '';
    });
    _tabController.animateTo(1);
  }

  void _clearForm() {
    setState(() {
      _isEditing = false;
      _editingCode = '';
    });
    _formKey.currentState?.reset();
    _codeController.clear();
    _nameController.clear();
    _fullPriceController.clear();
    _halfPriceController.clear();
  }

  String? _validateCode(String? v) {
    if (v == null || v.trim().isEmpty) return 'Item code is required';
    if (_isEditing) return null; // can't change code when editing
    final code = v.toUpperCase().trim();
    final exists = _allItems
        .any((item) => (item['code'] as String? ?? '').toUpperCase() == code);
    if (exists) return 'Item code "$code" already exists';
    return null;
  }

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Item name is required';
    final name = v.trim().toLowerCase();
    final exists = _allItems.any((item) {
      final itemCode = (item['code'] as String? ?? '').toUpperCase();
      // When editing, exclude the current item from duplicate check
      if (_isEditing && itemCode == _editingCode.toUpperCase()) return false;
      return (item['name'] as String? ?? '').toLowerCase() == name;
    });
    if (exists) return 'An item with this name already exists';
    return null;
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final code = _codeController.text.toUpperCase().trim();
      final name = _nameController.text.trim();
      final fullPrice = double.tryParse(_fullPriceController.text) ?? 0.0;
      final halfPrice = double.tryParse(_halfPriceController.text);

      await FirebaseFirestore.instance.collection('menuItems').doc(code).set({
        'code': code,
        'name': name,
        'canteenId': CanteenProvider.selectedCanteenId,
        'canteenName': CanteenProvider.selectedCanteenName,
        'fullPrice': fullPrice,
        if (halfPrice != null && halfPrice > 0) 'halfPrice': halfPrice,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${_isEditing ? "Updated" : "Added"} "$name" successfully!',
              style: GoogleFonts.poppins()),
          backgroundColor: const Color(0xFF1B4332),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        _clearForm();
        _tabController.animateTo(0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: GoogleFonts.poppins()),
          backgroundColor: AppColors.accentRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteItem(String code, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "$name"?',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
            'This item will be permanently removed from the menu. This cannot be undone.',
            style: GoogleFonts.poppins(
                color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentRed,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(context, true),
            child:
                Text('Delete', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('menuItems')
            .doc(code)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('"$name" deleted.', style: GoogleFonts.poppins()),
            backgroundColor: AppColors.accentRed,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error deleting: $e', style: GoogleFonts.poppins()),
            backgroundColor: AppColors.accentRed,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(
        title: 'Manage Menu',
        actions: [
          if (_isEditing)
            TextButton(
              onPressed: _clearForm,
              child: Text('Cancel Edit',
                  style:
                      GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Tab Bar ──────────────────────────────────────
          Container(
            color: AppColors.bgCard,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.accentGreen,
              indicatorWeight: 3,
              labelColor: AppColors.accentGreen,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(
                    icon: Icon(Icons.list_alt_rounded, size: 18),
                    text: 'All Items'),
                Tab(
                    icon: Icon(Icons.add_circle_outline, size: 18),
                    text: 'Add / Edit'),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // ── TAB 1: LIST + SEARCH ──────────────────────
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('menuItems')
                      .where('canteenId',
                          isEqualTo: CanteenProvider.selectedCanteenId)
                      .orderBy('name')
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.accentGreen));
                    }
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.restaurant_menu,
                                  size: 64, color: AppColors.textHint),
                              const SizedBox(height: 16),
                              Text('No menu items yet.',
                                  style: GoogleFonts.poppins(
                                      color: AppColors.textSecondary,
                                      fontSize: 15)),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.accentGreen,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12))),
                                onPressed: () => _tabController.animateTo(1),
                                icon:
                                    const Icon(Icons.add, color: Colors.white),
                                label: Text('Add First Item',
                                    style: GoogleFonts.poppins(
                                        color: Colors.white)),
                              ),
                            ]),
                      );
                    }

                    // Cache items for validation
                    _allItems = snap.data!.docs
                        .map((d) => d.data() as Map<String, dynamic>)
                        .toList();

                    // Filter by search query
                    final filtered = _allItems.where((item) {
                      if (_searchQuery.isEmpty) return true;
                      final code =
                          (item['code'] as String? ?? '').toLowerCase();
                      final name =
                          (item['name'] as String? ?? '').toLowerCase();
                      return code.contains(_searchQuery) ||
                          name.contains(_searchQuery);
                    }).toList();

                    return Column(
                      children: [
                        // Search bar
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: TextField(
                            controller: _searchController,
                            style: GoogleFonts.poppins(
                                color: AppColors.textPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Search by name or code...',
                              hintStyle: GoogleFonts.poppins(
                                  color: AppColors.textHint, fontSize: 13),
                              prefixIcon: const Icon(Icons.search_rounded,
                                  color: AppColors.textHint, size: 20),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded,
                                          color: AppColors.textHint, size: 18),
                                      onPressed: () {
                                        _searchController.clear();
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: AppColors.bgCard,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                    color: AppColors.bgDivider),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                    color: AppColors.bgDivider),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                    color: AppColors.accentGreen, width: 1.5),
                              ),
                            ),
                          ),
                        ),
                        // Item count
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Row(
                            children: [
                              Text(
                                _searchQuery.isEmpty
                                    ? '${_allItems.length} items total'
                                    : '${filtered.length} of ${_allItems.length} results',
                                style: GoogleFonts.poppins(
                                    color: AppColors.textHint, fontSize: 11),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => _tabController.animateTo(1),
                                child: Row(
                                  children: [
                                    const Icon(Icons.add_circle_outline,
                                        color: AppColors.accentGreen, size: 15),
                                    const SizedBox(width: 4),
                                    Text('Add Item',
                                        style: GoogleFonts.poppins(
                                            color: AppColors.accentGreen,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Items list
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.search_off_rounded,
                                          size: 48, color: AppColors.textHint),
                                      const SizedBox(height: 12),
                                      Text('No results for "$_searchQuery"',
                                          style: GoogleFonts.poppins(
                                              color: AppColors.textSecondary,
                                              fontSize: 14)),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) {
                                    final data = filtered[i];
                                    final code = data['code'] ?? '';
                                    final name = data['name'] ?? '';
                                    final fullPrice =
                                        (data['fullPrice'] ?? 0.0).toDouble();
                                    final halfPrice = data['halfPrice'] != null
                                        ? (data['halfPrice']).toDouble()
                                        : null;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      decoration: BoxDecoration(
                                        color: AppColors.bgCard,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                            color: AppColors.bgDivider),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                        child: Row(
                                          children: [
                                            // Code badge
                                            Container(
                                              width: 46,
                                              height: 46,
                                              decoration: BoxDecoration(
                                                gradient: AppGradients.brand,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  code.length > 4
                                                      ? code.substring(0, 4)
                                                      : code,
                                                  style: GoogleFonts.poppins(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 9),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            // Name + prices
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(name,
                                                      style:
                                                          GoogleFonts.poppins(
                                                              color: AppColors
                                                                  .textPrimary,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              fontSize: 14)),
                                                  const SizedBox(height: 4),
                                                  Row(children: [
                                                    _priceBadge(
                                                        'Full ₹${fullPrice.toStringAsFixed(0)}',
                                                        AppColors.accentGreen),
                                                    if (halfPrice != null &&
                                                        halfPrice > 0) ...[
                                                      const SizedBox(width: 6),
                                                      _priceBadge(
                                                          'Half ₹${halfPrice.toStringAsFixed(0)}',
                                                          AppColors
                                                              .accentOrange),
                                                    ],
                                                  ]),
                                                ],
                                              ),
                                            ),
                                            // Actions
                                            Column(
                                              children: [
                                                _iconBtn(
                                                    Icons.edit_rounded,
                                                    AppColors.accentBlue,
                                                    () => _loadForEdit(data)),
                                                const SizedBox(height: 4),
                                                _iconBtn(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    AppColors.accentRed,
                                                    () => _deleteItem(
                                                        code, name)),
                                              ],
                                            ),
                                          ],
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

                // ── TAB 2: ADD / EDIT FORM ────────────────────
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Editing banner
                        if (_isEditing)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.accentBlue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppColors.accentBlue
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.edit_rounded,
                                  color: AppColors.accentBlue, size: 16),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(
                                      'Editing: $_editingCode — code cannot be changed',
                                      style: GoogleFonts.poppins(
                                          color: AppColors.accentBlue,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500))),
                              TextButton(
                                  onPressed: _clearForm,
                                  child: Text('Cancel',
                                      style: GoogleFonts.poppins(
                                          color: AppColors.textSecondary,
                                          fontSize: 11))),
                            ]),
                          ),

                        // Fields
                        _field(
                          controller: _codeController,
                          label: 'Item Code *',
                          icon: Icons.qr_code_rounded,
                          hint: 'e.g. CH01 (unique ID)',
                          enabled: !_isEditing,
                          validator: _validateCode,
                          textCapitalization: TextCapitalization.characters,
                        ),
                        const SizedBox(height: 14),
                        _field(
                          controller: _nameController,
                          label: 'Item Name *',
                          icon: Icons.fastfood_outlined,
                          hint: 'e.g. Chicken Biryani',
                          validator: _validateName,
                        ),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                              child: _field(
                            controller: _fullPriceController,
                            label: 'Full Price (₹) *',
                            icon: Icons.currency_rupee,
                            hint: '0',
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              if (double.tryParse(v) == null) return 'Invalid';
                              return null;
                            },
                          )),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _field(
                            controller: _halfPriceController,
                            label: 'Half Price (₹)',
                            icon: Icons.currency_rupee,
                            hint: 'Optional',
                            keyboardType: TextInputType.number,
                          )),
                        ]),
                        const SizedBox(height: 28),
                        buildGradientButton(
                          label: _isEditing ? 'Update Item' : 'Save Item',
                          icon: _isEditing
                              ? Icons.update_rounded
                              : Icons.save_rounded,
                          isLoading: _isLoading,
                          onPressed: _isLoading ? null : _saveItem,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool enabled = true,
    TextCapitalization textCapitalization = TextCapitalization.words,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled,
      textCapitalization: textCapitalization,
      style: GoogleFonts.poppins(
          color: enabled ? AppColors.textPrimary : AppColors.textSecondary,
          fontSize: 14),
      validator: validator,
      decoration: darkInput(label: label, prefixIcon: icon, hint: hint),
    );
  }

  Widget _priceBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: GoogleFonts.poppins(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}
