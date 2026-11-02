import 'package:canteen_adani/fund_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('monthlyFundDocId (one budget per canteen per month)', () {
    test('is canteen + month, so two canteens never share a document', () {
      expect(monthlyFundDocId('north', '2026-11'), 'north_2026-11');
      expect(monthlyFundDocId('south', '2026-11'), 'south_2026-11');
      expect(monthlyFundDocId('north', '2026-11'),
          isNot(monthlyFundDocId('north', '2026-12')));
    });
    test('an empty canteen id means main (same as every other id in the app)', () {
      expect(monthlyFundDocId('', '2026-11'), 'main_2026-11');
      expect(monthlyFundDocId('  ', '2026-11'), 'main_2026-11');
    });
    test('the old shared id (month only) is not a canteen budget id', () {
      expect(monthlyFundDocId('main', '2026-11'), isNot('2026-11'));
    });
  });

  group('CanteenBudget', () {
    test('available = allocated - spent, exact to the paisa', () {
      final b = CanteenBudget.of(canteenId: 'north', allocated: 10000, spent: 2500.55);
      expect(b.availablePaise, 749945);
      expect(b.available, 7499.45);
      expect(b.exceeded, isFalse);
    });

    test('no budget set: no alert, nothing to compare', () {
      final b = CanteenBudget.of(canteenId: 'north', allocated: 0, spent: 5000);
      expect(b.hasBudget, isFalse);
      expect(b.needsAlert, isFalse);
      expect(b.exceeded, isFalse);
      expect(b.percentUsed, 0);
    });

    test('alert only when LESS than 15% is left', () {
      bool alert(double spent) =>
          CanteenBudget.of(canteenId: 'c', allocated: 1000, spent: spent).needsAlert;
      expect(alert(0), isFalse);
      expect(alert(849), isFalse); // 15.1% left
      expect(alert(850), isFalse); // exactly 15% left is not "less than"
      expect(alert(851), isTrue); // 14.9% left
      expect(alert(1000), isTrue); // 0% left
    });

    test('exceeded is true only past the budget', () {
      expect(CanteenBudget.of(canteenId: 'c', allocated: 1000, spent: 1000).exceeded, isFalse);
      final over = CanteenBudget.of(canteenId: 'c', allocated: 1000, spent: 1000.01);
      expect(over.exceeded, isTrue);
      expect(over.available, -0.01);
    });

    test('percent used is a whole number and never negative', () {
      expect(CanteenBudget.of(canteenId: 'c', allocated: 1000, spent: 855).percentUsed, 86);
      expect(CanteenBudget.of(canteenId: 'c', allocated: 1000, spent: 1500).percentUsed, 150);
      expect(CanteenBudget.of(canteenId: 'c', allocated: 1000, spent: 0).percentUsed, 0);
    });

    test('floating-point sums do not create a false alert (0.1 + 0.2 style)', () {
      // 3 x 283.3 = 849.9 in doubles is 849.8999999999999; must count as 849.90
      final b = CanteenBudget.of(canteenId: 'c', allocated: 1000, spent: 283.3 * 3);
      expect(b.spentPaise, 84990);
      expect(b.needsAlert, isFalse);
    });
  });

  group('budgetsNeedingAlert (admin dashboard)', () {
    test('each canteen is judged against ITS OWN budget, not a pooled total', () {
      final alerts = budgetsNeedingAlert(
        allocatedByCanteen: {'north': 1000, 'south': 100000},
        spentByCanteen: {'north': 950, 'south': 950},
      );
      expect(alerts.map((a) => a.canteenId), ['north']);
    });

    test('spending in a canteen without a budget never alerts', () {
      final alerts = budgetsNeedingAlert(
        allocatedByCanteen: {'north': 1000},
        spentByCanteen: {'north': 100, 'south': 999999},
      );
      expect(alerts, isEmpty);
    });

    test('a canteen with a budget and no spending is fine', () {
      expect(
          budgetsNeedingAlert(
              allocatedByCanteen: {'north': 1000}, spentByCanteen: {}),
          isEmpty);
    });

    test('worst first', () {
      final alerts = budgetsNeedingAlert(
        allocatedByCanteen: {'a': 1000, 'b': 1000, 'c': 1000},
        spentByCanteen: {'a': 900, 'b': 1200, 'c': 990},
      );
      expect(alerts.map((a) => a.canteenId), ['b', 'c', 'a']);
    });

    test('a zero budget is ignored (not a division by zero)', () {
      expect(
          budgetsNeedingAlert(
              allocatedByCanteen: {'north': 0}, spentByCanteen: {'north': 50}),
          isEmpty);
    });
  });
}
