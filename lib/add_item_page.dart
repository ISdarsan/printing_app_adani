import 'package:flutter/material.dart';

class AddItemPage extends StatefulWidget {
  const AddItemPage({super.key});

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage> {
  final _formKey = GlobalKey<FormState>();

  // Text controllers
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  // MODIFIED: Renamed to full price
  final _fullPriceController = TextEditingController();
  // NEW: Added half price controller
  final _halfPriceController = TextEditingController();

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

  void _saveItem() {
    if (_formKey.currentState!.validate()) {
      // --- TODO: Add Firebase save logic here ---
      // Now you would save all fields:
      // String code = _codeController.text;
      // String name = _nameController.text;
      // String fullPrice = _fullPriceController.text;
      // String halfPrice = _halfPriceController.text; // (might be empty)
      // -----------------------------------------

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item Saved! (Demo)'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    // Clean up all controllers
    _codeController.dispose();
    _nameController.dispose();
    _fullPriceController.dispose(); // MODIFIED
    _halfPriceController.dispose(); // NEW
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
            'Add New Menu Item',
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
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter Item Details',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 24),

              // Food Code Field
              TextFormField(
                controller: _codeController,
                decoration: _buildInputDecoration(
                  hintText: 'e.g., CH10 or 101',
                  labelText: 'Food Code',
                  icon: Icons.qr_code_2,
                ),
                validator: (value) =>
                value!.isEmpty ? 'Please enter a food code' : null,
              ),
              const SizedBox(height: 16),

              // Item Name Field
              TextFormField(
                controller: _nameController,
                decoration: _buildInputDecoration(
                  hintText: 'e.g., Chicken Curry',
                  labelText: 'Item Name',
                  icon: Icons.fastfood_outlined,
                ),
                validator: (value) =>
                value!.isEmpty ? 'Please enter an item name' : null,
              ),
              const SizedBox(height: 16),

              // MODIFIED: Full Price Field
              TextFormField(
                controller: _fullPriceController,
                keyboardType: TextInputType.number,
                decoration: _buildInputDecoration(
                  hintText: 'e.g., 120.00',
                  labelText: 'Full Price (₹)', // Changed label
                  icon: Icons.currency_rupee,
                ),
                validator: (value) =>
                value!.isEmpty ? 'Please enter a full price' : null,
              ),
              const SizedBox(height: 16),

              // NEW: Half Price Field
              TextFormField(
                controller: _halfPriceController,
                keyboardType: TextInputType.number,
                decoration: _buildInputDecoration(
                  hintText: 'e.g., 70.00 (Optional)',
                  labelText: 'Half Price (₹) (Optional)', // New label
                  icon: Icons.currency_rupee_outlined,
                ),
                validator: (value) {
                  // This field is optional, so no error if empty
                  return null;
                },
              ),
              const SizedBox(height: 40),

              // Save Button (Gradient)
              GestureDetector(
                onTap: _saveItem,
                child: Container(
                  width: double.infinity,
                  height: 55,
                  decoration: BoxDecoration(
                    gradient: adaniGradient,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'Save Item',
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

  InputDecoration _buildInputDecoration({
    required String hintText,
    required String labelText,
    required IconData icon,
  }) {
    // This is the brand's blue color from your logo
    const Color brandBlue = Color(0xFF0066B3);

    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Icon(icon, color: brandBlue),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: brandBlue, width: 2),
      ),
    );
  }
}