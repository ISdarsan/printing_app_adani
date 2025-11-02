import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// BillItem model remains the same
class BillItem {
  final String code;
  final String name;
  final String type; // "Full" or "Half"
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

// MenuItem model remains the same
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

  // Factory to create a MenuItem from a Firebase document
  factory MenuItem.fromFirestore(Map<String, dynamic> data) {
    return MenuItem(
      code: data['code'] ?? '',
      name: data['name'] ?? '',
      fullPrice: (data['fullPrice'] ?? 0.0).toDouble(),
      halfPrice:
      (data['halfPrice'] != null) ? (data['halfPrice']).toDouble() : null,
    );
  }
}

class PrintBillPage extends StatefulWidget {
  const PrintBillPage({super.key});

  @override
  State<PrintBillPage> createState() => _PrintBillPageState();
}

class _PrintBillPageState extends State<PrintBillPage> {
  final _autocompleteController = TextEditingController();
  final _autocompleteFocusNode = FocusNode();
  List<MenuItem> _fullMenu = [];
  MenuItem? _selectedMenuItem;

  final _quantityController = TextEditingController(text: '1');
  bool _isLoading = false;

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

  @override
  void initState() {
    super.initState();
    _fetchMenu();
  }

  Future<void> _fetchMenu() async {
    try {
      final snapshot =
      await FirebaseFirestore.instance.collection('menuItems').get();

      final menu = snapshot.docs.map((doc) {
        return MenuItem.fromFirestore(doc.data() as Map<String, dynamic>);
      }).toList();

      setState(() {
        _fullMenu = menu;
      });
    } catch (e) {
      _showErrorSnackBar('Failed to load menu: $e');
    }
  }

  void _addItemToBill() {
    final int quantity = int.tryParse(_quantityController.text) ?? 1;

    if (_selectedMenuItem == null) {
      _showErrorSnackBar('Please select an item from the search list.');
      return;
    }

    final menuItem = _selectedMenuItem!;
    final bool isFull = _priceSelection[0];
    double price;
    String type;

    if (isFull) {
      price = menuItem.fullPrice;
      type = 'Full';
    } else {
      if (menuItem.halfPrice != null && menuItem.halfPrice! > 0) {
        price = menuItem.halfPrice!;
        type = 'Half';
      } else {
        _showErrorSnackBar('This item does not have a "Half" price option.');
        return;
      }
    }

    setState(() {
      _currentBillItems.add(BillItem(
        code: menuItem.code,
        name: menuItem.name,
        type: type,
        quantity: quantity,
        price: price,
      ));
      _calculateTotal();
      _autocompleteController.clear();
      _selectedMenuItem = null;
      _quantityController.text = '1';
      _autocompleteFocusNode.unfocus();
    });
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
      _autocompleteController.clear();
      _selectedMenuItem = null;
    });
  }

  void _printBill() {
    if (_currentBillItems.isEmpty) {
      _showErrorSnackBar("Cannot print an empty bill.");
      return;
    }

    FirebaseFirestore.instance.collection('sales').add({
      'totalAmount': _totalAmount,
      'paymentMethod': _paymentMethod,
      'timestamp': FieldValue.serverTimestamp(),
      'items': _currentBillItems
          .map((item) => {
        'code': item.code,
        'name': item.name,
        'type': item.type,
        'quantity': item.quantity,
        'price': item.price,
        'subtotal': item.subtotal,
      })
          .toList(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Bill Saved! Total: ₹${_totalAmount.toStringAsFixed(2)}, Payment: $_paymentMethod'),
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
    _autocompleteController.dispose();
    _quantityController.dispose();
    _autocompleteFocusNode.dispose();
    super.dispose();
  }

  // --- WIDGET BUILD (MODIFIED) ---
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
      // The Scaffold will automatically resize when the keyboard appears.
      // This new Column layout is simpler and faster.
      body: SafeArea(
        child: Column(
          children: [
            // 1. INPUT SECTION
            // This part will NOT scroll. It's always at the top.
            _buildInputSection(),

            // 2. BILL ITEMS LIST
            const Divider(thickness: 1),
            const Padding(
              padding: EdgeInsets.only(top: 8.0, bottom: 4.0), // Added bottom padding
              child: Text(
                'Current Bill',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),

            // 3. THIS IS THE BIG FIX
            // We wrap the list in Expanded.
            // This tells the list to "take all the remaining empty space".
            // This pushes the totals to the bottom.
            Expanded(
              child: _currentBillItems.isEmpty
                  ? const Center(
                child: Text(
                  'No items added yet.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              )
                  : ListView.builder(
                // The ListView will now scroll internally if it gets too long
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

            // 4. TOTALS & PRINT BUTTON
            // Because the list is Expanded, this is pushed to the bottom.
            _buildTotalsSection(),
          ],
        ),
      ),
    );
  }
  // --- END OF MODIFICATION ---


  // Helper Widget for the input section
  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.white,
      child: Column(
        children: [
          // This is the new Autocomplete widget
          Autocomplete<MenuItem>(
            textEditingController: _autocompleteController,
            focusNode: _autocompleteFocusNode,
            displayStringForOption: (MenuItem option) =>
            '${option.code} - ${option.name}',
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text == '') {
                return const Iterable<MenuItem>.empty();
              }
              if (_fullMenu.isEmpty) {
                return const Iterable<MenuItem>.empty();
              }

              String query = textEditingValue.text.toLowerCase();
              return _fullMenu.where((MenuItem item) {
                return item.name.toLowerCase().contains(query) ||
                    item.code.toLowerCase().contains(query);
              });
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4.0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 200, maxWidth: MediaQuery.of(context).size.width - 32),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final MenuItem option = options.elementAt(index);
                        return InkWell(
                          onTap: () {
                            onSelected(option);
                          },
                          child: ListTile(
                            title: Text('${option.code} - ${option.name}'),
                            subtitle: Text('₹${option.fullPrice.toStringAsFixed(2)}'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
            onSelected: (MenuItem selection) {
              setState(() {
                _selectedMenuItem = selection;
                _autocompleteController.text = '${selection.code} - ${selection.name}';
                FocusScope.of(context).nextFocus();
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: _buildInputDecoration(
                  labelText: 'Search by Code or Name...',
                  icon: Icons.search,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: _buildInputDecoration(labelText: 'Quantity'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: ToggleButtons(
                  isSelected: _priceSelection,
                  onPressed: (index) {
                    setState(() {
                      _priceSelection = [index == 0, index == 1];
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  constraints:
                  const BoxConstraints(minHeight: 40.0, minWidth: 100.0),
                  children: const [
                    Text('Full', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('Half', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Add to Bill Button
          ElevatedButton.icon(
            icon: _isLoading
                ? Container(
              width: 20,
              height: 20,
              child: const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.add_shopping_cart),
            label: Text(_isLoading ? 'Adding...' : 'Add Item to Bill'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)
                )
            ),
            onPressed: _isLoading ? null : _addItemToBill,
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _clearBill,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)
                      )
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
                        'Save & Print Bill',
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

  InputDecoration _buildInputDecoration({required String labelText, IconData? icon}) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: icon != null ? Icon(icon) : null,
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