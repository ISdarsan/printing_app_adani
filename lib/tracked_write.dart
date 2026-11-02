import 'package:cloud_firestore/cloud_firestore.dart';

import 'sync_status.dart';

/// Firestore binding for [trackedConfirmedWrite]: `set` on a reference whose id
/// was chosen once up front (`collection.doc()`), so repeating it can never
/// create a second record.
Future<bool> saveTracked(
  DocumentReference<Map<String, dynamic>> ref,
  Map<String, dynamic> data, {
  required String label,
  Duration wait = const Duration(seconds: 8),
}) =>
    trackedConfirmedWrite(
      key: '${ref.parent.id}:${ref.id}',
      label: label,
      wait: wait,
      write: () => ref.set(data),
      existsOnServer: () async =>
          (await ref.get(const GetOptions(source: Source.server))).exists,
    );
