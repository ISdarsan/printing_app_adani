import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // <-- 1. ADD THIS IMPORT

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _otherReasonController = TextEditingController();

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  // --- 2. ADD STATE FOR DATE ---
  DateTime _selectedExpenseDate = DateTime.now();
  // -----------------------------

  String? _selectedCategory;
  final List<String> _expenseCategories = [
    'Vegetables',
    'Gas',
    'Groceries',
    'Maintenance',
    'Other',
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _otherReasonController.dispose();
    super.dispose();
  }

  // ... (Keep _showImageSourceDialog and _pickImage functions as they are) ...
  // Function to show dialog for choosing image source
  Future<void> _showImageSourceDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Select Proof"),
        contentPadding: const EdgeInsets.all(20),
        content: const Text("Choose source to upload receipt"),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text("Camera"),
            onPressed: () {
              Navigator.of(context).pop();
              _pickImage(ImageSource.camera);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.photo_library),
            label: const Text("Gallery"),
            onPressed: () {
              Navigator.of(context).pop();
              _pickImage(ImageSource.gallery);
            },
          ),
        ],
      ),
    );
  }

  // Function to pick the image
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        imageQuality: 70,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to pick image: $e")),
      );
    }
  }


  // --- 3. ADD DATE PICKER FUNCTION ---
  Future<void> _selectExpenseDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedExpenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(), // Can't log future expenses
    );
    if (picked != null && picked != _selectedExpenseDate) {
      setState(() {
        _selectedExpenseDate = picked;
      });
    }
  }
  // ---------------------------------


  // Function to handle submitting the expense
  Future<void> _submitExpense() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please upload a proof of expense"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You must be logged in to log an expense"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String finalDescription;
      if (_selectedCategory == 'Other') {
        finalDescription = _otherReasonController.text;
      } else {
        finalDescription = _selectedCategory!;
      }

      final amount = double.tryParse(_amountController.text) ?? 0.0;
      final imageBytes = await _imageFile!.readAsBytes();
      String base64Image = base64Encode(imageBytes);

      // 4. --- MODIFY THE SAVED DATA ---
      await FirebaseFirestore.instance.collection('expenses').add({
        'category': _selectedCategory,
        'description': finalDescription,
        'amount': amount,
        'proofImageBase64': base64Image,

        // --- USE THE SELECTED DATE INSTEAD OF SERVER TIMESTAMP ---
        'timestamp': Timestamp.fromDate(_selectedExpenseDate),

        'userId': user.uid,
      });
      // -------------------------------

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Expense logged successfully!"),
          backgroundColor: Colors.green,
        ),
      );

      _formKey.currentState!.reset();
      _amountController.clear();
      _otherReasonController.clear();
      setState(() {
        _imageFile = null;
        _selectedCategory = null;
        _selectedExpenseDate = DateTime.now(); // Reset date
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to log expense: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Log New Expense"),
        backgroundColor: theme.primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Expense Details Card ---
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Expense Details",
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // --- 5. ADD DATE FIELD TO FORM ---
                        TextFormField(
                          readOnly: true,
                          controller: TextEditingController(
                              text: DateFormat('MMMM dd, yyyy').format(_selectedExpenseDate)
                          ),
                          decoration: InputDecoration(
                            labelText: "Date of Expense *",
                            prefixIcon: Icon(Icons.calendar_month),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          onTap: () => _selectExpenseDate(context),
                        ),
                        const SizedBox(height: 16),
                        // ---------------------------------

                        // --- Category Dropdown ---
                        DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          decoration: const InputDecoration(
                            labelText: "Expense Category *",
                            prefixIcon: Icon(Icons.category),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          hint: const Text("Select a category"),
                          isExpanded: true,
                          items: _expenseCategories.map((String category) {
                            return DropdownMenuItem<String>(
                              value: category,
                              child: Text(category),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setState(() {
                              _selectedCategory = newValue;
                              if (newValue != 'Other') {
                                _otherReasonController.clear();
                              }
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return "Please select a category";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // --- Conditional "Other Reason" Field ---
                        if (_selectedCategory == 'Other')
                          TextFormField(
                            controller: _otherReasonController,
                            decoration: const InputDecoration(
                              labelText: "Reason for 'Other' *",
                              prefixIcon: Icon(Icons.edit_note),
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            validator: (value) {
                              if (_selectedCategory == 'Other' &&
                                  (value == null || value.isEmpty)) {
                                return "Please provide a reason";
                              }
                              return null;
                            },
                          ),
                        const SizedBox(height: 16),

                        // --- Amount Field ---
                        TextFormField(
                          controller: _amountController,
                          decoration: const InputDecoration(
                            labelText: "Amount (₹) *",
                            prefixIcon: Icon(Icons.currency_rupee),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return "Please enter an amount";
                            }
                            if (double.tryParse(value) == null) {
                              return "Please enter a valid number";
                            }
                            if (double.parse(value) <= 0) {
                              return "Amount must be greater than zero";
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // --- Image Upload Card ---
                Card(
                  elevation: 4,
                  // ... (Keep this card exactly as it was) ...
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Upload Proof *",
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: _showImageSourceDialog,
                          child: Container(
                            height: 200,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              border: Border.all(
                                color: _imageFile == null
                                    ? Colors.grey.shade400
                                    : theme.primaryColor,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: _imageFile == null
                                ? Center(
                              child: Column(
                                mainAxisAlignment:
                                MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo,
                                    color: Colors.grey.shade600,
                                    size: 50,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Tap to upload receipt",
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            )
                                : ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                _imageFile!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // --- Submit Button ---
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _submitExpense,
                  // ... (Keep this button exactly as it was) ...
                  icon: _isLoading
                      ? Container(
                    width: 24,
                    height: 24,
                    padding: const EdgeInsets.all(2.0),
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                      : const Icon(Icons.save),
                  label: Text(
                    _isLoading ? "Saving..." : "Save Expense",
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: theme.primaryColor,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}