import 'package:canteen_adani/cash_closing_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('closingStatusFor (whole paise)', () {
    test('exactly balanced, shortage, surplus', () {
      expect(closingStatusFor(0), ClosingStatus.balanced);
      expect(closingStatusFor(-0.01), ClosingStatus.shortage);
      expect(closingStatusFor(0.01), ClosingStatus.surplus);
    });
    test('floating-point dust is balanced, not a shortage', () {
      expect(closingStatusFor(0.1 + 0.2 - 0.3), ClosingStatus.balanced); // 5.5e-17
      expect(closingStatusFor(-1e-13), ClosingStatus.balanced);
    });
  });

  group('closingChipText', () {
    test('shows exact amounts, not rounded to a rupee (a 40 paise shortage is not "₹0")', () {
      expect(closingChipText(-0.40), 'Shortage: ₹0.40');
      expect(closingChipText(0.5), 'Surplus: ₹0.50');
    });
    test('whole rupees stay short', () {
      expect(closingChipText(-120), 'Shortage: ₹120');
      expect(closingChipText(75), 'Surplus: ₹75');
      expect(closingChipText(0), 'Balanced');
    });
    test('shortage amount is positive text (the word carries the direction)', () {
      expect(closingChipText(-2500.5), 'Shortage: ₹2500.50');
    });
  });

  group('closingDay (older / odd records must not crash the admin list)', () {
    test('uses the date field', () {
      expect(closingDay('2026-11-02', 'north_2026-11-02'), DateTime(2026, 11, 2));
    });
    test('a record without a date field falls back to the document id suffix', () {
      expect(closingDay(null, 'north_2026-11-02'), DateTime(2026, 11, 2));
      expect(closingDay('', 'north_east_2026-11-02'), DateTime(2026, 11, 2)); // canteen id with underscores
    });
    test('the old failure: the whole document id used as a date', () {
      // DateFormat("yyyy-MM-dd").parse("north_2026-11-02") threw FormatException
      expect(() => closingDay(null, 'north_2026-11-02'), returnsNormally);
    });
    test('garbage gives null (screen shows the raw text) instead of throwing', () {
      expect(closingDay('not a date', 'whatever'), isNull);
      expect(closingDay(null, 'no-underscore-and-no-date'), isNull);
      expect(closingDay('2026-13-45', 'x_y'), isNull);
      expect(closingDay('2026-02-31', 'x_y'), isNull); // no 31st of February
      expect(closingDay('2024-02-29', 'x_y'), DateTime(2024, 2, 29)); // but a real leap day is fine
    });
  });

  group('closingDayChanged (IST midnight)', () {
    // IST midnight = 18:30 UTC
    test('same business day: unchanged', () {
      expect(closingDayChanged(openedDayKey: '2026-11-02', now: DateTime.utc(2026, 11, 2, 18, 29, 59)), isFalse);
    });
    test('one second after IST midnight: the closing screen is stale', () {
      expect(closingDayChanged(openedDayKey: '2026-11-02', now: DateTime.utc(2026, 11, 2, 18, 30, 0)), isTrue);
    });
    test('does not depend on the phone timezone, only on the instant', () {
      final ist = DateTime.utc(2026, 11, 2, 18, 31); // 00:01 IST on the 3rd
      expect(closingDayChanged(openedDayKey: '2026-11-02', now: ist), isTrue);
      expect(closingDayChanged(openedDayKey: '2026-11-03', now: ist), isFalse);
    });
  });
}
