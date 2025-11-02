import 'package:flutter/material.dart';
// 1. IMPORT the Firebase database package
import 'package:cloud_firestore/cloud_firestore.dart';

// 2. CONVERT to a StatefulWidget to manage a "loading" state
class AddItemPage extends StatefulWidget {
  const AddItemPage({super.key});

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage> {
  // A key to validate our form
  final _formKey = GlobalKey<FormState>();

  // Controllers to get the text from the fields
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _fullPriceController = TextEditingController();
  final _halfPriceController = TextEditingController();

  // A variable to track if we are currently saving
  bool _isLoading = false;

  // Your gradient
  final LinearGradient adaniGradient = const LinearGradient(
    colors: [
      Color(0xFF0066B3), // blue
      Color(0xFF6C3FB5), // purple
      Color(0xFFE91E63), // pink
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // 3. CREATE the function to save the item
  Future<void> _saveItem() async {
    // First, check if all fields are valid (e.g., not empty)
    if (_formKey.currentState!.validate()) {
      // Show the loading spinner
      setState(() {
        _isLoading = true;
      });

      try {
        // Get the values from the text fields
        String code = _codeController.text.toUpperCase().trim();
        String name = _nameController.text.trim();
        // Convert prices from text (String) to a number (double)
        double fullPrice = double.tryParse(_fullPriceController.text) ?? 0.0;
        double? halfPrice = _halfPriceController.text.isEmpty
            ? null // If half price is empty, save it as null
            : double.tryParse(_halfPriceController.text);

        // --- THIS IS THE MAGIC ---
        // Get a reference to our database collection called "menuItems"
        // We use .doc(code) to use the Food Code as the ID.
        // This is smart because it prevents duplicate food codes.
        await FirebaseFirestore.instance.collection('menuItems').doc(code).set({
          'code': code,
          'name': name,
          'fullPrice': fullPrice,
          'halfPrice': halfPrice,
          'category': 'default', // We can add this feature later
        });
        // -------------------------

        // Show a success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Go back to the previous page (dashboard)
        if (mounted) {
          Navigator.pop(context);
        }
      } catch (e) {
        // If an error happens (like no internet)
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Clean up the controllers when the page is closed
  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _fullPriceController.dispose();
    _halfPriceController.dispose();
    super.dispose();
  }

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
            'Add / Edit Item',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        // 4. WRAP everything in a Form widget
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const Text(
                'Enter New Food Details',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF003C8F)),
              ),
              const SizedBox(height: 24),
              _buildTextFormField(
                controller: _codeController,
                labelText: 'Food Code (e.g., CH10)',
                icon: Icons.qr_code,
              ),
              const SizedBox(height: 16),
              _buildTextFormField(
                controller: _nameController,
                labelText: 'Item Name (e.g., Chicken Curry)',
                icon: Icons.fastfood_outlined,
              ),
              const SizedBox(height: 16),
              _buildTextFormField(
                controller: _fullPriceController,
                labelText: 'Full Price (e.g., 120)',
                icon: Icons.currency_rupee,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildTextFormField(
                controller: _halfPriceController,
                labelText: 'Half Price (e.g., 70) - Optional',
                icon: Icons.currency_rupee,
                keyboardType: TextInputType.number,
                isOptional: true, // This will skip validation if it's empty
              ),
              const SizedBox(height: 32),

              // 5. MODIFY the save button to show a loading spinner
              GestureDetector(
                onTap: _isLoading ? null : _saveItem, // Disable button when loading
                child: Container(
                  width: double.infinity,
                  height: 55,
                  decoration: BoxDecoration(
                    gradient: adaniGradient,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Center(
                    // Show spinner or text
                    child: _isLoading
                        ? const CircularProgressIndicator(
                      valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.white),
                    )
                        : const Text(
                      'Save Item to Database',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget for text fields
  Widget _buildTextFormField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isOptional = false, // New parameter
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: labelText,
        filled: true,
        fillColor: Colors.white,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF0066B3), width: 2),
        ),
      ),
      // Validator to check if field is empty
      validator: (value) {
        if (isOptional && (value == null || value.isEmpty)) {
          return null; // Skip validation if optional and empty
        }
        if (value == null || value.isEmpty) {
          return 'This field is mandatory';
        }
        return null;
      },
    );
  }
}