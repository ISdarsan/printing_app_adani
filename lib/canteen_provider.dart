import 'package:cloud_firestore/cloud_firestore.dart';

class CanteenProvider {
  static String _selectedCanteenId = 'main';
  static String _selectedCanteenName = 'Main Canteen';

  static String get selectedCanteenId => _selectedCanteenId;
  static String get selectedCanteenName => _selectedCanteenName;

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

  static Future<void> initializeForStaff(String staffId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('canteenStaff')
          .doc(staffId)
          .get();

      final data = doc.data();
      final canteenId = (data?['canteenId'] ?? '').toString();
      final canteenName = (data?['canteenName'] ?? 'Main Canteen').toString();

      if (canteenId.isNotEmpty) {
        setSelectedCanteen(id: canteenId, name: canteenName);
      } else {
        setSelectedCanteen(id: 'main', name: 'Main Canteen');
      }
    } catch (_) {
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
