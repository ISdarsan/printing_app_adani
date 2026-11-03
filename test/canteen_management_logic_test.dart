import 'package:canteen_adani/canteen_management_logic.dart';
import 'package:flutter_test/flutter_test.dart';

const mainC = CanteenInfo('main', 'Main Canteen');
const north = CanteenInfo('north', 'North Canteen');
const south = CanteenInfo('south', 'South Canteen');

StaffMember admin(String email, {String canteen = 'main'}) =>
    StaffMember(uid: 'a-$email', email: email, role: 'admin', canteenId: canteen, canteenName: canteen);
StaffMember cashier(String email, String canteen) =>
    StaffMember(uid: 'c-$email', email: email, role: 'cashier', canteenId: canteen, canteenName: canteen);

void main() {
  group('admins are assigned to every canteen automatically', () {
    final staff = [
      cashier('zed@x.com', 'north'),
      admin('boss@x.com'), // saved under main
      cashier('amy@x.com', 'main'),
      cashier('raj@x.com', 'south'),
    ];

    test('an admin appears under EVERY canteen, whatever canteen is stored on their record', () {
      for (final c in ['main', 'north', 'south', 'a_canteen_created_tomorrow']) {
        expect(staffForCanteen(staff, c).any((s) => s.email == 'boss@x.com'), isTrue, reason: c);
      }
    });

    test('a cashier appears only under their own canteen', () {
      expect(staffForCanteen(staff, 'north').map((s) => s.email), ['boss@x.com', 'zed@x.com']);
      expect(staffForCanteen(staff, 'south').map((s) => s.email), ['boss@x.com', 'raj@x.com']);
      expect(staffForCanteen(staff, 'main').map((s) => s.email), ['boss@x.com', 'amy@x.com']);
    });

    test('a canteen with no cashiers still lists the admin (never "No staff")', () {
      expect(staffForCanteen(staff, 'brand_new').map((s) => s.email), ['boss@x.com']);
    });

    test('admins first, then by e-mail ignoring case', () {
      final s = [cashier('b@x.com', 'n'), cashier('A@x.com', 'n'), admin('z@x.com')];
      expect(staffForCanteen(s, 'n').map((x) => x.email), ['z@x.com', 'A@x.com', 'b@x.com']);
    });

    test('an admin is labelled "All canteens", a cashier by their canteen', () {
      expect(staffCanteenLabel(admin('boss@x.com')), 'All canteens');
      expect(staffCanteenLabel(cashier('amy@x.com', 'north')), 'north');
      expect(staffCanteenLabel(const StaffMember(uid: 'u', email: 'e', role: 'cashier', canteenId: 'north', canteenName: 'North Canteen')), 'North Canteen');
    });

    test('a staff record without a canteen id is shown under main (as before)', () {
      final s = StaffMember.fromMap('u1', {'email': 'old@x.com', 'role': 'cashier'});
      expect(s.canteenId, 'main');
      expect(StaffMember.fromMap('u2', {'role': 'admin', 'canteenId': ''}).canteenId, 'main');
      expect(StaffMember.fromMap('u3', {}).role, 'cashier'); // default role
    });
  });

  group('planCanteenDelete', () {
    final all = [mainC, north, south];

    test('a canteen with no cashiers can be deleted, admins never block it', () {
      final p = planCanteenDelete(canteenId: 'north', canteens: all, staff: [admin('boss@x.com', canteen: 'north'), cashier('amy@x.com', 'main')]);
      expect(p.allowed, isTrue);
      expect(p.cashiers, isEmpty);
      expect(p.moveTo, isNull);
      expect(p.message, contains('No cashiers are assigned to "North Canteen"'));
      expect(p.message, contains('Admins keep access to every canteen'));
      expect(p.message, contains('bills, expenses and menu items are not deleted'));
    });

    test('cashiers of another canteen are moved to Main (the earlier behaviour)', () {
      final p = planCanteenDelete(canteenId: 'north', canteens: all, staff: [cashier('zed@x.com', 'north'), cashier('amy@x.com', 'main')]);
      expect(p.allowed, isTrue);
      expect(p.moveTo, mainC);
      expect(p.cashiers.map((s) => s.email), ['zed@x.com']);
      expect(p.message, contains('1 cashier (zed@x.com) will be moved to "Main Canteen"'));
    });

    test('MAIN can be deleted when no cashier is assigned to it', () {
      final p = planCanteenDelete(canteenId: 'main', canteens: all, staff: [admin('boss@x.com'), cashier('zed@x.com', 'north')]);
      expect(p.allowed, isTrue);
      expect(p.moveTo, isNull);
    });

    test('MAIN cannot be deleted while a cashier is assigned to it: nobody is left without a canteen', () {
      final p = planCanteenDelete(canteenId: 'main', canteens: all, staff: [admin('boss@x.com'), cashier('amy@x.com', 'main'), cashier('bob@x.com', 'main')]);
      expect(p.allowed, isFalse);
      expect(p.moveTo, isNull);
      expect(p.message, contains('2 cashiers are still assigned to "Main Canteen"'));
      expect(p.message, contains('amy@x.com'));
      expect(p.message, contains('Reassign Canteen'));
    });

    test('cashiers are NOT silently moved to Main once Main has been deleted: the delete is blocked', () {
      final p = planCanteenDelete(canteenId: 'north', canteens: [north, south], staff: [cashier('zed@x.com', 'north')]);
      expect(p.allowed, isFalse);
      expect(p.moveTo, isNull);
    });

    test('a staff record with no canteen counts as main when deciding', () {
      final legacy = StaffMember.fromMap('u', {'email': 'old@x.com', 'role': 'cashier'});
      expect(planCanteenDelete(canteenId: 'main', canteens: all, staff: [legacy]).allowed, isFalse);
    });

    test('many cashiers: the message lists a few names and counts the rest', () {
      final many = [for (var i = 0; i < 7; i++) cashier('c$i@x.com', 'main')];
      final p = planCanteenDelete(canteenId: 'main', canteens: all, staff: many);
      expect(p.allowed, isFalse);
      expect(p.message, contains('7 cashiers'));
      expect(p.message, contains('and 3 more'));
    });

    test('deleting the last canteen is allowed when it has no cashiers', () {
      expect(planCanteenDelete(canteenId: 'north', canteens: [north], staff: [admin('boss@x.com')]).allowed, isTrue);
    });
  });

  group('validCanteenSelection (a dropdown must never get a value it does not list)', () {
    test('keeps a still-existing choice', () {
      expect(validCanteenSelection('north', [mainC, north]), north);
    });
    test('a deleted canteen falls back to the first one instead of crashing the dropdown', () {
      expect(validCanteenSelection('main', [north, south]), north);
      expect(validCanteenSelection(null, [north, south]), north);
    });
    test('no canteens at all gives null (the screen says "add a canteen")', () {
      expect(validCanteenSelection('main', const []), isNull);
    });
  });
}
