import 'package:flutter/material.dart';
// 1. IMPORT the Firebase database package
import 'package:cloud_firestore/cloud_firestore.dart';

// This is our data model. We will use it to read data from Firebase.
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

  // 2. NEW: A factory to create a MenuItem from a Firebase document
  factory MenuItem.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return MenuItem(
      code: data['code'] ?? '',
      name: data['name'] ?? '',
      fullPrice: (data['fullPrice'] ?? 0.0).toDouble(),
      halfPrice: (data['halfPrice'] ?? 0.0).toDouble(),
    );
  }
}

class MenuViewPage extends StatefulWidget {
  const MenuViewPage({super.key});
  @override
  State<MenuViewPage> createState() => _MenuViewPageState();
}

class _MenuViewPageState extends State<MenuViewPage> {
  // 3. REMOVED the old demo data list (_allMenuItems)

  // We keep the search controller
  final _searchController = TextEditingController();
  String _searchQuery = ''; // Store the search query here

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterMenu);
  }

  void _filterMenu() {
    // Just update the query string, the StreamBuilder will do the rest
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
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

          // 4. NEW: Use a StreamBuilder to get live data
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // This is the "stream" we listen to:
              // It gets all documents from the "menuItems" collection
              stream:
              FirebaseFirestore.instance.collection('menuItems').snapshots(),
              builder: (context, snapshot) {
                // Handle the "Loading" state
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Handle the "Error" state
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                // Handle the "No Data" state
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No items found in menu.\nGo to "Add Item" to add some!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                // --- We have data! ---
                // 5. Apply the search filter to the LIVE data
                final allItems = snapshot.data!.docs.map((doc) {
                  // Convert the Firebase document into our MenuItem object
                  return MenuItem.fromFirestore(doc);
                }).toList();

                final filteredItems = allItems.where((item) {
                  final nameMatches = item.name.toLowerCase().contains(_searchQuery);
                  final codeMatches = item.code.toLowerCase().contains(_searchQuery);
                  return nameMatches || codeMatches;
                }).toList();

                // If search finds nothing, show a message
                if (filteredItems.isEmpty) {
                  return const Center(
                    child: Text(
                      'No items match your search.',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                // 6. Build the list using the filtered, live data
                return ListView.builder(
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
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
                            if (item.halfPrice != null && item.halfPrice! > 0)
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
