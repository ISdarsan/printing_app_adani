import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'theme.dart';
import 'report_records.dart' show asDouble;
import 'money.dart';
import 'sync_status.dart';
import 'canteen_provider.dart';
import 'business_time.dart';

class _AlreadyReconciledException implements Exception {}

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

  String get _todayId => BusinessTime.dateKey(DateTime.now());
  String get _todayRecordId =>
      CanteenProvider.cashReconciliationDocumentId(DateTime.now());
  String get _todayLabel => DateFormat('dd MMMM yyyy').format(DateTime.now());

  late Stream<Map<String, dynamic>?> _todayStatsStream;
  late Stream<Map<String, dynamic>?> _todayReconciliationStream;
  late Stream<QuerySnapshot> _reconciliationHistoryStream;

  @override
  void initState() {
    super.initState();
    // Branch-scoped queries instead of document streams: a cashier cannot read
    // a document that does not exist yet, and a failed stream ends for good, so
    // the screen would never notice the closing being submitted. A query just
    // returns nothing and then the new record. Equality filters only.
    Stream<Map<String, dynamic>?> today(String collection) => FirebaseFirestore
        .instance
        .collection(collection)
        .where('canteenId', isEqualTo: CanteenProvider.selectedCanteenId)
        .where('date', isEqualTo: _todayId)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isEmpty ? null : s.docs.first.data());
    _todayStatsStream = today('dailyStats');
    _todayReconciliationStream = today('cashReconciliations');

    Query<Map<String, dynamic>> historyQuery =
        FirebaseFirestore.instance.collection('cashReconciliations');
    if (!widget.isAdmin) {
      historyQuery = historyQuery.where('canteenId',
          isEqualTo: CanteenProvider.selectedCanteenId);
    }
    _reconciliationHistoryStream = historyQuery
        .orderBy('timestamp', descending: true)
        .limit(30)
        .snapshots();
  }

  Future<void> _submitReconciliation(double systemCash) async {
    if (_isSubmitting) return; // duplicate tap
    if (!_formKey.currentState!.validate()) return;
    final actual = double.tryParse(_cashController.text);
    if (actual == null || actual < 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('Please enter a valid cash amount', style: AppText.style()),
        backgroundColor: AppColors.accentRed,
      ));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // Rounded to the paisa: floating point noise must not turn an exact
      // count into a 0.0000000000001 "shortage" in the audit log.
      final discrepancy = roundMoney(actual - systemCash);
      final reconciliationRef = FirebaseFirestore.instance
          .collection('cashReconciliations')
          .doc(_todayRecordId);
      var alreadyMine = false;
      await SyncTracker.instance.track<void>(
        key: 'closing:$_todayRecordId',
        label: 'Cash closing ₹${actual.toStringAsFixed(2)} for $_todayLabel',
        safeToRetry: false,
        run: () async {
        // Already closed today? Asked with a branch-scoped query (cashiers cannot
        // read a missing document). If a previous attempt of THIS submission
        // did commit but its acknowledgement was lost, the record is ours:
        // report success instead of "already submitted".
        final prior = await FirebaseFirestore.instance
            .collection('cashReconciliations')
            .where('canteenId', isEqualTo: CanteenProvider.selectedCanteenId)
            .where('date', isEqualTo: _todayId)
            .limit(1)
            .get(const GetOptions(source: Source.server));
        if (prior.docs.isNotEmpty) {
          final d = prior.docs.first.data();
          alreadyMine =
              d['submittedBy'] == FirebaseAuth.instance.currentUser?.email &&
                  moneyEquals(asDouble(d['actualCash']), actual);
          if (alreadyMine) return;
          throw _AlreadyReconciledException();
        }
        // Create-only: the record id is fixed per branch and day, so a second
        // create is an UPDATE to the rules, which cashiers may not do. A
        // transaction (not a plain set) so that it fails when offline instead
        // of being queued.
        await FirebaseFirestore.instance.runTransaction((transaction) async {
        transaction.set(reconciliationRef, {
          'date': _todayId,
          'canteenId': CanteenProvider.selectedCanteenId,
          'canteenName': CanteenProvider.selectedCanteenName,
          'systemCash': roundMoney(systemCash),
          'actualCash': roundMoney(actual),
          'discrepancy': discrepancy,
          'note': _noteController.text.trim(),
          'submittedBy':
              FirebaseAuth.instance.currentUser?.email ?? 'Unknown Cashier',
          // Required by the security rules: the closing is signed with the
          // caller's uid, so it cannot be filed in someone else's name.
          'submittedByUid': FirebaseAuth.instance.currentUser?.uid,
          'timestamp': FieldValue.serverTimestamp(),
        });
        });
        },
      );

      _cashController.clear();
      _noteController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reconciliation submitted successfully!',
              style: AppText.style()),
          backgroundColor: const Color(0xFF1B4332),
        ));
      }
    } on _AlreadyReconciledException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'A cash reconciliation has already been submitted for this canteen today.',
              style: AppText.style()),
          backgroundColor: AppColors.accentOrange,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: AppText.style()),
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
        title:
            widget.isAdmin ? 'Cash Reconciliation Logs' : 'Daily Cash Closing',
        centerTitle: true,
      ),
      body: widget.isAdmin
          ? _buildAdminHistoryView()
          : _buildCashierSubmissionView(),
    );
  }

  Widget _buildCashierSubmissionView() {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _todayReconciliationStream,
      builder: (context, reconSnap) {
        if (reconSnap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accentBlue));
        }

        // If today is already reconciled, show status and details
        if (reconSnap.data != null) {
          final data = reconSnap.data!;
          final system = asDouble(data['systemCash']);
          final actual = asDouble(data['actualCash']);
          final discrepancy = asDouble(data['discrepancy']);
          final note = data['note'] ?? '';
          final user = data['submittedBy'] ?? '';
          final ts = data['timestamp'] as Timestamp?;
          final timeStr =
              ts != null ? DateFormat('hh:mm a').format(ts.toDate()) : '';

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
                      border:
                          Border.all(color: const Color(0xFF1B4332), width: 2),
                    ),
                    child: const Icon(Icons.check_circle_outline_rounded,
                        color: Color(0xFF2D6A4F), size: 48),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Reconciled for Today',
                    style: AppText.style(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text('Submitted by $user at $timeStr',
                    style: AppText.style(
                        color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: glassCard(radius: 20),
                  child: Column(
                    children: [
                      _rowDetail('Reconciliation Date', _todayLabel),
                      const Divider(color: AppColors.bgDivider, height: 24),
                      _rowDetail('System Cash Recorded',
                          '₹${system.toStringAsFixed(2)}'),
                      const Divider(color: AppColors.bgDivider, height: 24),
                      _rowDetail('Actual Cash Counted',
                          '₹${actual.toStringAsFixed(2)}'),
                      const Divider(color: AppColors.bgDivider, height: 24),
                      _rowDetail(
                        'Discrepancy',
                        '₹${discrepancy.toStringAsFixed(2)}',
                        valueColor: toPaise(discrepancy) == 0
                            ? AppColors.accentGreen
                            : toPaise(discrepancy) < 0
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
        return StreamBuilder<Map<String, dynamic>?>(
          stream: _todayStatsStream,
          builder: (context, statsSnap) {
            double systemCash = 0.0;
            final d = statsSnap.data;
            if (d != null) {
              systemCash = asDouble(d['totalCash']);
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
                      decoration: gradientCard(
                          gradient: AppGradients.blueAccent, radius: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.account_balance_wallet_outlined,
                                  color: Colors.white, size: 24),
                              const SizedBox(width: 8),
                              Text('Closing Summary',
                                  style: AppText.style(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(_todayLabel,
                              style: AppText.style(
                                  color: Colors.white60, fontSize: 12)),
                          const SizedBox(height: 14),
                          Text('₹${systemCash.toStringAsFixed(2)}',
                              style: AppText.style(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text('Expected Cash in Register (System Total)',
                              style: AppText.style(
                                  color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text('Count & Reconcile Cash',
                        style: AppText.style(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _cashController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: AppText.style(color: Colors.white, fontSize: 14),
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
                      style: AppText.style(color: Colors.white, fontSize: 14),
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
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: _isSubmitting
                            ? null
                            : () => _submitReconciliation(systemCash),
                        child: _isSubmitting
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : Text('Submit Closing Reconciliation',
                                style: AppText.style(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
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

    final discrepancy = roundMoney(actual - systemCash);
    final isMatched = toPaise(discrepancy) == 0;
    final isNegative = toPaise(discrepancy) < 0;

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
            style: AppText.style(
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
            style: AppText.style(
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
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accentBlue));
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Text('No reconciliation logs found.',
                style: AppText.style(color: AppColors.textHint, fontSize: 14)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final dateStr = data['date'] ?? docs[i].id;
            final date = DateFormat('yyyy-MM-dd').parse(dateStr);
            final system = asDouble(data['systemCash']);
            final actual = asDouble(data['actualCash']);
            final discrepancy = asDouble(data['discrepancy']);
            final note = data['note'] ?? '';
            final user = data['submittedBy'] ?? '';

            // Read-time paise comparison also fixes old records that were
            // stored with floating point dust (no data is rewritten).
            final isBalanced = toPaise(discrepancy) == 0;
            final isShortage = toPaise(discrepancy) < 0;

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
                          style: AppText.style(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isBalanced
                              ? const Color(0xFF1B4332).withValues(alpha: 0.15)
                              : isShortage
                                  ? AppColors.accentRed.withValues(alpha: 0.12)
                                  : AppColors.accentOrange
                                      .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isBalanced
                              ? 'Balanced'
                              : isShortage
                                  ? 'Shortage: ₹${discrepancy.abs().toStringAsFixed(0)}'
                                  : 'Surplus: ₹${discrepancy.toStringAsFixed(0)}',
                          style: AppText.style(
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
                      _colDetail(
                          'Expected (System)', '₹${system.toStringAsFixed(0)}'),
                      _colDetail(
                          'Actual counted', '₹${actual.toStringAsFixed(0)}'),
                      _colDetail(
                          'Discrepancy', '₹${discrepancy.toStringAsFixed(0)}',
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
                          style: AppText.style(
                              color: AppColors.textHint, fontSize: 10)),
                      if (note.isNotEmpty)
                        Expanded(
                          child: Text(
                            note,
                            style: AppText.style(
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
        Text(label,
            style: AppText.style(color: AppColors.textSecondary, fontSize: 13)),
        Text(value,
            style: AppText.style(
                color: valueColor ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _colDetail(String label, String value, {Color? valColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppText.style(color: AppColors.textHint, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: AppText.style(
                color: valColor ?? Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}
