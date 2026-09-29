import 'dart:async';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'canteen_provider.dart';

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

int normalizeBillQuantity(dynamic value) {
  final qty = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (qty == null || qty <= 0) return 1;
  return qty;
}

List<BillItem> mergeBillItems(List<BillItem> items) {
  final merged = <String, BillItem>{};
  for (final item in items) {
    final key = '${item.code}|${item.type}';
    final existing = merged[key];
    if (existing == null) {
      merged[key] = BillItem(
        code: item.code,
        name: item.name,
        type: item.type,
        quantity: normalizeBillQuantity(item.quantity),
        price: item.price,
      );
      continue;
    }
    merged[key] = BillItem(
      code: existing.code,
      name: existing.name,
      type: existing.type,
      quantity: normalizeBillQuantity(existing.quantity + item.quantity),
      price: existing.price,
    );
  }
  return merged.values.toList();
}

// ─────────────────────────────────────────────────────────────
//  ESC/POS Receipt Builder  (matches KPC307-UEWB 80mm printer)
//  Format mirrors the receipt photo:
//    VIZMART                  ← bold, centered
//    Date: DD/MM/YYYY HH:MM
//    Bill No: BILL-YYYYMMDDHHMMSS
//    ────────────────────────
//    Item       Qty  Price  Total
//    ────────────────────────
//    Chicken...   2  120.0  240.0
//    ────────────────────────
//    TOTAL              Rs. XXX.XX
//    Payment Mode: Cash
//    ────────────────────────
//         Thank you! Visit again.
// ─────────────────────────────────────────────────────────────

Future<List<int>> buildEscPosReceipt({
  required String billId,
  required List<BillItem> items,
  required double totalAmount,
  required String paymentMode,
  required String canteenName,
  String? customerName,
  String? customerPhone,
}) async {
  final profile = await CapabilityProfile.load();
  final generator = Generator(PaperSize.mm80, profile);
  var bytes = <int>[];

  final now = DateTime.now();
  final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(now);

  // ── Header ──
  bytes += generator.text(
    'VIZMART',
    styles: const PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
      width: PosTextSize.size1,
    ),
  );
  bytes += generator.text(
    'Branch - $canteenName',
    styles: const PosStyles(align: PosAlign.center, bold: true),
  );
  bytes += generator.text(
    'Date: $dateStr',
    styles: const PosStyles(align: PosAlign.center),
  );
  bytes += generator.text(
    'Bill No: $billId',
    styles: const PosStyles(align: PosAlign.center),
  );

  if ((customerName ?? '').isNotEmpty) {
    bytes += generator.text('Customer: $customerName');
  }
  if ((customerPhone ?? '').isNotEmpty) {
    bytes += generator.text('Phone: $customerPhone');
  }

  bytes += generator.hr();

  // ── Column Headers ──
  // 80mm @ 48 chars wide: Item(20) Qty(5) Price(9) Total(9)  + separators
  bytes += generator.row([
    PosColumn(
      text: 'Item',
      width: 6,
      styles: const PosStyles(bold: true, align: PosAlign.left),
    ),
    PosColumn(
      text: 'Qty',
      width: 2,
      styles: const PosStyles(bold: true, align: PosAlign.center),
    ),
    PosColumn(
      text: 'Price',
      width: 2,
      styles: const PosStyles(bold: true, align: PosAlign.right),
    ),
    PosColumn(
      text: 'Total',
      width: 2,
      styles: const PosStyles(bold: true, align: PosAlign.right),
    ),
  ]);

  bytes += generator.hr();

  // ── Line Items ──
  for (final item in items) {
    final displayName = item.type == 'Half'
        ? '${item.name}(H)'
        : item.name;
    bytes += generator.row([
      PosColumn(
        text: displayName,
        width: 6,
        styles: const PosStyles(align: PosAlign.left),
      ),
      PosColumn(
        text: '${item.quantity}',
        width: 2,
        styles: const PosStyles(align: PosAlign.center),
      ),
      PosColumn(
        text: item.price.toStringAsFixed(1),
        width: 2,
        styles: const PosStyles(align: PosAlign.right),
      ),
      PosColumn(
        text: item.subtotal.toStringAsFixed(1),
        width: 2,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
  }

  bytes += generator.hr();

  // ── Total ──
  bytes += generator.row([
    PosColumn(
      text: 'TOTAL',
      width: 5,
      styles: const PosStyles(bold: true, align: PosAlign.left),
    ),
    PosColumn(
      text: 'Rs. ${totalAmount.toStringAsFixed(2)}',
      width: 7,
      styles: const PosStyles(bold: true, align: PosAlign.right),
    ),
  ]);

  bytes += generator.text('Payment Mode: $paymentMode');

  bytes += generator.hr();

  // ── Footer ──
  bytes += generator.text(
    'Thank you! Visit again.',
    styles: const PosStyles(align: PosAlign.center),
  );
  bytes += generator.feed(2);
  bytes += generator.cut();

  return bytes;
}

// ─────────────────────────────────────────────────────────────
//  Printer Connection Status enum
// ─────────────────────────────────────────────────────────────

enum _PrinterStatus { notInitialized, scanning, noBluetooth, noDevice, disconnected, connecting, connected }

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

  // Menu State
  List<MenuItem> _fullMenu = [];
  MenuItem? _selectedItem;
  int _quantity = 1;
  bool _isFullPrice = true;
  String _paymentMethod = 'Cash';

  // Bill State
  final List<BillItem> _billItems = [];
  double _totalAmount = 0.0;
  bool _isSaving = false;
  bool _isAdding = false;
  bool _menuLoading = true;

  // ── Printer State ──
  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;
  List<BluetoothDevice> _bondedDevices = [];
  BluetoothDevice? _selectedPrinter;
  _PrinterStatus _printerStatus = _PrinterStatus.notInitialized;
  bool _isPrinting = false;



  @override
  void initState() {
    super.initState();
    _loadMenu();
    _initPrinter();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  //  Production-Grade Printer Management
  // ─────────────────────────────────────────────────────────────

  Future<void> _initPrinter() async {
    try {
      final isConnected = await _printer.isConnected ?? false;
      if (isConnected) {
        final devices = await _printer.getBondedDevices();
        if (mounted) {
          setState(() {
            _bondedDevices = devices;
            _selectedPrinter = _pickBestDevice(devices);
            _printerStatus = _PrinterStatus.connected;
          });
        }
      } else {
        final devices = await _printer.getBondedDevices();
        if (mounted) {
          setState(() {
            _bondedDevices = devices;
            if (devices.isNotEmpty) {
              _selectedPrinter = _pickBestDevice(devices);
            }
            _printerStatus = _PrinterStatus.disconnected;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _printerStatus = _PrinterStatus.disconnected);
    }
  }

  /// Triggers user action to connect: check Bluetooth status and present device sheet
  Future<void> _startPrinterSetup() async {
    try {
      final available = await _printer.isAvailable ?? false;
      final isOn = await _printer.isOn ?? false;

      if (!available || !isOn) {
        if (mounted) setState(() => _printerStatus = _PrinterStatus.noBluetooth);
        _snack('Bluetooth is OFF. Please turn on Bluetooth in settings.', error: true);
        await _showPrinterSheet();
        return;
      }

      final devices = await _printer.getBondedDevices();
      if (!mounted) return;

      setState(() {
        _bondedDevices = devices;
        if (devices.isNotEmpty) {
          _selectedPrinter ??= _pickBestDevice(devices);
        }
        _printerStatus = devices.isEmpty ? _PrinterStatus.noDevice : _PrinterStatus.disconnected;
      });

      await _showPrinterSheet();
    } catch (e) {
      if (mounted) {
        setState(() => _printerStatus = _PrinterStatus.disconnected);
        _snack('Bluetooth error: $e', error: true);
      }
      await _showPrinterSheet();
    }
  }

  /// Selects preferred thermal printer model or falls back to first paired device
  BluetoothDevice _pickBestDevice(List<BluetoothDevice> devices) {
    return devices.firstWhere(
      (d) =>
          (d.name ?? '').toUpperCase().contains('KPC') ||
          (d.name ?? '').toUpperCase().contains('POS') ||
          (d.name ?? '').toUpperCase().contains('PRINTER') ||
          (d.name ?? '').toUpperCase().contains('THERMAL') ||
          (d.name ?? '').toUpperCase().contains('BT'),
      orElse: () => devices.first,
    );
  }

  Future<void> _connectToPrinter() async {
    if (_selectedPrinter == null) {
      await _startPrinterSetup();
      return;
    }
    setState(() => _printerStatus = _PrinterStatus.connecting);
    try {
      // Disconnect if previously connected to avoid socket lock
      try { await _printer.disconnect(); } catch (_) {}

      final result = await _printer.connect(_selectedPrinter!);
      final connected = result == 'true' || result == true;
      if (!mounted) return;
      
      setState(() => _printerStatus =
          connected ? _PrinterStatus.connected : _PrinterStatus.disconnected);
          
      if (connected) {
        _snack('✓ Connected to ${_selectedPrinter!.name ?? "Printer"}');
      } else {
        _snack('Could not connect to ${_selectedPrinter!.name ?? "Printer"}. Retrying...', error: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _printerStatus = _PrinterStatus.disconnected);
        _snack('Connection failed: $e', error: true);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Printer Connection Modal Sheet
  // ─────────────────────────────────────────────────────────────

  Future<void> _showPrinterSheet() async {
    try {
      final devices = await _printer.getBondedDevices();
      if (mounted) setState(() => _bondedDevices = devices);
    } catch (_) {}

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          return _PrinterSheet(
            devices: _bondedDevices,
            selectedDevice: _selectedPrinter,
            printerStatus: _printerStatus,
            onSelect: (device) async {
              setModalState(() {
                _selectedPrinter = device;
                _printerStatus = _PrinterStatus.connecting;
              });
              setState(() {
                _selectedPrinter = device;
              });
              Navigator.pop(ctx);
              await _connectToPrinter();
            },
            onRefresh: () async {
              try {
                final devs = await _printer.getBondedDevices();
                setModalState(() {
                  _bondedDevices = devs;
                });
                if (mounted) {
                  setState(() {
                    _bondedDevices = devs;
                  });
                }
              } catch (_) {}
            },
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Receipt Printing
  // ─────────────────────────────────────────────────────────────

  Future<void> _printReceipt({
    required String billId,
    required List<BillItem> items,
    required double totalAmount,
    required String paymentMode,
    String? customerName,
    String? customerPhone,
  }) async {
    if (items.isEmpty) {
      _snack('No items to print.', error: true);
      return;
    }

    setState(() => _isPrinting = true);
    try {
      // 1. Ensure Bluetooth is ON and bonded devices are available
      final isAvailable = await _printer.isAvailable ?? false;
      final isOn = await _printer.isOn ?? false;
      if (!isAvailable || !isOn) {
        _snack('Bluetooth is OFF. Please turn on Bluetooth to print.', error: true);
        return;
      }

      // 2. Fetch bonded devices if no printer selected yet
      if (_selectedPrinter == null || _bondedDevices.isEmpty) {
        final devices = await _printer.getBondedDevices();
        if (devices.isEmpty) {
          _snack('No paired thermal printers found. Pair printer in Bluetooth settings.', error: true);
          return;
        }
        _bondedDevices = devices;
        _selectedPrinter = _pickBestDevice(devices);
      }

      // 3. Connect to printer if not already connected
      final isConnected = await _printer.isConnected ?? false;
      if (!isConnected) {
        _snack('Connecting to ${_selectedPrinter!.name ?? "Printer"}...');
        try { await _printer.disconnect(); } catch (_) {}
        final result = await _printer.connect(_selectedPrinter!);
        final connected = result == 'true' || result == true;
        if (!connected) {
          throw Exception('Could not connect to ${_selectedPrinter!.name ?? "Printer"}');
        }
        if (mounted) setState(() => _printerStatus = _PrinterStatus.connected);
      }

      // 4. Build ESC/POS receipt bytes
      final bytes = await buildEscPosReceipt(
        billId: billId,
        items: items,
        totalAmount: totalAmount,
        paymentMode: paymentMode,
        canteenName: CanteenProvider.selectedCanteenName,
        customerName: customerName,
        customerPhone: customerPhone,
      );

      // 5. Send raw bytes to thermal printer
      await _printer.writeBytes(Uint8List.fromList(bytes));
      _snack('✓ Receipt printed successfully.');
    } catch (e) {
      if (mounted) setState(() => _printerStatus = _PrinterStatus.disconnected);
      _snack('Print failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Menu
  // ─────────────────────────────────────────────────────────────

  Future<void> _loadMenu() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('menuItems').get();
      final items = snap.docs
          .map((d) => MenuItem.fromFirestore(d.data()))
          .where((m) => m.name.isNotEmpty)
          .toList();
      if (mounted) {
        setState(() {
          _fullMenu = items;
          _menuLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _menuLoading = false);
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

  // ─────────────────────────────────────────────────────────────
  //  Bill Logic
  // ─────────────────────────────────────────────────────────────

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
    final qty = normalizeBillQuantity(_quantity);
    setState(() {
      _isAdding = true;
      final existingIndex = _billItems.indexWhere(
        (e) => e.code == item.code && e.type == type,
      );
      if (existingIndex >= 0) {
        final existing = _billItems[existingIndex];
        _billItems[existingIndex] = BillItem(
          code: existing.code,
          name: existing.name,
          type: existing.type,
          quantity: normalizeBillQuantity(existing.quantity + qty),
          price: existing.price,
        );
      } else {
        _billItems.add(BillItem(
          code: item.code,
          name: item.name,
          type: type,
          quantity: qty,
          price: price,
        ));
      }
      _recalcTotal();
      _searchController.clear();
      _selectedItem = null;
      _quantity = 1;
      _isFullPrice = true;
      _isAdding = false;
    });
    _searchFocus.unfocus();
  }

  void _removeItem(int index) => setState(() {
        _billItems.removeAt(index);
        _recalcTotal();
      });

  void _recalcTotal() =>
      _totalAmount = _billItems.fold(0.0, (s, i) => s + i.subtotal);

  // ─────────────────────────────────────────────────────────────
  //  Save + Print Bill
  // ─────────────────────────────────────────────────────────────

  Future<void> _processSaveBill() async {
    if (_billItems.isEmpty) {
      _snack('Add at least one item first.', error: true);
      return;
    }

    final billItemsSnapshot = List<BillItem>.from(_billItems);
    final totalSnapshot = _totalAmount;
    final paymentSnapshot = _paymentMethod;
    String? customerName, customerPhone;

    if (_paymentMethod == 'Credit') {
      final result = await _showCreditCustomerDialog();
      if (result == null) return;
      customerName = result['name'];
      customerPhone = result['phone'];
    }

    final billId = await _saveBill(
      customerName: customerName,
      customerPhone: customerPhone,
    );

    if (billId != null) {
      await _printReceipt(
        billId: billId,
        items: billItemsSnapshot,
        totalAmount: totalSnapshot,
        paymentMode: paymentSnapshot,
        customerName: customerName,
        customerPhone: customerPhone,
      );
    }
  }

  /// Returns the generated bill ID (e.g. "BILL-20260915170112") or null on failure.
  Future<String?> _saveBill({
    String? customerName,
    String? customerPhone,
  }) async {
    setState(() => _isSaving = true);
    final db = FirebaseFirestore.instance;
    String? generatedBillId;
    try {
      await db.runTransaction((tx) async {
        final counterRef = db.collection('counters').doc('billCounter');
        final counterSnap = await tx.get(counterRef);
        final newBillNum = counterSnap.exists
            ? (counterSnap.data()!['lastNumber'] as int) + 1
            : 38;
        final selectedCanteenId = CanteenProvider.selectedCanteenId;
        final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final billRef = db.collection('bills').doc();

        // Generate a bill ID like "BILL-20260915170112"
        final now = DateTime.now();
        final ts = DateFormat('yyyyMMddHHmmss').format(now);
        generatedBillId = 'BILL-$ts${newBillNum.toString().padLeft(2, '0')}';

        final statRef = db.collection('dailyStats').doc(todayId);

        final billData = <String, dynamic>{
          'billId': generatedBillId,
          'billNumber': newBillNum,
          'canteenId': selectedCanteenId,
          'canteenName': CanteenProvider.selectedCanteenName,
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
              'name': customerName,
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
            'canteenId': selectedCanteenId,
            'canteenName': CanteenProvider.selectedCanteenName,
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

      _snack('✓ Bill saved! ₹${_totalAmount.toStringAsFixed(2)} · $_paymentMethod');
      setState(() {
        _billItems.clear();
        _recalcTotal();
        _paymentMethod = 'Cash';
        _searchController.clear();
        _selectedItem = null;
        _quantity = 1;
        _isFullPrice = true;
      });
      return generatedBillId;
    } catch (e) {
      _snack('Error saving bill: $e', error: true);
      return null;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Credit Customer Dialog
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, String>?> _showCreditCustomerDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    List<Map<String, dynamic>> existingCustomers = [];

    try {
      final snap =
          await FirebaseFirestore.instance.collection('creditCustomers').get();
      existingCustomers = snap.docs.map((d) => d.data()).toList();
    } catch (_) {}

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
                    Row(children: [
                      const Icon(Icons.credit_score_rounded,
                          color: AppColors.accentOrange, size: 28),
                      const SizedBox(width: 12),
                      Text('Credit Customer',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 24),
                    Text('Phone Number',
                        style: GoogleFonts.poppins(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Autocomplete<Map<String, dynamic>>(
                      optionsBuilder: (TextEditingValue tv) {
                        if (tv.text.isEmpty) return const [];
                        return existingCustomers.where((c) {
                          final phone = (c['phone'] ?? '').toString().toLowerCase();
                          final name = (c['name'] ?? '').toString().toLowerCase();
                          final q = tv.text.toLowerCase();
                          return phone.contains(q) || name.contains(q);
                        });
                      },
                      displayStringForOption: (o) => o['phone'] ?? '',
                      onSelected: (o) {
                        phoneCtrl.text = o['phone'] ?? '';
                        nameCtrl.text = o['name'] ?? '';
                      },
                      fieldViewBuilder:
                          (context, textCtrl, focusNode, onFieldSubmitted) {
                        textCtrl.addListener(() {
                          if (phoneCtrl.text != textCtrl.text) {
                            phoneCtrl.text = textCtrl.text;
                          }
                        });
                        return TextFormField(
                          controller: textCtrl,
                          focusNode: focusNode,
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 14),
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: 'Enter phone number…',
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
                                border: Border.all(color: AppColors.glassBorder),
                              ),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                separatorBuilder: (_, __) => const Divider(
                                    color: AppColors.glassBorder, height: 1),
                                itemBuilder: (_, i) {
                                  final o = options.elementAt(i);
                                  return ListTile(
                                    title: Text(o['name'] ?? '',
                                        style: GoogleFonts.poppins(
                                            color: Colors.white, fontSize: 14)),
                                    subtitle: Text(o['phone'] ?? '',
                                        style: GoogleFonts.poppins(
                                            color: AppColors.textHint,
                                            fontSize: 12)),
                                    onTap: () => onSelected(o),
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
                      style:
                          GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Enter name…',
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
                    Row(children: [
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
                              final double currentPending =
                                  (customer['totalPending'] ?? 0.0).toDouble();
                              const double maxCreditLimit = 2000.0;
                              if (currentPending + _totalAmount > maxCreditLimit) {
                                showDialog(
                                  context: context,
                                  builder: (dCtx) => AlertDialog(
                                    backgroundColor: const Color(0xFF111827),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20)),
                                    title: Text('Credit Limit Exceeded',
                                        style: GoogleFonts.poppins(
                                            color: AppColors.accentRed,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16)),
                                    content: Text(
                                      'Customer has a pending credit of ₹${currentPending.toStringAsFixed(2)}.\n'
                                      'Adding this bill (₹${_totalAmount.toStringAsFixed(2)}) would exceed the ₹${maxCreditLimit.toStringAsFixed(0)} limit.\n\n'
                                      'Please collect a repayment first.',
                                      style: GoogleFonts.poppins(
                                          color: AppColors.textSecondary,
                                          fontSize: 13),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dCtx),
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
                    ]),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Helpers
  // ─────────────────────────────────────────────────────────────

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
        content: Text('Remove all ${_billItems.length} item(s)?',
            style: GoogleFonts.poppins(
                color: AppColors.textSecondary, fontSize: 14)),
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
            // Printer icon with live status color
            GestureDetector(
              onTap: _startPrinterSetup,
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _printerStatusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _printerStatusColor.withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _printerStatus == _PrinterStatus.connecting ||
                          _printerStatus == _PrinterStatus.scanning
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: _printerStatusColor,
                          ),
                        )
                      : Icon(Icons.print_rounded,
                          color: _printerStatusColor, size: 16),
                  const SizedBox(width: 5),
                  Text(
                    _printerStatusLabel,
                    style: GoogleFonts.poppins(
                        color: _printerStatusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            ),
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
              // ── Printer status bar (only when not connected) ──
              if (_printerStatus != _PrinterStatus.connected &&
                  _printerStatus != _PrinterStatus.scanning &&
                  _printerStatus != _PrinterStatus.connecting)
                _PrinterStatusBar(
                  status: _printerStatus,
                  deviceName: _selectedPrinter?.name,
                  onConnect: _connectToPrinter,
                  onChoose: _showPrinterSheet,
                ),

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
                onTogglePrice: (isFull) => setState(() => _isFullPrice = isFull),
                onIncrement: () => setState(() => _quantity++),
                onDecrement: () {
                  if (_quantity > 1) setState(() => _quantity--);
                },
                onAdd: _addItem,
              ),

              // ── Cart Header ──
              _CartHeader(count: _billItems.length),

              // ── Scrollable Cart ──
              Expanded(
                child: _billItems.isEmpty
                    ? _EmptyCart()
                    : _CartList(items: _billItems, onRemove: _removeItem),
              ),

              // ── Bottom: Payment + Actions ──
              _BottomPanel(
                total: _totalAmount,
                paymentMethod: _paymentMethod,
                isSaving: _isSaving || _isPrinting,
                hasItems: _billItems.isNotEmpty,
                printerConnected: _printerStatus == _PrinterStatus.connected,
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

  // ── Printer status helpers ──

  Color get _printerStatusColor {
    switch (_printerStatus) {
      case _PrinterStatus.connected:
        return Colors.greenAccent;
      case _PrinterStatus.connecting:
      case _PrinterStatus.scanning:
        return AppColors.accentBlue;
      case _PrinterStatus.disconnected:
        return AppColors.accentOrange;
      case _PrinterStatus.noBluetooth:
      case _PrinterStatus.noDevice:
        return AppColors.accentRed;
      case _PrinterStatus.notInitialized:
        return AppColors.textSecondary;
    }
  }

  String get _printerStatusLabel {
    switch (_printerStatus) {
      case _PrinterStatus.connected:
        return 'Connected';
      case _PrinterStatus.connecting:
        return 'Connecting';
      case _PrinterStatus.scanning:
        return 'Scanning';
      case _PrinterStatus.disconnected:
        return 'Disconnected';
      case _PrinterStatus.noBluetooth:
        return 'No BT';
      case _PrinterStatus.noDevice:
        return 'No Printer';
      case _PrinterStatus.notInitialized:
        return 'Printer';
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  Printer Status Banner (shown when not connected)
// ─────────────────────────────────────────────────────────────

class _PrinterStatusBar extends StatelessWidget {
  final _PrinterStatus status;
  final String? deviceName;
  final VoidCallback onConnect;
  final VoidCallback onChoose;

  const _PrinterStatusBar({
    required this.status,
    required this.deviceName,
    required this.onConnect,
    required this.onChoose,
  });

  @override
  Widget build(BuildContext context) {
    final isError = status == _PrinterStatus.noBluetooth ||
        status == _PrinterStatus.noDevice;
    final color = isError ? AppColors.accentRed : AppColors.accentOrange;

    String message;
    switch (status) {
      case _PrinterStatus.disconnected:
        message = deviceName != null
            ? 'Printer "$deviceName" disconnected'
            : 'No printer connected';
        break;
      case _PrinterStatus.noBluetooth:
        message = 'Bluetooth is not available or turned off';
        break;
      case _PrinterStatus.noDevice:
        message = 'No paired Bluetooth printer found';
        break;
      default:
        message = 'Printer not connected';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(
          isError ? Icons.bluetooth_disabled_rounded : Icons.print_disabled_rounded,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: GoogleFonts.poppins(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        if (status == _PrinterStatus.disconnected && deviceName != null)
          GestureDetector(
            onTap: onConnect,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Text('Reconnect',
                  style: GoogleFonts.poppins(
                      color: color, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ),
        if (status == _PrinterStatus.noDevice ||
            status == _PrinterStatus.disconnected)
          GestureDetector(
            onTap: onChoose,
            child: Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.accentBlue.withValues(alpha: 0.5)),
              ),
              child: Text('Choose',
                  style: GoogleFonts.poppins(
                      color: AppColors.accentBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Printer Picker Bottom Sheet
// ─────────────────────────────────────────────────────────────

class _PrinterSheet extends StatelessWidget {
  final List<BluetoothDevice> devices;
  final BluetoothDevice? selectedDevice;
  final _PrinterStatus printerStatus;
  final ValueChanged<BluetoothDevice> onSelect;
  final VoidCallback onRefresh;

  const _PrinterSheet({
    required this.devices,
    required this.selectedDevice,
    required this.printerStatus,
    required this.onSelect,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.glassBorder,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Bluetooth Printers',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                GestureDetector(
                  onTap: onRefresh,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.accentBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.accentBlue.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.refresh_rounded,
                          color: AppColors.accentBlue, size: 14),
                      const SizedBox(width: 4),
                      Text('Refresh',
                          style: GoogleFonts.poppins(
                              color: AppColors.accentBlue,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Showing paired Bluetooth devices on your phone.',
                style: GoogleFonts.poppins(
                    color: AppColors.textHint, fontSize: 11)),
            const SizedBox(height: 14),
            if (devices.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(children: [
                    const Icon(Icons.bluetooth_searching_rounded,
                        color: AppColors.textSecondary, size: 40),
                    const SizedBox(height: 10),
                    Text(
                      'No paired devices found.\nPair your thermal printer in Android Bluetooth settings first.',
                      style: GoogleFonts.poppins(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ]),
                ),
              )
            else
              ...devices.map((device) {
                final isSelected = selectedDevice?.address == device.address;
                final isConnected =
                    isSelected && printerStatus == _PrinterStatus.connected;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.bgInput : AppColors.bgDark,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isConnected
                          ? Colors.greenAccent.withValues(alpha: 0.6)
                          : isSelected
                              ? AppColors.accentBlue.withValues(alpha: 0.5)
                              : AppColors.glassBorder,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isConnected
                            ? Colors.greenAccent.withValues(alpha: 0.1)
                            : AppColors.accentBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.print_rounded,
                        color: isConnected
                            ? Colors.greenAccent
                            : AppColors.accentBlue,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      device.name ?? device.address ?? 'Printer',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      device.address ?? '',
                      style: GoogleFonts.poppins(
                          color: AppColors.textHint, fontSize: 10),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isConnected
                              ? [
                                  Colors.green.shade700,
                                  Colors.greenAccent.shade700
                                ]
                              : [
                                  AppColors.gradBlue,
                                  AppColors.accentBlue,
                                ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isConnected ? 'Active' : 'Connect',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    onTap: isConnected ? null : () => onSelect(device),
                  ),
                );
              }),
            const SizedBox(height: 8),
            // Hint
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgInput,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppColors.textSecondary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tip: If your printer (KPC307-UEWB) is not listed, '
                    'pair it via Android Settings → Bluetooth first.',
                    style: GoogleFonts.poppins(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        height: 1.5),
                  ),
                ),
              ]),
            ),
          ],
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
          _SearchField(
            controller: searchController,
            focusNode: searchFocus,
            suggestions: suggestions,
            menuLoading: menuLoading,
            onItemSelected: onItemSelected,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _QtyStepper(
                value: quantity,
                onInc: onIncrement,
                onDec: onDecrement,
              ),
              const SizedBox(width: 10),
              _PriceToggle(
                isFull: isFullPrice,
                onToggle: onTogglePrice,
              ),
              const SizedBox(width: 10),
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
//  _SearchField
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
                ? 'Loading menu…'
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
              borderSide: const BorderSide(color: AppColors.gradBlue, width: 1.5),
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
                      child: Row(children: [
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
                      ]),
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

  const _QtyStepper({required this.value, required this.onInc, required this.onDec});

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
            child: Text('$value',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 46,
        decoration: BoxDecoration(
          color: isAdd
              ? AppColors.gradBlue.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.horizontal(
            left: isAdd ? Radius.zero : const Radius.circular(11),
            right: isAdd ? const Radius.circular(11) : Radius.zero,
          ),
        ),
        child: Icon(icon,
            color: isAdd ? AppColors.accentBlue : AppColors.textSecondary,
            size: 18),
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
          _ToggleChip(label: 'Full', selected: isFull, onTap: () => onToggle(true)),
          _ToggleChip(label: 'Half', selected: !isFull, onTap: () => onToggle(false)),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentBlue.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: selected ? AppColors.accentBlue : AppColors.textHint,
            fontSize: 12,
            fontWeight: FontWeight.w700,
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
          gradient: const LinearGradient(
            colors: [AppColors.gradBlue, AppColors.accentBlue],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.gradBlue.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: isAdding
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text('Add to Bill',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ]),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.bgDark,
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.accentGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.shopping_cart_outlined,
              color: AppColors.accentGreen, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          count == 0 ? 'Bill Items' : 'Bill Items ($count)',
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ]),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 56, color: AppColors.textHint.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('No items added yet',
              style: GoogleFonts.poppins(
                  color: AppColors.textHint, fontSize: 14)),
          const SizedBox(height: 4),
          Text('Search and add items above',
              style: GoogleFonts.poppins(
                  color: AppColors.textHint.withValues(alpha: 0.6),
                  fontSize: 12)),
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
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final item = items[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(children: [
            // Item Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(item.name,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    if (item.type == 'Half') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accentOrange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('½',
                            style: GoogleFonts.poppins(
                                color: AppColors.accentOrange,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '${item.quantity} × ₹${item.price.toStringAsFixed(1)}',
                    style: GoogleFonts.poppins(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            // Subtotal
            Text(
              '₹${item.subtotal.toStringAsFixed(1)}',
              style: GoogleFonts.poppins(
                  color: AppColors.accentGreen,
                  fontSize: 14,
                  fontWeight: FontWeight.w800),
            ),
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
                child: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.accentRed, size: 16),
              ),
            ),
          ]),
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
  final bool printerConnected;
  final ValueChanged<String> onPaymentChanged;
  final VoidCallback onSave;
  final VoidCallback onClear;

  const _BottomPanel({
    required this.total,
    required this.paymentMethod,
    required this.isSaving,
    required this.hasItems,
    required this.printerConnected,
    required this.onPaymentChanged,
    required this.onSave,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.glassBorder)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Total row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Amount',
                  style: GoogleFonts.poppins(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              Text(
                '₹ ${total.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                    color: AppColors.accentGreen,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Payment method
          Row(children: [
            _PayBtn(
                label: 'Cash',
                icon: Icons.money_rounded,
                selected: paymentMethod == 'Cash',
                onTap: () => onPaymentChanged('Cash')),
            const SizedBox(width: 8),
            _PayBtn(
                label: 'UPI',
                icon: Icons.qr_code_scanner_rounded,
                selected: paymentMethod == 'UPI',
                onTap: () => onPaymentChanged('UPI')),
            const SizedBox(width: 8),
            _PayBtn(
                label: 'Credit',
                icon: Icons.credit_card_rounded,
                selected: paymentMethod == 'Credit',
                onTap: () => onPaymentChanged('Credit')),
          ]),
          const SizedBox(height: 12),
          // Save + Print button
          GestureDetector(
            onTap: (!hasItems || isSaving) ? null : onSave,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                gradient: hasItems && !isSaving
                    ? const LinearGradient(
                        colors: [Color(0xFF0066B3), Color(0xFF4FC3F7)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : null,
                color: hasItems && !isSaving ? null : AppColors.bgInput,
                borderRadius: BorderRadius.circular(16),
                boxShadow: hasItems && !isSaving
                    ? [
                        BoxShadow(
                          color: const Color(0xFF0066B3).withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.save_alt_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Save & Print Bill',
                          style: GoogleFonts.poppins(
                              color: hasItems ? Colors.white : AppColors.textHint,
                              fontWeight: FontWeight.w800,
                              fontSize: 15),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.print_rounded,
                            color: Colors.white70, size: 16),
                      ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PayBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gradBlue.withValues(alpha: 0.25)
                : AppColors.bgInput,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.accentBlue : AppColors.glassBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(children: [
            Icon(icon,
                color: selected ? AppColors.accentBlue : AppColors.textSecondary,
                size: 18),
            const SizedBox(height: 3),
            Text(label,
                style: GoogleFonts.poppins(
                    color: selected ? AppColors.accentBlue : AppColors.textHint,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}
