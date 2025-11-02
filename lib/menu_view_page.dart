import 'package:flutter/material.dart';

// This is our demo data model.
// Later, this will come from Firebase.
class MenuItem {
  final String code;
  final String name;
  final double fullPrice;
  final double? halfPrice; // Nullable (optional)

  MenuItem({
    required this.code,
    required this.name,
    required this.fullPrice,
    this.halfPrice,
  });
}

class MenuViewPage extends StatefulWidget {
  const MenuViewPage({super.key});

  @override
  State<MenuViewPage> createState() => _MenuViewPageState();
}

class _MenuViewPageState extends State<MenuViewPage> {
  // --- DEMO DATA ---
  // This is the list of all items in the menu.
  // Later, we will fetch this list from Firebase.
  final List<MenuItem> _allMenuItems = [
    MenuItem(
        code: 'CH10', name: 'Chicken Curry', fullPrice: 120.00, halfPrice: 70.00),
    MenuItem(
        code: 'BF20', name: 'Beef Fry', fullPrice: 140.00, halfPrice: 80.00),
    MenuItem(code: 'VEG30', name: 'Veg Meals', fullPrice: 80.00),
    MenuItem(
        code: 'FI40', name: 'Fish Curry', fullPrice: 100.00, halfPrice: 60.00),
    MenuItem(code: 'PO50', name: 'Porotta', fullPrice: 12.00),
    MenuItem(code: 'WA60', name: 'Water Bottle', fullPrice: 20.00),
    MenuItem(code: 'CH70', name: 'Chai', fullPrice: 10.00),
  ];
  // -----------------

  List<MenuItem> _filteredMenuItems = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Initially, show all items
    _filteredMenuItems = _allMenuItems;
    _searchController.addListener(_filterMenu);
  }

  void _filterMenu() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredMenuItems = _allMenuItems.where((item) {
        final nameMatches = item.name.toLowerCase().contains(query);
        final codeMatches = item.code.toLowerCase().contains(query);
        return nameMatches || codeMatches;
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Your Adani brand gradient
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
            'Full Menu & Prices',
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
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or code...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Menu List
          Expanded(
            child: ListView.builder(
              itemCount: _filteredMenuItems.length,
              itemBuilder: (context, index) {
                final item = _filteredMenuItems[index];
                return Card(
                  margin:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    // Food Code
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade50,
                      child: Text(
                        item.code,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    // Item Name
                    title: Text(
                      item.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    // Prices (Full and Half)
                    trailing: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Full: ₹${item.fullPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.green,
                          ),
                        ),
                        // Only show "Half" if it has a price
                        if (item.halfPrice != null)
                          Text(
                            'Half: ₹${item.halfPrice!.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
