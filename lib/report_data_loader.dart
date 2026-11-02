import 'package:cloud_firestore/cloud_firestore.dart';

import 'business_time.dart';
import 'export_range.dart';
import 'paged_fetch.dart';
import 'report_records.dart';

/// Builds a Firestore [PageFetcher]: ordered query, cursor = last document,
/// each document mapped immediately to a small record (so page buffers, and
/// large fields such as `proofImageBase64`, can be garbage collected).
///
/// `Source.server` is deliberate for exports: offline, the read fails and the
/// export reports it, rather than silently producing a report from a partial
/// local cache.
PageFetcher<R> firestorePageFetcher<R>(
  Query<Map<String, dynamic>> ordered,
  R Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) map,
) {
  return (cursor, limit) async {
    var q = ordered;
    if (cursor != null) {
      q = q.startAfterDocument(cursor as DocumentSnapshot<Map<String, dynamic>>);
    }
    final snap = await q.limit(limit).get(const GetOptions(source: Source.server));
    final docs = snap.docs;
    return PageResult<R>(
      docs.map(map).toList(),
      docs.isEmpty ? cursor : docs.last,
      docs.length == limit,
    );
  };
}

/// Reads everything the Excel report needs, page by page, for [range].
///
/// Admin only (unscoped collection reads; rules allow this for admins).
/// Ordering is `timestamp desc` and the cursor is the last document, so Firestore's
/// implicit `__name__` tiebreak makes pages contiguous: equal timestamps can
/// neither be skipped nor repeated.
class ReportDataLoader {
  final FirebaseFirestore db;
  const ReportDataLoader(this.db);

  static const _billPage = 500;
  // Expense documents carry a base64 proof photo, so keep pages small.
  static const _expensePage = 40;

  Query<Map<String, dynamic>> _timeOrdered(String collection, DateRange? r) {
    Query<Map<String, dynamic>> q = db.collection(collection);
    if (r != null) {
      q = q
          .where('timestamp', isGreaterThanOrEqualTo: r.start)
          .where('timestamp', isLessThan: r.end);
    }
    return q.orderBy('timestamp', descending: true);
  }

  Future<ReportData> load({
    required ExportRange range,
    void Function(String stage, int count)? onProgress,
    bool Function()? isCancelled,
    int maxRowsPerCollection = 200000,
  }) async {
    final r = range.range;
    final truncatedIn = <String>[];

    Future<List<T>> run<T>(
      String stage,
      Query<Map<String, dynamic>> q,
      T Function(QueryDocumentSnapshot<Map<String, dynamic>>) map,
      String Function(T) keyOf, {
      int pageSize = _billPage,
    }) async {
      final res = await fetchAllPages<T>(
        fetchPage: firestorePageFetcher<T>(q, map),
        pageSize: pageSize,
        maxItems: maxRowsPerCollection,
        isCancelled: isCancelled,
        keyOf: keyOf,
        onProgress: (n) => onProgress?.call(stage, n),
      );
      if (res.truncated) truncatedIn.add(stage);
      return res.items;
    }

    final topItems = <String, int>{};
    final bills = await run<BillRow>(
      'bills',
      _timeOrdered('bills', r),
      (d) {
        final data = d.data();
        accumulateTopItems(topItems, data['items']);
        return BillRow.fromMap(data, id: d.id);
      },
      (b) => b.id,
    );
    final expenses = await run<ExpenseRow>(
      'expenses',
      _timeOrdered('expenses', r),
      (d) => ExpenseRow.fromMap(d.data(), id: d.id),
      (e) => e.id,
      pageSize: _expensePage,
    );
    final repayments = await run<RepaymentRow>(
      'repayments',
      _timeOrdered('repayments', r),
      (d) => RepaymentRow.fromMap(d.data(), id: d.id),
      (x) => x.id,
    );
    final recons = await run<ReconRow>(
      'cash reconciliations',
      _timeOrdered('cashReconciliations', r),
      (d) => ReconRow.fromMap(d.data(), id: d.id),
      (x) => x.id,
    );
    // Credit balances are "as of now", not period data.
    final credits = await run<CreditRow>(
      'credit customers',
      db.collection('creditCustomers').orderBy('totalPending', descending: true),
      (d) => CreditRow.fromMap(d.data(), id: d.id),
      (x) => x.id,
    );

    final names = <String, String>{'main': 'Main Canteen'};
    final canteens =
        await db.collection('canteens').get(const GetOptions(source: Source.server));
    for (final c in canteens.docs) {
      names[c.id] = (c.data()['name'] ?? c.id).toString();
    }

    var label = range.periodLabel;
    if (truncatedIn.isNotEmpty) {
      label += ' (INCOMPLETE: row limit reached for ${truncatedIn.join(', ')})';
    }
    return ReportData(
      bills: bills,
      expenses: expenses,
      credits: credits,
      repayments: repayments,
      recons: recons,
      topItems: topItems,
      canteenNames: names,
      periodLabel: label,
    );
  }
}
