import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'theme.dart';

class CreditDetailPage extends StatefulWidget {
  final String customerPhone;
  final String customerName;

  const CreditDetailPage({
    super.key,
    required this.customerPhone,
    required this.customerName,
  });

  @override
  State<CreditDetailPage> createState() => _CreditDetailPageState();
}

class _CreditDetailPageState extends State<CreditDetailPage> {
  double _totalPending = 0.0;
  bool _isProcessing = false;
  int _activeTab = 0; // 0 = Pending Bills, 1 = Repayment Logs
  late Stream<DocumentSnapshot> _customerStream;
  late Stream<QuerySnapshot> _billsStream;
  late Stream<QuerySnapshot> _repaymentsStream;

  @override
  void initState() {
    super.initState();
    _customerStream = FirebaseFirestore.instance
        .collection('creditCustomers')
        .doc(widget.customerPhone)
        .snapshots();
    _billsStream = FirebaseFirestore.instance
        .collection('bills')
        .where('customerPhone', isEqualTo: widget.customerPhone)
        .where('creditStatus', isEqualTo: 'Pending')
        .snapshots();
    _repaymentsStream = FirebaseFirestore.instance
        .collection('repayments')
        .where('customerPhone', isEqualTo: widget.customerPhone)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: buildGradientAppBar(title: 'Credit Details'),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _customerStream,
        builder: (context, customerSnap) {
          double currentTotalPending = 0.0;
          if (customerSnap.hasData && customerSnap.data!.exists) {
            final data = customerSnap.data!.data() as Map<String, dynamic>;
            currentTotalPending = (data['totalPending'] ?? 0.0).toDouble();
          }
          
          // Update instance variable so dialog can use it
          _totalPending = currentTotalPending;

          return Column(
            children: [
              // Customer Header
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppGradients.brand,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.gradBlue.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10))
                  ],
                ),
                child: Column(
                  children: [
                    Text(widget.customerName,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(widget.customerPhone,
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 16),
                    Text('Total Pending',
                        style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    Text('₹${currentTotalPending.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),

              // Tab Selector (Pending Bills / Repayments)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _activeTab = 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              gradient: _activeTab == 0 ? AppGradients.blueAccent : null,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Pending Bills',
                              style: GoogleFonts.poppins(
                                color: _activeTab == 0 ? Colors.white : AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _activeTab = 1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              gradient: _activeTab == 1 ? AppGradients.orangeAccent : null,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Repayments',
                              style: GoogleFonts.poppins(
                                color: _activeTab == 1 ? Colors.white : AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Active Tab Content
              Expanded(
                child: _activeTab == 0
                    ? _buildPendingBillsList()
                    : _buildRepaymentsList(),
              ),

              // Pay Now Button
              if (currentTotalPending > 0)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentGreen,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed:
                            _isProcessing ? null : () => _showRepaymentDialog(),
                        child: _isProcessing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Text('Pay Now',
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showRepaymentDialog() async {
    final amountCtrl = TextEditingController();
    String paymentMode = 'Cash'; // Default

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: const Color(0xFF111827),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Receive Payment',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 24),
                  Text('Amount Received',
                      style: GoogleFonts.poppins(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: amountCtrl,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            prefixText: '₹ ',
                            prefixStyle: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600),
                            filled: true,
                            fillColor: AppColors.bgInput,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              AppColors.accentBlue.withValues(alpha: 0.2),
                          foregroundColor: AppColors.accentBlue,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          amountCtrl.text = _totalPending.toStringAsFixed(2);
                        },
                        child: Text('Full',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Payment Mode',
                      style: GoogleFonts.poppins(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setDialogState(() => paymentMode = 'Cash'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: paymentMode == 'Cash'
                                  ? const Color(0xFF00C853)
                                      .withValues(alpha: 0.2)
                                  : AppColors.bgInput,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: paymentMode == 'Cash'
                                      ? const Color(0xFF00C853)
                                      : AppColors.glassBorder),
                            ),
                            alignment: Alignment.center,
                            child: Text('Cash',
                                style: GoogleFonts.poppins(
                                    color: paymentMode == 'Cash'
                                        ? const Color(0xFF00C853)
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setDialogState(() => paymentMode = 'UPI'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: paymentMode == 'UPI'
                                  ? AppColors.accentBlue.withValues(alpha: 0.2)
                                  : AppColors.bgInput,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: paymentMode == 'UPI'
                                      ? AppColors.accentBlue
                                      : AppColors.glassBorder),
                            ),
                            alignment: Alignment.center,
                            child: Text('UPI',
                                style: GoogleFonts.poppins(
                                    color: paymentMode == 'UPI'
                                        ? AppColors.accentBlue
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Cancel',
                              style: GoogleFonts.poppins(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentGreen,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            final amount =
                                double.tryParse(amountCtrl.text) ?? 0.0;
                            if (amount > 0 && amount <= _totalPending) {
                              Navigator.pop(context);
                              _processRepayment(amount, paymentMode);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Invalid amount')));
                            }
                          },
                          child: Text('Confirm',
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _processRepayment(double amount, String paymentMode) async {
    setState(() => _isProcessing = true);
    final db = FirebaseFirestore.instance;

    try {
      await db.runTransaction((tx) async {
        // 1. Fetch pending bills
        final billsSnap = await db.collection('bills')
            .where('customerPhone', isEqualTo: widget.customerPhone)
            .where('creditStatus', isEqualTo: 'Pending')
            .get(); 

        List<DocumentSnapshot> billDocs = [];
        for (var doc in billsSnap.docs) {
          billDocs.add(await tx.get(doc.reference));
        }
        
        // Sort bills locally to apply payments to oldest bills first
        billDocs.sort((a, b) {
          final tsA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final tsB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (tsA == null && tsB == null) return 0;
          if (tsA == null) return -1;
          if (tsB == null) return 1;
          return tsA.compareTo(tsB);
        });

        final customerRef =
            db.collection('creditCustomers').doc(widget.customerPhone);
        final customerSnap = await tx.get(customerRef);

        final todayId = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final statRef = db.collection('dailyStats').doc(todayId);

        // 2. Distribute payment
        double remainingAmount = amount;
        for (var doc in billDocs) {
          if (remainingAmount <= 0) break;

          final data = doc.data() as Map<String, dynamic>;
          double billPending =
              (data['pendingAmount'] ?? data['totalAmount'] ?? 0.0).toDouble();

          if (remainingAmount >= billPending) {
            // Bill fully paid
            remainingAmount -= billPending;
            tx.update(doc.reference, {
              'pendingAmount': 0.0,
              'creditStatus': 'Paid',
            });
          } else {
            // Bill partially paid
            tx.update(doc.reference, {
              'pendingAmount': billPending - remainingAmount,
            });
            remainingAmount = 0;
          }
        }

        // 3. Update customer total
        if (customerSnap.exists) {
          tx.update(customerRef, {
            'totalPending': FieldValue.increment(-amount),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }

        // 3.5. Create repayment audit log document
        final repaymentRef = db.collection('repayments').doc();
        tx.set(repaymentRef, {
          'customerPhone': widget.customerPhone,
          'customerName': widget.customerName,
          'amount': amount,
          'paymentMode': paymentMode,
          'timestamp': FieldValue.serverTimestamp(),
          'processedBy': FirebaseAuth.instance.currentUser?.email ?? 'Unknown',
        });

        // 4. Update daily stats (only add to cash/upi, DO NOT add to totalSales)
        tx.set(
          statRef,
          {
            if (paymentMode == 'Cash')
              'totalCash': FieldValue.increment(amount),
            if (paymentMode == 'UPI') 'totalUpi': FieldValue.increment(amount),
            'creditReceived': FieldValue.increment(amount),
            'lastUpdated': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Payment of ₹${amount.toStringAsFixed(2)} successful!'),
        backgroundColor: const Color(0xFF1B4332),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AppColors.accentRed,
      ));
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Widget _buildPendingBillsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _billsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accentBlue));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
        }

        var docs = snapshot.data?.docs ?? [];
        docs.sort((a, b) {
          final tsA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final tsB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (tsA == null && tsB == null) return 0;
          if (tsA == null) return -1;
          if (tsB == null) return 1;
          return tsA.compareTo(tsB);
        });

        if (docs.isEmpty) {
          return Center(
            child: Text('No pending bills found', style: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 15)),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final ts = data['timestamp'] as Timestamp?;
            final dateStr = ts != null ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate()) : 'Unknown Date';
            final billNum = data['billNumber']?.toString() ?? '-';
            final pendingAmt = (data['pendingAmount'] ?? data['totalAmount'] ?? 0.0).toDouble();
            final items = List<Map<String, dynamic>>.from(data['items'] ?? []);

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: glassCard(radius: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Bill #$billNum', style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      Text('₹${pendingAmt.toStringAsFixed(2)}', style: GoogleFonts.poppins(color: AppColors.accentRed, fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(dateStr, style: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 11)),
                  const Divider(color: AppColors.bgDivider, height: 20),
                  ...items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text('${item['quantity']}x ${item['name']}', style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 12))),
                          Text('₹${(item['subtotal'] ?? 0.0).toStringAsFixed(0)}', style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 12)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRepaymentsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _repaymentsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accentBlue));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
        }

        var docs = snapshot.data?.docs ?? [];
        docs.sort((a, b) {
          final tsA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final tsB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (tsA == null && tsB == null) return 0;
          if (tsA == null) return 1; // puts nulls at end
          if (tsB == null) return -1;
          return tsB.compareTo(tsA); // newest repayment first
        });

        if (docs.isEmpty) {
          return Center(
            child: Text('No repayment history found', style: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 15)),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final ts = data['timestamp'] as Timestamp?;
            final dateStr = ts != null ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate()) : 'Unknown Date';
            final amount = (data['amount'] ?? 0.0).toDouble();
            final mode = data['paymentMode'] ?? 'Cash';
            final user = data['processedBy'] ?? 'Staff';

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: glassCard(radius: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accentGreen.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      mode == 'Cash' ? Icons.money_rounded : Icons.phone_android_rounded,
                      color: AppColors.accentGreen,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cleared via $mode', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(dateStr, style: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 11)),
                        Text('By: $user', style: GoogleFonts.poppins(color: AppColors.textHint, fontSize: 10)),
                      ],
                    ),
                  ),
                  Text(
                    '+₹${amount.toStringAsFixed(0)}',
                    style: GoogleFonts.poppins(color: AppColors.accentGreen, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
