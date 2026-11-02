import 'package:canteen_adani/business_time.dart';
import 'package:canteen_adani/canteen_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bill saved just before / after IST midnight must land in the right
/// dailyStats document, whatever the phone's timezone is.
void main() {
  group('dailyStats / reconciliation ids at the midnight boundary', () {
    test('23:59:59.999 IST belongs to the old day, 00:00 IST to the new', () {
      final lastMs = DateTime.utc(2026, 11, 2, 18, 29, 59, 999); // IST 23:59:59.999
      final firstMs = DateTime.utc(2026, 11, 2, 18, 30); // IST 00:00 next day
      expect(CanteenProvider.dailyStatsDocumentId(lastMs, canteenId: 'north'),
          'north_2026-11-02');
      expect(CanteenProvider.dailyStatsDocumentId(firstMs, canteenId: 'north'),
          'north_2026-11-03');
    });

    test('month-end: 31 Oct 23:59 IST vs 1 Nov 00:00 IST', () {
      expect(
          CanteenProvider.dailyStatsDocumentId(
              DateTime.utc(2026, 10, 31, 18, 29, 59),
              canteenId: 'main'),
          'main_2026-10-31');
      expect(
          CanteenProvider.dailyStatsDocumentId(
              DateTime.utc(2026, 10, 31, 18, 30),
              canteenId: 'main'),
          'main_2026-11-01');
    });

    test('reconciliation id always equals the dailyStats id', () {
      final i = DateTime.utc(2026, 12, 31, 20, 0); // already 1 Jan in IST
      expect(CanteenProvider.cashReconciliationDocumentId(i, canteenId: 'x'),
          CanteenProvider.dailyStatsDocumentId(i, canteenId: 'x'));
      expect(CanteenProvider.dailyStatsDocumentId(i, canteenId: 'x'),
          'x_2027-01-01');
    });

    test('a bill, its dailyStats id and the day query agree', () {
      final billTime = DateTime.utc(2026, 11, 2, 18, 29, 59, 500);
      final id = CanteenProvider.dailyStatsDocumentId(billTime, canteenId: 'a');
      final day = BusinessTime.dayRange(billTime);
      expect(day.contains(billTime), isTrue);
      expect(CanteenProvider.dateFromDailyStatsDocumentId(id),
          BusinessTime.dateKey(day.start.add(const Duration(hours: 1))));
    });
  });

  group('branch scoping helper', () {
    test('cashier scope uses the staff canteen, admin is unscoped', () {
      CanteenProvider.applyStaffData(
          {'role': 'cashier', 'canteenId': 'north', 'canteenName': 'North'});
      expect(CanteenProvider.isAdmin, isFalse);
      expect(CanteenProvider.selectedCanteenId, 'north');
      CanteenProvider.applyStaffData({'role': 'admin'});
      expect(CanteenProvider.isAdmin, isTrue);
    });
  });
}
