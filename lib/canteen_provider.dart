import 'package:cloud_firestore/cloud_firestore.dart';

class CanteenProvider {
  static String _selectedCanteenId = 'main';
  static String _selectedCanteenName = 'Main Canteen';

  static String get selectedCanteenId => _selectedCanteenId;
  static String get selectedCanteenName => _selectedCanteenName;

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

    if (selectedId == 'main') {
      return docCanteenId.isEmpty || docCanteenId == 'main';
    }

    return docCanteenId.isEmpty || docCanteenId == selectedId;
  }
}
