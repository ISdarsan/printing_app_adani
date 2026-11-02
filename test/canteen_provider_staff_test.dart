import 'package:canteen_adani/canteen_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CanteenProvider.applyStaffData', () {
    test('branch cashier is scoped to their own canteen, not admin', () {
      CanteenProvider.applyStaffData(
          {'role': 'cashier', 'canteenId': 'north', 'canteenName': 'North'});
      expect(CanteenProvider.isAdmin, isFalse);
      expect(CanteenProvider.selectedCanteenId, 'north');
      expect(CanteenProvider.selectedCanteenName, 'North');
    });

    test('admin flag is set only for role == admin', () {
      CanteenProvider.applyStaffData({'role': 'admin'});
      expect(CanteenProvider.isAdmin, isTrue);
      expect(CanteenProvider.selectedCanteenId, 'main');
      CanteenProvider.applyStaffData({'role': 'cashier'});
      expect(CanteenProvider.isAdmin, isFalse);
    });

    test('missing document data defaults to non-admin main canteen', () {
      CanteenProvider.applyStaffData(null);
      expect(CanteenProvider.isAdmin, isFalse);
      expect(CanteenProvider.selectedCanteenId, 'main');
    });
  });
}
