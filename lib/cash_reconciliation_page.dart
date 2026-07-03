import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'theme.dart';

class CashReconciliationPage extends StatefulWidget {
  final bool isAdmin;
  const CashReconciliationPage({super.key, this.isAdmin = false});

  @override
  State<CashReconciliationPage> createState() => _CashReconciliationPageState();
}

class _CashReconciliationPageState extends State<CashReconciliationPage> {
  final _cashController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  String get _todayId => DateFormat('yyyy-MM-dd').format(DateTime.now());
  String get _todayLabel => DateFormat('dd MMMM yyyy').format(DateTime.now());

  late Stream<DocumentSnapshot> _todayStatsStream;
  late Stream<DocumentSnapshot> _todayReconciliationStream;
  late Stream<QuerySnapshot> _reconciliationHistoryStream;

  @override
  void initState() {
    super.initState();
    _todayStatsStream = FirebaseFirestore.instance
        .collection('dailyStats')
        .doc(_todayId)
        .snapshots();

    _todayReconciliationStream = FirebaseFirestore.instance
        .collection('cashReconciliations')
        .doc(_todayId)
        .snapshots();

    _reconciliationHistoryStream = FirebaseFirestore.instance
        .collection('cashReconciliations')
        .orderBy('timestamp', descending: true)
        .limit(30)
        .snapshots();
  }

  Future<void> _submitReconciliation(double systemCash) async {
    if (!_formKey.currentState!.validate()) return;
    final actual = double.tryParse(_cashController.text);
    if (actual == null || actual < 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a valid cash amount', style: GoogleFonts.poppins()),
        backgroundColor: AppColors.accentRed,
      ));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final discrepancy = actual - systemCash;
      await FirebaseFirestore.instance
          .collection('cashReconciliations')
          .doc(_todayId)
          .set({
        'date': _todayId,
        'systemCash': systemCash,
        'actualCash': actual,
        'discrepancy': discrepancy,
        'note': _noteController.text.trim(),
        'submittedBy': FirebaseAuth.instance.currentUser?.email ?? 'Unknown Cashier',
        'timestamp': FieldValue.serverTimestamp(),
      });

      _cashController.clear();
      _noteController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reconciliation submitted successfully!', style: GoogleFonts.poppins()),
          backgroundColor: const Color(0xFF1B4332),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: GoogleFonts.poppins()),
          backgroundColor: AppColors.accentRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _cashController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(
        title: widget.isAdmin ? 'Cash Reconciliation Logs' : 'Daily Cash Closing',
        centerTitle: true,
      ),
      body: widget.isAdmin ? _buildAdminHistoryView() : _buildCashierSubmissionView(),
    );
  }

  Widget _buildCashierSubmissionView() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _todayReconciliationStream,
      builder: (context, reconSnap) {
        if (reconSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accentBlue));
        }

        // If today is already reconciled, show status and details
        if (reconSnap.hasData && reconSnap.data!.exists) {
          final data = reconSnap.data!.data() as Map<String, dynamic>;
          final system = (data['systemCash'] ?? 0.0) as double;
          final actual = (data['actualCash'] ?? 0.0) as double;
          final discrepancy = (data['discrepancy'] ?? 0.0) as double;
          final note = data['note'] ?? '';
          final user = data['submittedBy'] ?? '';
          final ts = data['timestamp'] as Timestamp?;
          final timeStr = ts != null ? DateFormat('hh:mm a').format(ts.toDate()) : '';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B4332).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1B4332), width: 2),
                    ),
                    child: const Icon(Icons.check_circle_outline_rounded,
                        color: Color(0xFF2D6A4F), size: 48),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Reconciled for Today',
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Submitted by $user at $timeStr',
                    style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: glassCard(radius: 20),
                  child: Column(
                    children: [
                      _rowDetail('Reconciliation Date', _todayLabel),
                      const Divider(color: AppColors.bgDivider, height: 24),
                      _rowDetail('System Cash Recorded', '₹${system.toStringAsFixed(2)}'),
                      const Divider(color: AppColors.bgDivider, height: 24),
                      _rowDetail('Actual Cash Counted', '₹${actual.toStringAsFixed(2)}'),
                      const Divider(color: AppColors.bgDivider, height: 24),
                      _rowDetail(
                        'Discrepancy',
                        '₹${discrepancy.toStringAsFixed(2)}',
                        valueColor: discrepancy == 0
                            ? AppColors.accentGreen
                            : discrepancy < 0
                                ? AppColors.accentRed
                                : AppColors.accentOrange,
                      ),
                      if (note.isNotEmpty) ...[
                        const Divider(color: AppColors.bgDivider, height: 24),
                        _rowDetail('Closing Notes', note),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Otherwise show the submission form
        return StreamBuilder<DocumentSnapshot>(
          stream: _todayStatsStream,
          builder: (context, statsSnap) {
            double systemCash = 0.0;
            if (statsSnap.hasData && statsSnap.data!.exists) {
              final d = statsSnap.data!.data() as Map<String, dynamic>;
              systemCash = ((d['totalCash'] ?? 0.0) as num).toDouble();
            }

            return Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: gradientCard(gradient: AppGradients.blueAccent, radius: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 24),
                              const SizedBox(width: 8),
                              Text('Closing Summary',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(_todayLabel, style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
                          const SizedBox(height: 14),
                          Text('₹${systemCash.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                  color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text('Expected Cash in Register (System Total)',
                              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text('Count & Reconcile Cash',
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _cashController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                      decoration: darkInput(
                        label: 'Actual Cash in Drawer (INR)',
                        prefixIcon: Icons.currency_rupee_rounded,
                      ),
                      onChanged: (val) {
                        setState(() {}); // trigger discrepancy update
                      },
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (double.tryParse(v) == null || double.parse(v) < 0) {
                          return 'Enter a valid positive number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _noteController,
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                      maxLines: 2,
                      decoration: darkInput(
                        label: 'Add note (e.g. Reason for discrepancy)',
                        prefixIcon: Icons.note_alt_outlined,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildDiscrepancyDisplay(systemCash),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentBlue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: _isSubmitting ? null : () => _submitReconciliation(systemCash),
                        child: _isSubmitting
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text('Submit Closing Reconciliation',
                                style: GoogleFonts.poppins(
                                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDiscrepancyDisplay(double systemCash) {
    final actual = double.tryParse(_cashController.text) ?? 0.0;
    if (_cashController.text.isEmpty) return const SizedBox();

    final discrepancy = actual - systemCash;
    final isMatched = discrepancy == 0;
    final isNegative = discrepancy < 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMatched
            ? const Color(0xFF1B4332).withValues(alpha: 0.12)
            : isNegative
                ? AppColors.accentRed.withValues(alpha: 0.1)
                : AppColors.accentOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMatched
              ? const Color(0xFF1B4332).withValues(alpha: 0.3)
              : isNegative
                  ? AppColors.accentRed.withValues(alpha: 0.3)
                  : AppColors.accentOrange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            isMatched
                ? 'Status: Balanced'
                : isNegative
                    ? 'Status: Shortage'
                    : 'Status: Surplus',
            style: GoogleFonts.poppins(
              color: isMatched
                  ? AppColors.accentGreen
                  : isNegative
                      ? AppColors.accentRed
                      : AppColors.accentOrange,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          Text(
            '₹${discrepancy.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              color: isMatched
                  ? AppColors.accentGreen
                  : isNegative
                      ? AppColors.accentRed
                      : AppColors.accentOrange,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminHistoryView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _reconciliationHistoryStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accentBlue));
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Text('No reconciliation logs found.',
                style: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 14)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final dateStr = data['date'] ?? docs[i].id;
            final date = DateFormat('yyyy-MM-dd').parse(dateStr);
            final system = (data['systemCash'] ?? 0.0) as double;
            final actual = (data['actualCash'] ?? 0.0) as double;
            final discrepancy = (data['discrepancy'] ?? 0.0) as double;
            final note = data['note'] ?? '';
            final user = data['submittedBy'] ?? '';

            final isBalanced = discrepancy == 0;
            final isShortage = discrepancy < 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: glassCard(radius: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('dd MMMM yyyy').format(date),
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isBalanced
                              ? const Color(0xFF1B4332).withValues(alpha: 0.15)
                              : isShortage
                                  ? AppColors.accentRed.withValues(alpha: 0.12)
                                  : AppColors.accentOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isBalanced
                              ? 'Balanced'
                              : isShortage
                                  ? 'Shortage: ₹${discrepancy.abs().toStringAsFixed(0)}'
                                  : 'Surplus: ₹${discrepancy.toStringAsFixed(0)}',
                          style: GoogleFonts.poppins(
                            color: isBalanced
                                ? AppColors.accentGreen
                                : isShortage
                                    ? AppColors.accentRed
                                    : AppColors.accentOrange,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _colDetail('Expected (System)', '₹${system.toStringAsFixed(0)}'),
                      _colDetail('Actual counted', '₹${actual.toStringAsFixed(0)}'),
                      _colDetail('Discrepancy', '₹${discrepancy.toStringAsFixed(0)}',
                          valColor: isBalanced
                              ? AppColors.accentGreen
                              : isShortage
                                  ? AppColors.accentRed
                                  : AppColors.accentOrange),
                    ],
                  ),
                  const Divider(color: AppColors.bgDivider, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Submitted by $user',
                          style: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 10)),
                      if (note.isNotEmpty)
                        Expanded(
                          child: Text(
                            note,
                            style: GoogleFonts.poppins(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontStyle: FontStyle.italic),
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _rowDetail(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 13)),
        Text(value,
            style: GoogleFonts.poppins(
                color: valueColor ?? Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _colDetail(String label, String value, {Color? valColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: GoogleFonts.poppins(
                color: valColor ?? Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
