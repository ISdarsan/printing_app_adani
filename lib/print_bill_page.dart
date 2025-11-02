import 'package:flutter/material.dart';

// This is a simple data model for an item IN THE BILL
class BillItem {
  final String code;
  final String name;
  final String type; // "Full" or "Half"
  final int quantity;
  final double price; // The price for this item (e.g., 120.00)

  BillItem({
    required this.code,
    required this.name,
    required this.type,
    required this.quantity,
    required this.price,
  });

  double get subtotal => price * quantity;
}

// This is a (DEMO) model for an item IN THE MENU
// Later, this will come from Firebase
class MenuItem {
  final String code;
  final String name;
  final double fullPrice;
  final double? halfPrice;

  MenuItem({
    required this.code,
    required this.name,
    required this.fullPrice,
    this.halfPrice,
  });
}

class PrintBillPage extends StatefulWidget {
  const PrintBillPage({super.key});

  @override
  State<PrintBillPage> createState() => _PrintBillPageState();
}

class _PrintBillPageState extends State<PrintBillPage> {
  // --- DEMO MENU DATABASE ---
  final Map<String, MenuItem> _menuDatabase = {
    'CH10': MenuItem(
        code: 'CH10', name: 'Chicken Curry', fullPrice: 120.00, halfPrice: 70.00),
    'BF20': MenuItem(
        code: 'BF20', name: 'Beef Fry', fullPrice: 140.00, halfPrice: 80.00),
    'VEG30': MenuItem(code: 'VEG30', name: 'Veg Meals', fullPrice: 80.00),
    'PO50': MenuItem(code: 'PO50', name: 'Porotta', fullPrice: 12.00),
  };
  // --------------------------

  final _codeController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  List<bool> _priceSelection = [true, false]; // [Full, Half]
  List<bool> _paymentSelection = [true, false]; // [Cash, UPI]
  String _paymentMethod = 'Cash';

  final List<BillItem> _currentBillItems = [];
  double _totalAmount = 0.0;

  final LinearGradient adaniGradient = const LinearGradient(
    colors: [
      Color(0xFF0066B3), // blue
      Color(0xFF6C3FB5), // purple
      Color(0xFFE91E63), // pink
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // --- LOGIC METHODS ---

  void _addItemToBill() {
    final String code = _codeController.text.toUpperCase().trim();
    final int quantity = int.tryParse(_quantityController.text) ?? 1;

    if (_menuDatabase.containsKey(code)) {
      final menuItem = _menuDatabase[code]!;
      final bool isFull = _priceSelection[0];

      double price;
      String type;

      if (isFull) {
        price = menuItem.fullPrice;
        type = 'Full';
      } else {
        if (menuItem.halfPrice != null) {
          price = menuItem.halfPrice!;
          type = 'Half';
        } else {
          _showErrorSnackBar('This item does not have a "Half" price option.');
          return;
        }
      }

      setState(() {
        _currentBillItems.add(BillItem(
          code: code,
          name: menuItem.name,
          type: type,
          quantity: quantity,
          price: price,
        ));
        _calculateTotal();
      });

      _codeController.clear();
      _quantityController.text = '1';
    } else {
      _showErrorSnackBar('Food Code "$code" not found in menu.');
    }
  }

  void _removeItem(int index) {
    setState(() {
      _currentBillItems.removeAt(index);
      _calculateTotal();
    });
  }

  void _calculateTotal() {
    double total = 0.0;
    for (var item in _currentBillItems) {
      total += item.subtotal;
    }
    setState(() {
      _totalAmount = total;
    });
  }

  void _clearBill() {
    setState(() {
      _currentBillItems.clear();
      _calculateTotal();
      _paymentSelection = [true, false];
      _paymentMethod = 'Cash';
    });
  }

  void _printBill() {
    if (_currentBillItems.isEmpty) {
      _showErrorSnackBar("Cannot print an empty bill.");
      return;
    }

    // --- TODO: Add real printer logic here ---
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Printing Bill... Total: ₹${_totalAmount.toStringAsFixed(2)}, Payment: $_paymentMethod'),
        backgroundColor: Colors.green,
      ),
    );

    _clearBill();
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  // --- UI WIDGETS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: AppBar(
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: Container(
            decoration: BoxDecoration(gradient: adaniGradient),
          ),
          title: const Text(
            'New Bill',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
          elevation: 3,
        ),
      ),
      // --- THIS IS THE FIX ---
      // Wrap the entire body in a SafeArea widget
      body: SafeArea(
        child: Column(
          children: [
            // 1. INPUT SECTION
            _buildInputSection(),

            // 2. BILL ITEMS LIST
            const Divider(thickness: 1),
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text(
                'Current Bill',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(
              child: _currentBillItems.isEmpty
                  ? const Center(
                child: Text(
                  'No items added yet.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _currentBillItems.length,
                itemBuilder: (context, index) {
                  final item = _currentBillItems[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: ListTile(
                      title: Text(item.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${item.quantity} x ${item.type} @ ₹${item.price.toStringAsFixed(2)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '₹${item.subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () => _removeItem(index),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // 3. TOTALS & PRINT BUTTON
            _buildTotalsSection(),
          ],
        ),
      ),
    );
  }

  // Helper Widget for the input section
  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Food Code & Quantity
          Expanded(
            flex: 3,
            child: Column(
              children: [
                TextField(
                  controller: _codeController,
                  decoration:
                  _buildInputDecoration(labelText: 'Food Code (e.g., CH10)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: _buildInputDecoration(labelText: 'Quantity'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Toggle & Add Button
          Expanded(
            flex: 2,
            child: Column(
              children: [
                ToggleButtons(
                  isSelected: _priceSelection,
                  onPressed: (index) {
                    setState(() {
                      _priceSelection = [index == 0, index == 1];
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  constraints:
                  const BoxConstraints(minHeight: 40.0, minWidth: 60.0),
                  children: const [
                    Text('Full', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('Half', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Add'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _addItemToBill,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper Widget for the totals section
  Widget _buildTotalsSection() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // TOTAL AMOUNT
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOTAL:',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              Text(
                '₹${_totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // PAYMENT METHOD
          Row(
            children: [
              const Text(
                'Payment Method:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              ToggleButtons(
                isSelected: _paymentSelection,
                onPressed: (index) {
                  setState(() {
                    _paymentSelection = [index == 0, index == 1];
                    _paymentMethod = (index == 0) ? 'Cash' : 'UPI';
                  });
                },
                borderRadius: BorderRadius.circular(8),
                constraints:
                const BoxConstraints(minHeight: 40.0, minWidth: 60.0),
                selectedColor: Colors.white,
                fillColor: Colors.blue.shade300,
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text('Cash'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text('UPI'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ACTION BUTTONS
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _clearBill,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    minimumSize: const Size(0, 50),
                  ),
                  child: const Text('Clear Bill'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _printBill,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: adaniGradient,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Center(
                      child: Text(
                        'Print Bill',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration({required String labelText}) {
    return InputDecoration(
      labelText: labelText,
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }
}

