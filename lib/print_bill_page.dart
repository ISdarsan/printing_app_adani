import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'theme.dart';

// ─────────────────────────────────────────────────────────────
//  Data Models
// ─────────────────────────────────────────────────────────────

class BillItem {
  final String code, name, type;
  final int quantity;
  final double price;
  BillItem({
    required this.code,
    required this.name,
    required this.type,
    required this.quantity,
    required this.price,
  });
  double get subtotal => price * quantity;
}

class MenuItem {
  final String code, name;
  final double fullPrice;
  final double? halfPrice;
  MenuItem({
    required this.code,
    required this.name,
    required this.fullPrice,
    this.halfPrice,
  });
  factory MenuItem.fromFirestore(Map<String, dynamic> data) {
    return MenuItem(
      code: data['code'] ?? '',
      name: data['name'] ?? '',
      fullPrice: (data['fullPrice'] ?? 0.0).toDouble(),
      halfPrice:
          data['halfPrice'] != null ? (data['halfPrice']).toDouble() : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Page Widget
// ─────────────────────────────────────────────────────────────

class PrintBillPage extends StatefulWidget {
  const PrintBillPage({super.key});
  @override
  State<PrintBillPage> createState() => _PrintBillPageState();
}

class _PrintBillPageState extends State<PrintBillPage> {
  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // State
  List<MenuItem> _fullMenu = [];
  MenuItem? _selectedItem;
  int _quantity = 1;
  bool _isFullPrice = true;
  String _paymentMethod = 'Cash'; // 'Cash' | 'UPI' | 'Credit'

  final List<BillItem> _billItems = [];
  double _totalAmount = 0.0;

  bool _isSaving = false;
  bool _isAdding = false;
  bool _menuLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMenu();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────

  Future<void> _loadMenu() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('menuItems').get();
      setState(() {
        _fullMenu =
            snap.docs.map((d) => MenuItem.fromFirestore(d.data())).toList();
        _menuLoading = false;
      });
    } catch (e) {
      setState(() => _menuLoading = false);
      _snack('Failed to load menu: $e', error: true);
    }
  }

  List<MenuItem> get _suggestions {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return [];
    return _fullMenu
        .where((m) =>
            m.name.toLowerCase().contains(q) ||
            m.code.toLowerCase().contains(q))
        .take(8)
        .toList();
  }

  // ── Bill logic ────────────────────────────────────────────

  void _addItem() {
    if (_selectedItem == null) {
      _snack('Please select an item first.', error: true);
      return;
    }
    final item = _selectedItem!;
    double price;
    String type;
    if (_isFullPrice) {
      price = item.fullPrice;
      type = 'Full';
    } else {
      if (item.halfPrice == null || item.halfPrice! <= 0) {
        _snack('No half price for this item.', error: true);
        return;
      }
      price = item.halfPrice!;
      type = 'Half';
    }
    setState(() {
      _isAdding = true;
      _billItems.add(BillItem(
        code: item.code,
        name: item.name,
        type: type,
        quantity: _quantity,
        price: price,
      ));
      _recalcTotal();
      _searchController.clear();
      _selectedItem = null;
      _quantity = 1;
      _isFullPrice = true;
      _isAdding = false;
    });
    _searchFocus.unfocus();
  }

  void _removeItem(int index) {
    setState(() {
      _billItems.removeAt(index);
      _recalcTotal();
    });
  }

  void _recalcTotal() {
    _totalAmount = _billItems.fold(0.0, (prevSum, i) => prevSum + i.subtotal);
  }

  Future<void> _processSaveBill() async {
    if (_billItems.isEmpty) {
      _snack('Add at least one item first.', error: true);
      return;
    }

    if (_paymentMethod == 'Credit') {
      final result = await _showCreditCustomerDialog();
      if (result == null) return; // cancelled
      await _saveBill(
          customerName: result['name'], customerPhone: result['phone']);
    } else {
      await _saveBill();
    }
  }

  Future<Map<String, String>?> _showCreditCustomerDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    List<Map<String, dynamic>> existingCustomers = [];

    // Fetch existing customers for autocomplete
    try {
      final snap =
          await FirebaseFirestore.instance.collection('creditCustomers').get();
      existingCustomers = snap.docs.map((d) => d.data()).toList();
    } catch (e) {
      // ignore
    }

    if (!mounted) return null;

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: const Color(0xFF111827),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.credit_score_rounded,
                            color: AppColors.accentOrange, size: 28),
                        const SizedBox(width: 12),
                        Text('Credit Customer',
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('Phone Number',
                        style: GoogleFonts.poppins(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Autocomplete<Map<String, dynamic>>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return const Iterable<Map<String, dynamic>>.empty();
                        }
                        return existingCustomers.where((c) {
                          final phone =
                              (c['phone'] ?? '').toString().toLowerCase();
                          final name =
                              (c['name'] ?? '').toString().toLowerCase();
                          final q = textEditingValue.text.toLowerCase();
                          return phone.contains(q) || name.contains(q);
                        });
                      },
                      displayStringForOption: (option) => option['phone'] ?? '',
                      onSelected: (option) {
                        phoneCtrl.text = option['phone'] ?? '';
                        nameCtrl.text = option['name'] ?? '';
                      },
                      fieldViewBuilder: (context, textEditingController,
                          focusNode, onFieldSubmitted) {
                        // sync controllers
                        textEditingController.addListener(() {
                          if (phoneCtrl.text != textEditingController.text) {
                            phoneCtrl.text = textEditingController.text;
                          }
                        });
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 14),
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: 'Enter phone number...',
                            hintStyle: GoogleFonts.poppins(
                                color: AppColors.textHint, fontSize: 14),
                            filled: true,
                            fillColor: AppColors.bgInput,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (v.length != 10 || int.tryParse(v) == null) {
                              return 'Enter 10-digit number';
                            }
                            return null;
                          },
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              width: 280,
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                color: AppColors.bgCard,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: AppColors.glassBorder),
                              ),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(
                                        color: AppColors.glassBorder,
                                        height: 1),
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return ListTile(
                                    title: Text(option['name'] ?? '',
                                        style: GoogleFonts.poppins(
                                            color: Colors.white, fontSize: 14)),
                                    subtitle: Text(option['phone'] ?? '',
                                        style: GoogleFonts.poppins(
                                            color: AppColors.textHint,
                                            fontSize: 12)),
                                    onTap: () => onSelected(option),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Text('Customer Name',
                        style: GoogleFonts.poppins(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: nameCtrl,
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Enter name...',
                        hintStyle: GoogleFonts.poppins(
                            color: AppColors.textHint, fontSize: 14),
                        filled: true,
                        fillColor: AppColors.bgInput,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: Text('Cancel',
                                style: GoogleFonts.poppins(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentOrange,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              if (formKey.currentState!.validate()) {
                                final enteredPhone = phoneCtrl.text.trim();
                                final customer = existingCustomers.firstWhere(
                                    (c) => c['phone'] == enteredPhone,
                                    orElse: () => <String, dynamic>{});
                                final double currentPending = (customer['totalPending'] ?? 0.0).toDouble();
                                const double maxCreditLimit = 2000.0;
                                if (currentPending + _totalAmount > maxCreditLimit) {
                                  showDialog(
                                    context: context,
                                    builder: (dialogCtx) => AlertDialog(
                                      backgroundColor: const Color(0xFF111827),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      title: Text('Credit Limit Exceeded',
                                          style: GoogleFonts.poppins(
                                              color: AppColors.accentRed,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16)),
                                      content: Text(
                                        'Customer has a pending credit of ₹${currentPending.toStringAsFixed(2)}.\n'
                                        'Adding this bill (₹${_totalAmount.toStringAsFixed(2)}) would exceed the maximum limit of ₹${maxCreditLimit.toStringAsFixed(0)}.\n\n'
                                        'Please collect a repayment before processing new credit.',
                                        style: GoogleFonts.poppins(
                                            color: AppColors.textSecondary, fontSize: 13),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogCtx),
                                          child: Text('OK',
                                              style: GoogleFonts.poppins(
                                                  color: AppColors.accentBlue,
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  );
                                  return;
                                }

                                Navigator.pop(context, {
                                  'name': nameCtrl.text.trim(),
                                  'phone': enteredPhone,
                                });
                              }
                            },
                            child: Text('Confirm',
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _saveBill({String? customerName, String? customerPhone}) async {
    setState(() => _isSaving = true);
    final db = FirebaseFirestore.instance;
    try {
      await db.runTransaction((tx) async {
        final counterRef = db.collection('counters').doc('billCounter');
        final counterSnap = await tx.get(counterRef);
        int newBillNum = counterSnap.exists
            ? (counterSnap.data()!['lastNumber'] as int) + 1
            : 1;
        final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final billRef = db.collection('bills').doc();
        final statRef = db.collection('dailyStats').doc(todayId);

        Map<String, dynamic> billData = {
          'billNumber': newBillNum,
          'totalAmount': _totalAmount,
          'paymentMode': _paymentMethod,
          'timestamp': FieldValue.serverTimestamp(),
          'items': _billItems
              .map((i) => {
                    'code': i.code,
                    'name': i.name,
                    'type': i.type,
                    'quantity': i.quantity,
                    'price': i.price,
                    'subtotal': i.subtotal,
                  })
              .toList(),
        };

        if (_paymentMethod == 'Credit' && customerPhone != null) {
          billData['customerName'] = customerName;
          billData['customerPhone'] = customerPhone;
          billData['creditStatus'] = 'Pending';
          billData['pendingAmount'] = _totalAmount;

          final customerRef =
              db.collection('creditCustomers').doc(customerPhone);
          final customerSnap = await tx.get(customerRef);
          if (customerSnap.exists) {
            tx.update(customerRef, {
              'totalPending': FieldValue.increment(_totalAmount),
              'lastUpdated': FieldValue.serverTimestamp(),
              'name': customerName, // update name just in case
            });
          } else {
            tx.set(customerRef, {
              'phone': customerPhone,
              'name': customerName,
              'totalPending': _totalAmount,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
          }
        }

        tx.set(billRef, billData);

        tx.set(
          statRef,
          {
            'totalSales': FieldValue.increment(_totalAmount),
            'totalBills': FieldValue.increment(1),
            if (_paymentMethod == 'Cash')
              'totalCash': FieldValue.increment(_totalAmount),
            if (_paymentMethod == 'UPI')
              'totalUpi': FieldValue.increment(_totalAmount),
            if (_paymentMethod == 'Credit')
              'totalCredit': FieldValue.increment(_totalAmount),
            'lastUpdated': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        tx.set(counterRef, {'lastNumber': newBillNum});
      });

      _snack(
          '✓ Bill saved! ₹${_totalAmount.toStringAsFixed(2)} · $_paymentMethod');
      setState(() {
        _billItems.clear();
        _recalcTotal();
        _paymentMethod = 'Cash';
        _searchController.clear();
        _selectedItem = null;
        _quantity = 1;
        _isFullPrice = true;
      });
    } catch (e) {
      _snack('Error saving bill: $e', error: true);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmClear() async {
    if (_billItems.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear Bill?',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove all ${_billItems.length} item(s)?',
          style:
              GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 14),
        ),
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
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Clear All',
                style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _billItems.clear();
        _recalcTotal();
        _paymentMethod = 'Cash';
        _searchController.clear();
        _selectedItem = null;
        _quantity = 1;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
      backgroundColor: error ? AppColors.accentRed : const Color(0xFF1B4332),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.bgDark,
        resizeToAvoidBottomInset: false,
        appBar: buildGradientAppBar(
          title: 'New Bill',
          actions: [
            if (_billItems.isNotEmpty)
              IconButton(
                onPressed: _confirmClear,
                icon: const Icon(Icons.delete_sweep_rounded,
                    color: Colors.white70),
                tooltip: 'Clear Bill',
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // ── Top: Add Item Panel ──
              _AddItemPanel(
                searchController: _searchController,
                searchFocus: _searchFocus,
                suggestions: _suggestions,
                selectedItem: _selectedItem,
                isFullPrice: _isFullPrice,
                quantity: _quantity,
                isAdding: _isAdding,
                menuLoading: _menuLoading,
                onItemSelected: (item) {
                  setState(() {
                    _selectedItem = item;
                    _searchController.text = '${item.code} - ${item.name}';
                  });
                  _searchFocus.unfocus();
                },
                onTogglePrice: (isFull) =>
                    setState(() => _isFullPrice = isFull),
                onIncrement: () => setState(() => _quantity++),
                onDecrement: () {
                  if (_quantity > 1) setState(() => _quantity--);
                },
                onAdd: _addItem,
              ),

              // ── Middle: Cart Header ──
              _CartHeader(count: _billItems.length),

              // ── Scrollable Cart ──
              Expanded(
                child: _billItems.isEmpty
                    ? _EmptyCart()
                    : _CartList(
                        items: _billItems,
                        onRemove: _removeItem,
                      ),
              ),

              // ── Bottom: Payment + Actions ──
              _BottomPanel(
                total: _totalAmount,
                paymentMethod: _paymentMethod,
                isSaving: _isSaving,
                hasItems: _billItems.isNotEmpty,
                onPaymentChanged: (m) => setState(() => _paymentMethod = m),
                onSave: _processSaveBill,
                onClear: _confirmClear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  _AddItemPanel
// ─────────────────────────────────────────────────────────────

class _AddItemPanel extends StatelessWidget {
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final List<MenuItem> suggestions;
  final MenuItem? selectedItem;
  final bool isFullPrice;
  final int quantity;
  final bool isAdding;
  final bool menuLoading;
  final ValueChanged<MenuItem> onItemSelected;
  final ValueChanged<bool> onTogglePrice;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onAdd;

  const _AddItemPanel({
    required this.searchController,
    required this.searchFocus,
    required this.suggestions,
    required this.selectedItem,
    required this.isFullPrice,
    required this.quantity,
    required this.isAdding,
    required this.menuLoading,
    required this.onItemSelected,
    required this.onTogglePrice,
    required this.onIncrement,
    required this.onDecrement,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search field + dropdown overlay using Stack
          _SearchField(
            controller: searchController,
            focusNode: searchFocus,
            suggestions: suggestions,
            menuLoading: menuLoading,
            onItemSelected: onItemSelected,
          ),
          const SizedBox(height: 12),
          // Qty + Full/Half + Add Button row
          Row(
            children: [
              // Quantity stepper
              _QtyStepper(
                value: quantity,
                onInc: onIncrement,
                onDec: onDecrement,
              ),
              const SizedBox(width: 10),
              // Full / Half toggle
              _PriceToggle(
                isFull: isFullPrice,
                onToggle: onTogglePrice,
              ),
              const SizedBox(width: 10),
              // Add button
              Expanded(
                flex: 3,
                child: _AddButton(isAdding: isAdding, onAdd: onAdd),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  _SearchField — custom dropdown (no Autocomplete widget issues)
// ─────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<MenuItem> suggestions;
  final bool menuLoading;
  final ValueChanged<MenuItem> onItemSelected;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.menuLoading,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          style: GoogleFonts.poppins(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: menuLoading
                ? 'Loading menu...'
                : 'Search by item code or name…',
            hintStyle:
                GoogleFonts.poppins(color: AppColors.textHint, fontSize: 14),
            filled: true,
            fillColor: AppColors.bgInput,
            prefixIcon: const Icon(Icons.search_rounded,
                color: AppColors.textSecondary, size: 22),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded,
                        color: AppColors.textHint, size: 20),
                    onPressed: () => controller.clear(),
                  )
                : (menuLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accentBlue),
                        ),
                      )
                    : null),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: AppColors.gradBlue, width: 1.5),
            ),
          ),
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2235),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4), blurRadius: 16)
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: suggestions.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: AppColors.glassBorder, height: 1),
                itemBuilder: (_, i) {
                  final item = suggestions[i];
                  return InkWell(
                    onTap: () => onItemSelected(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.gradBlue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(item.code,
                                style: GoogleFonts.poppins(
                                    color: AppColors.accentBlue,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(item.name,
                                style: GoogleFonts.poppins(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '₹${item.fullPrice.toStringAsFixed(0)}',
                            style: GoogleFonts.poppins(
                                color: AppColors.accentGreen,
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  _QtyStepper
// ─────────────────────────────────────────────────────────────

class _QtyStepper extends StatelessWidget {
  final int value;
  final VoidCallback onInc;
  final VoidCallback onDec;

  const _QtyStepper({
    required this.value,
    required this.onInc,
    required this.onDec,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepBtn(icon: Icons.remove, onTap: onDec),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '$value',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
          ),
          _StepBtn(icon: Icons.add, onTap: onInc, isAdd: true),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isAdd;
  const _StepBtn({required this.icon, required this.onTap, this.isAdd = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 36,
          height: 46,
          child: Icon(icon,
              size: 18,
              color: isAdd ? AppColors.accentGreen : AppColors.textSecondary),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  _PriceToggle
// ─────────────────────────────────────────────────────────────

class _PriceToggle extends StatelessWidget {
  final bool isFull;
  final ValueChanged<bool> onToggle;

  const _PriceToggle({required this.isFull, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleTab(
              label: 'Full', active: isFull, onTap: () => onToggle(true)),
          _ToggleTab(
              label: 'Half', active: !isFull, onTap: () => onToggle(false)),
        ],
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleTab(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.gradBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: active ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  _AddButton
// ─────────────────────────────────────────────────────────────

class _AddButton extends StatelessWidget {
  final bool isAdding;
  final VoidCallback onAdd;
  const _AddButton({required this.isAdding, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isAdding ? null : onAdd,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          gradient: isAdding ? null : AppGradients.brand,
          color: isAdding ? AppColors.bgInput : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: isAdding
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_shopping_cart_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text('Add',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  _CartHeader
// ─────────────────────────────────────────────────────────────

class _CartHeader extends StatelessWidget {
  final int count;
  const _CartHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgDark,
        border: Border(
          top: BorderSide(color: AppColors.bgDivider),
          bottom: BorderSide(color: AppColors.bgDivider),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded,
              color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 8),
          Text(
            'Current Order',
            style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const Spacer(),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count item${count > 1 ? 's' : ''}',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentBlue),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  _EmptyCart
// ─────────────────────────────────────────────────────────────

class _EmptyCart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: const Icon(Icons.shopping_cart_outlined,
                size: 44, color: AppColors.textHint),
          ),
          const SizedBox(height: 18),
          Text('Your cart is empty',
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text('Search and add items above',
              style:
                  GoogleFonts.poppins(fontSize: 13, color: AppColors.textHint)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  _CartList
// ─────────────────────────────────────────────────────────────

class _CartList extends StatelessWidget {
  final List<BillItem> items;
  final ValueChanged<int> onRemove;

  const _CartList({required this.items, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final isHalf = item.type == 'Half';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Qty badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.gradBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${item.quantity}×',
                    style: GoogleFonts.poppins(
                        color: AppColors.accentBlue,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              const SizedBox(width: 12),
              // Name + details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.name,
                        style: GoogleFonts.poppins(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text('₹${item.price.toStringAsFixed(0)} each',
                            style: GoogleFonts.poppins(
                                color: AppColors.textSecondary, fontSize: 11)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isHalf
                                ? AppColors.accentOrange.withValues(alpha: 0.15)
                                : AppColors.accentGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(item.type,
                              style: GoogleFonts.poppins(
                                  color: isHalf
                                      ? AppColors.accentOrange
                                      : AppColors.accentGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Subtotal
              Text('₹${item.subtotal.toStringAsFixed(0)}',
                  style: GoogleFonts.poppins(
                      color: AppColors.accentGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              const SizedBox(width: 8),
              // Remove
              GestureDetector(
                onTap: () => onRemove(i),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.accentRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.accentRed, size: 16),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  _BottomPanel
// ─────────────────────────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  final double total;
  final String paymentMethod;
  final bool isSaving;
  final bool hasItems;
  final ValueChanged<String> onPaymentChanged;
  final VoidCallback onSave;
  final VoidCallback onClear;

  const _BottomPanel({
    required this.total,
    required this.paymentMethod,
    required this.isSaving,
    required this.hasItems,
    required this.onPaymentChanged,
    required this.onSave,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 30,
              offset: const Offset(0, -10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.glassBorder,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // Total row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GRAND TOTAL',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textHint,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 2),
                  Text(
                    '₹${total.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accentGreen,
                        height: 1.0),
                  ),
                ],
              ),
              // Item count badge
              if (hasItems)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accentGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.accentGreen.withValues(alpha: 0.3)),
                  ),
                  child: Text('Bill Ready',
                      style: GoogleFonts.poppins(
                          color: AppColors.accentGreen,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Payment method selector
          Row(
            children: [
              Text('Pay via',
                  style: GoogleFonts.poppins(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    _PayBtn(
                        label: 'Cash',
                        icon: Icons.payments_rounded,
                        active: paymentMethod == 'Cash',
                        color: const Color(0xFF00C853),
                        onTap: () => onPaymentChanged('Cash')),
                    const SizedBox(width: 8),
                    _PayBtn(
                        label: 'UPI',
                        icon: Icons.qr_code_scanner_rounded,
                        active: paymentMethod == 'UPI',
                        color: AppColors.accentBlue,
                        onTap: () => onPaymentChanged('UPI')),
                    const SizedBox(width: 8),
                    _PayBtn(
                        label: 'Credit',
                        icon: Icons.credit_score_rounded,
                        active: paymentMethod == 'Credit',
                        color: AppColors.accentOrange,
                        onTap: () => onPaymentChanged('Credit')),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              // Clear button
              OutlinedButton(
                onPressed: hasItems ? onClear : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accentRed,
                  side: BorderSide(
                      color:
                          hasItems ? AppColors.accentRed : AppColors.textHint),
                  minimumSize: const Size(56, 54),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Icon(Icons.delete_outline_rounded, size: 22),
              ),
              const SizedBox(width: 12),
              // Save & Print button
              Expanded(
                child: _SaveButton(
                    isSaving: isSaving, enabled: hasItems, onSave: onSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  _PayBtn
// ─────────────────────────────────────────────────────────────

class _PayBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _PayBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.18) : AppColors.bgInput,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? color : AppColors.glassBorder,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: active ? color : AppColors.textHint, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.poppins(
                    color: active ? color : AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  _SaveButton
// ─────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  final bool isSaving;
  final bool enabled;
  final VoidCallback onSave;

  const _SaveButton({
    required this.isSaving,
    required this.enabled,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled && !isSaving ? onSave : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        decoration: BoxDecoration(
          gradient: enabled && !isSaving ? AppGradients.brand : null,
          color: enabled ? null : AppColors.bgInput,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled && !isSaving
              ? [
                  BoxShadow(
                      color: AppColors.gradBlue.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6)),
                ]
              : [],
        ),
        child: Center(
          child: isSaving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.print_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text('Save & Print',
                        style: GoogleFonts.poppins(
                            color: enabled ? Colors.white : AppColors.textHint,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                  ],
                ),
        ),
      ),
    );
  }
}
