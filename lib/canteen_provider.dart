import 'package:cloud_firestore/cloud_firestore.dart';

class CanteenProvider {
  static String _selectedCanteenId = 'main';
  static String _selectedCanteenName = 'Main Canteen';
  static bool _isAdmin = false;

  static String get selectedCanteenId => _selectedCanteenId;
  static String get selectedCanteenName => _selectedCanteenName;
  static bool get isAdmin => _isAdmin;

  static Query<Map<String, dynamic>> scopeQuery(
      Query<Map<String, dynamic>> query) {
    if (_isAdmin) return query;
    return query.where('canteenId', isEqualTo: selectedCanteenId);
  }

  static String dailyStatsDocumentId(DateTime date, {String? canteenId}) =>
      '${_normalizedCanteenId(canteenId)}_${_dateKey(date)}';

  static String cashReconciliationDocumentId(DateTime date,
          {String? canteenId}) =>
      dailyStatsDocumentId(date, canteenId: canteenId);

  static String creditCustomerDocumentId(String phone, {String? canteenId}) =>
      '${_normalizedCanteenId(canteenId)}_${phone.trim()}';

  static String dateFromDailyStatsDocumentId(String documentId) {
    final separator = documentId.lastIndexOf('_');
    return separator < 0 ? documentId : documentId.substring(separator + 1);
  }

  static String _normalizedCanteenId(String? canteenId) {
    final normalized = (canteenId ?? _selectedCanteenId).trim();
    return normalized.isEmpty ? 'main' : normalized;
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static void setSelectedCanteen({
    required String id,
    required String name,
  }) {
    _selectedCanteenId = id.trim().isEmpty ? 'main' : id.trim();
    _selectedCanteenName = name.trim().isEmpty ? 'Main Canteen' : name.trim();
  }

  /// Loads the signed-in staff member's role and branch.
  ///
  /// Errors are intentionally NOT swallowed: silently falling back to the
  /// 'main' canteen on a network failure would attach a branch cashier to the
  /// wrong branch. Callers must handle the exception (e.g. show a retry).
  static Future<void> initializeForStaff(String staffId) async {
    final doc = await FirebaseFirestore.instance
        .collection('canteenStaff')
        .doc(staffId)
        .get();
    applyStaffData(doc.data());
  }

  /// Applies a staff document's fields. Split out so it can be unit-tested.
  static void applyStaffData(Map<String, dynamic>? data) {
    _isAdmin = data?['role'] == 'admin';
    final canteenId = (data?['canteenId'] ?? '').toString();
    final canteenName = (data?['canteenName'] ?? 'Main Canteen').toString();

    if (canteenId.isNotEmpty) {
      setSelectedCanteen(id: canteenId, name: canteenName);
    } else {
      setSelectedCanteen(id: 'main', name: 'Main Canteen');
    }
  }

  static bool matchesSelectedCanteen(Map<String, dynamic> data) {
    final docCanteenId = (data['canteenId'] ?? '').toString();
    final selectedId = selectedCanteenId;

    if (docCanteenId.isEmpty) return selectedId == 'main';
    if (selectedId == 'main') {
      return docCanteenId == 'main';
    }

    return docCanteenId == selectedId;
  }

  static bool matchesNotificationCanteen(Map<String, dynamic> data) {
    final docCanteenId = (data['canteenId'] ?? '').toString().trim();
    if (docCanteenId.isEmpty) return selectedCanteenId == 'main';
    return docCanteenId == selectedCanteenId;
  }
}
