import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'theme.dart';

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
  final _picker = ImagePicker();
  bool _isLoading = false;
  DateTime _selectedExpenseDate = DateTime.now();
  String? _selectedCategory;

  final List<String> _expenseCategories = [
    'Vegetables',
    'Gas',
    'Groceries',
    'Maintenance',
    'Other'
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _otherReasonController.dispose();
    super.dispose();
  }

  Future<void> _showImageSourceDialog() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Select Proof',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        content: Text('Choose image source',
            style: GoogleFonts.poppins(
                color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.camera_alt, color: AppColors.accentBlue),
            label: Text('Camera',
                style: GoogleFonts.poppins(color: AppColors.accentBlue)),
            onPressed: () {
              Navigator.pop(context);
              _pickImage(ImageSource.camera);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.photo_library, color: AppColors.gradPurple),
            label: Text('Gallery',
                style: GoogleFonts.poppins(color: AppColors.gradPurple)),
            onPressed: () {
              Navigator.pop(context);
              _pickImage(ImageSource.gallery);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final f = await _picker.pickImage(
          source: source, maxWidth: 800, imageQuality: 70);
      if (f != null) setState(() => _imageFile = File(f.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Failed to pick image: $e', style: GoogleFonts.poppins()),
            backgroundColor: AppColors.accentRed));
      }
    }
  }

  Future<void> _selectExpenseDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedExpenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.gradBlue,
            onPrimary: Colors.white,
            surface: AppColors.bgCard,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && picked != _selectedExpenseDate) {
      setState(() => _selectedExpenseDate = picked);
    }
  }

  Future<void> _submitExpense() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please upload a proof of expense'),
          backgroundColor: AppColors.accentRed));
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final desc = _selectedCategory == 'Other'
          ? _otherReasonController.text
          : _selectedCategory!;
      final amount = double.tryParse(_amountController.text) ?? 0.0;
      final imageBytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      await FirebaseFirestore.instance.collection('expenses').add({
        'category': _selectedCategory,
        'description': desc,
        'amount': amount,
        'proofImageBase64': base64Image,
        'timestamp': Timestamp.fromDate(_selectedExpenseDate),
        'userId': user.uid,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✓ Expense logged!', style: GoogleFonts.poppins()),
            backgroundColor: const Color(0xFF1B4332)));
      }

      _formKey.currentState!.reset();
      _amountController.clear();
      _otherReasonController.clear();
      setState(() {
        _imageFile = null;
        _selectedCategory = null;
        _selectedExpenseDate = DateTime.now();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Failed to log expense: $e', style: GoogleFonts.poppins()),
            backgroundColor: AppColors.accentRed));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Log New Expense'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Expense Details Card ──────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: glassCard(radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.edit_note_rounded,
                          color: AppColors.accentBlue, size: 22),
                      const SizedBox(width: 8),
                      sectionTitle('Expense Details'),
                    ]),
                    const SizedBox(height: 18),

                    // Date picker
                    GestureDetector(
                      onTap: () => _selectExpenseDate(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.bgInput,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month,
                                color: AppColors.textSecondary, size: 20),
                            const SizedBox(width: 12),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Date of Expense',
                                      style: GoogleFonts.poppins(
                                          color: AppColors.textSecondary,
                                          fontSize: 11)),
                                  Text(
                                      DateFormat('MMMM dd, yyyy')
                                          .format(_selectedExpenseDate),
                                      style: GoogleFonts.poppins(
                                          color: AppColors.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500)),
                                ]),
                            const Spacer(),
                            const Icon(Icons.chevron_right,
                                color: AppColors.textHint, size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Category dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      dropdownColor: AppColors.bgCard,
                      style: GoogleFonts.poppins(
                          color: AppColors.textPrimary, fontSize: 14),
                      decoration: darkInput(
                          label: 'Expense Category *',
                          prefixIcon: Icons.category_outlined),
                      items: _expenseCategories
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(c,
                                    style: GoogleFonts.poppins(
                                        color: AppColors.textPrimary)),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedCategory = v;
                        if (v != 'Other') _otherReasonController.clear();
                      }),
                      validator: (v) =>
                          v == null ? 'Please select a category' : null,
                    ),
                    const SizedBox(height: 14),

                    if (_selectedCategory == 'Other') ...[
                      TextFormField(
                        controller: _otherReasonController,
                        style: GoogleFonts.poppins(
                            color: AppColors.textPrimary, fontSize: 14),
                        decoration: darkInput(
                            label: 'Reason for Other *',
                            prefixIcon: Icons.notes_rounded),
                        validator: (v) => _selectedCategory == 'Other' &&
                                (v == null || v.isEmpty)
                            ? 'Please provide a reason'
                            : null,
                      ),
                      const SizedBox(height: 14),
                    ],

                    TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.poppins(
                          color: AppColors.textPrimary, fontSize: 14),
                      decoration: darkInput(
                          label: 'Amount (₹) *',
                          prefixIcon: Icons.currency_rupee),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter an amount';
                        if (double.tryParse(v) == null) return 'Invalid number';
                        if (double.parse(v) <= 0) return 'Amount must be > 0';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Upload Proof Card ─────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: glassCard(radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.photo_camera_outlined,
                          color: AppColors.accentOrange, size: 22),
                      const SizedBox(width: 8),
                      sectionTitle('Upload Proof *'),
                    ]),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _showImageSourceDialog,
                      child: Container(
                        height: 190,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.bgInput,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _imageFile == null
                                ? AppColors.glassBorder
                                : AppColors.accentGreen,
                            width: _imageFile == null ? 1 : 1.5,
                            style: _imageFile == null
                                ? BorderStyle.solid
                                : BorderStyle.solid,
                          ),
                        ),
                        child: _imageFile == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                    const Icon(Icons.add_a_photo_outlined,
                                        color: AppColors.textHint, size: 44),
                                    const SizedBox(height: 10),
                                    Text('Tap to upload receipt',
                                        style: GoogleFonts.poppins(
                                            color: AppColors.textSecondary,
                                            fontSize: 13)),
                                    Text('Camera or Gallery',
                                        style: GoogleFonts.poppins(
                                            color: AppColors.textHint,
                                            fontSize: 11)),
                                  ])
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child:
                                    Image.file(_imageFile!, fit: BoxFit.cover)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              buildGradientButton(
                label: 'Save Expense',
                icon: Icons.save_rounded,
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _submitExpense,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
