import 'package:canteen_adani/financial_metrics.dart';
import 'package:canteen_adani/money.dart';
import 'package:canteen_adani/print_bill_page.dart' show BillItem;
import 'package:flutter_test/flutter_test.dart';

/// Synthetic prices only. "OLD" helpers reproduce the pre-fix code exactly so
/// the problem is demonstrated, then the fixed code is shown to have none.

// ---- OLD logic (before this phase) ------------------------------------------
bool oldRepaymentAccepted(double amount, double pending) =>
    amount > 0 && amount <= pending;

({List<double> newPending, List<bool> paid}) oldDistribute(
    List<double> pending, double amount) {
  var remaining = amount;
  final np = List<double>.from(pending);
  final paid = List<bool>.filled(pending.length, false);
  for (var i = 0; i < pending.length; i++) {
    if (remaining <= 0) break;
    if (remaining >= pending[i]) {
      remaining -= pending[i];
      np[i] = 0.0;
      paid[i] = true;
    } else {
      np[i] = pending[i] - remaining;
      remaining = 0;
    }
  }
  return (newPending: np, paid: paid);
}

void main() {
  group('the problem is real (old logic) and fixed (new logic)', () {
    test('full repayment of one bill: old rejects some exact amounts, new rejects none', () {
      var cases = 0, oldRejected = 0, newRejected = 0;
      for (var cents = 5; cents <= 20000; cents += 5) {
        final price = cents / 100.0;
        for (var q = 1; q <= 6; q++) {
          final pending = price * q; // old BillItem.subtotal
          final typed = double.parse(pending.toStringAsFixed(2));
          cases++;
          if (!oldRepaymentAccepted(typed, pending)) oldRejected++;
          // new: totals are rounded when the bill is built, validation is in paise
          final pendingNew = roundMoney(price * q);
          if (!(toPaise(typed) > 0 && moneyLessOrEqual(typed, pendingNew))) newRejected++;
          // and even against the legacy un-rounded stored value
          if (!(toPaise(typed) > 0 && moneyLessOrEqual(typed, pending))) newRejected++;
        }
      }
      // ignore: avoid_print
      print('PRECISION full-repayment: old rejected $oldRejected of $cases, new $newRejected');
      expect(cases, 24000);
      expect(oldRejected, greaterThan(2000), reason: 'old logic rejects ~9.5% of exact full repayments');
      expect(newRejected, 0);
    });

    test('customer with three credit bills pays the exact total', () {
      var oldRejected = 0, newRejected = 0, cases = 0;
      for (var a = 5; a <= 3000; a += 35) {
        for (var b = 5; b <= 3000; b += 55) {
          for (var c = 5; c <= 3000; c += 95) {
            final pending = (a / 100.0) + (b / 100.0) + (c / 100.0);
            final typed = double.parse(pending.toStringAsFixed(2));
            cases++;
            if (!oldRepaymentAccepted(typed, pending)) oldRejected++;
            if (!moneyLessOrEqual(typed, pending)) newRejected++;
          }
        }
      }
      // ignore: avoid_print
      print('PRECISION 3-bill: old rejected $oldRejected of $cases, new $newRejected');
      expect(cases, 151360);
      expect(oldRejected, greaterThan(10000));
      expect(newRejected, 0);
    });

    test('cash closing: exact count shows "Balanced" (old: usually not)', () {
      var oldNotBalanced = 0, newNotBalanced = 0;
      for (var seed = 1; seed <= 2000; seed++) {
        var sum = 0.0; // what repeated increments produce
        var paise = 0;
        for (var i = 0; i < 40; i++) {
          final v = ((seed * 7919 + i * 104729) % 9000) + 5;
          sum += (v / 100.0) * (1 + (i % 3));
          paise += v * (1 + (i % 3));
        }
        final actual = double.parse((paise / 100.0).toStringAsFixed(2));
        if (actual - sum != 0) oldNotBalanced++;
        if (!moneyEquals(actual, sum)) newNotBalanced++;
        // stored discrepancy is exactly zero after rounding
        expect(roundMoney(actual - sum), 0.0);
      }
      // ignore: avoid_print
      print('PRECISION closing: old not-balanced $oldNotBalanced of 2000, new $newNotBalanced');
      expect(oldNotBalanced, greaterThan(1000));
      expect(newNotBalanced, 0);
    });

    test('last instalment clears the bill (old: leaves dust and stays Pending)', () {
      var oldDust = 0, newDust = 0, cases = 0;
      for (var cents = 105; cents <= 20000; cents += 5) {
        final bill = cents / 100.0;
        for (final part in [0.1, 0.2, 0.3, 0.7]) {
          final first = double.parse((bill * part).toStringAsFixed(2));
          final second = double.parse((bill - first).toStringAsFixed(2));
          cases++;
          // after the first instalment the bill holds `bill - first`
          final afterFirstOld = oldDistribute([bill], first).newPending[0];
          if (!oldDistribute([afterFirstOld], second).paid[0]) oldDust++;
          final afterFirstNew = planRepayment([bill], first).allocations.single.newPending;
          if (!planRepayment([afterFirstNew], second).allocations.single.paid) newDust++;
        }
      }
      // ignore: avoid_print
      print('PRECISION dust: old $oldDust of $cases, new $newDust');
      expect(cases, 15920);
      expect(oldDust, greaterThan(1000));
      expect(newDust, 0);
    });

    test('credit limit: a bill landing exactly on the limit is allowed', () {
      // Pending is a sum of several earlier bills (as in production); the new
      // bill brings the total to exactly 2000.00.
      var oldBlocked = 0, newBlocked = 0, cases = 0;
      for (var a = 5; a < 150000; a += 7) {
        for (var b = 5; b < 150000; b += 997) {
          final rest = 200000 - a - b;
          if (rest <= 0) continue;
          final pending = (a / 100.0) + (b / 100.0); // accumulated balance
          final bill = rest / 100.0;
          cases++;
          if (pending + bill > 2000.0) oldBlocked++;
          if (moneyGreater(pending + bill, 2000.0)) newBlocked++;
        }
      }
      expect(cases, greaterThan(100000));
      expect(newBlocked, 0, reason: 'new logic never blocks an exact-limit bill');
      // Informational: how often the OLD comparison misfired on this data.
      // ignore: avoid_print
      print('credit-limit old misfires: $oldBlocked of $cases');
      expect(moneyGreater(1999.99 + 0.02, 2000.0), isTrue, reason: 'still blocks real overruns');
      expect(moneyGreater(2000.0, 2000.0), isFalse);
    });
  });

  group('helpers', () {
    test('price display never hides paise (12.50 is not shown as 13)', () {
      expect(formatRupees(12), '12');
      expect(formatRupees(12.0), '12');
      expect(formatRupees(12.5), '12.50');
      expect(formatRupees(7.05), '7.05');
      expect(formatRupees(0.15 * 3), '0.45');
      expect(formatRupees(10.1 * 3), '30.30');
      expect(formatRupees(0), '0');
    });

    test('rounding and conversion', () {
      expect(roundMoney(0.15 * 3), 0.45);
      expect(roundMoney(0.1 + 0.2), 0.3);
      expect(toPaise(12.10), 1210);
      expect(toPaise(-12.10), -1210);
      expect(fromPaise(1210), 12.10);
      expect(roundMoney(0), 0.0);
      expect(moneyEquals(0.1 + 0.2, 0.3), isTrue);
      expect(moneyEquals(10.00, 10.01), isFalse);
      expect(moneyLessOrEqual(10.00, 10.00), isTrue);
      expect(moneyGreaterOrEqual(10.00, 10.01), isFalse);
    });
  });

  group('planRepayment keeps the existing oldest-first rule', () {
    test('clears oldest bills first, partially pays the next, leaves the rest', () {
      final plan = planRepayment([100.0, 50.5, 20.0], 130.25);
      expect(plan.allocations.length, 2);
      expect(plan.allocations[0].paid, isTrue);
      expect(plan.allocations[0].newPending, 0.0);
      expect(plan.allocations[1].paid, isFalse);
      expect(plan.allocations[1].newPending, 20.25); // 50.50 - 30.25
      expect(plan.unallocated, 0.0);
    });
    test('exact total clears every bill', () {
      final plan = planRepayment([100.0, 50.5, 20.0], 170.5);
      expect(plan.allocations.every((a) => a.paid), isTrue);
      expect(plan.allocations.length, 3);
      expect(plan.unallocated, 0.0);
    });
    test('over-payment is reported as unallocated (as before it was ignored)', () {
      final plan = planRepayment([10.0], 25.0);
      expect(plan.allocations.single.paid, isTrue);
      expect(plan.unallocated, 15.0);
    });
    test('a zero-balance bill still marked Pending is closed, as in the original code', () {
      final plan = planRepayment([0.0, 40.0], 10.0);
      expect(plan.allocations[0].paid, isTrue);
      expect(plan.allocations[1].newPending, 30.0);
    });
    test('money is conserved: pending before - pending after == amount', () {
      final before = [33.33, 12.1, 0.15 * 3, 99.99, 5.05];
      for (final amount in [0.01, 12.1, 45.88, 100.0, 150.62]) {
        final plan = planRepayment(before, amount);
        var after = before.map(toPaise).toList();
        for (final a in plan.allocations) {
          after[a.index] = toPaise(a.newPending);
        }
        final paidPaise = before.map(toPaise).reduce((x, y) => x + y) -
            after.reduce((x, y) => x + y);
        expect(paidPaise + toPaise(plan.unallocated), toPaise(amount), reason: '$amount');
      }
    });
    test('matches the old algorithm wherever the old one had no floating point noise', () {
      for (final pend in [
        [100.0, 50.0, 25.0],
        [10.5, 20.25, 30.75],
      ]) {
        for (final amt in [5.0, 10.5, 30.75, 60.25, 61.5]) {
          final o = oldDistribute(pend, amt);
          final n = planRepayment(pend, amt);
          for (final a in n.allocations) {
            expect(o.paid[a.index], a.paid, reason: '$pend $amt');
            expect(o.newPending[a.index], a.newPending, reason: '$pend $amt');
          }
        }
      }
    });
  });

  group('bills and daily stats', () {
    test('BillItem subtotal is rounded to the paisa', () {
      final item = BillItem(code: 'x', name: 'Tea', type: 'Full', quantity: 3, price: 0.15);
      expect(item.subtotal, 0.45);
      expect(item.subtotal == 0.45, isTrue);
    });
    test('item totals add to an exact 2-decimal bill total', () {
      final items = [
        BillItem(code: 'a', name: 'A', type: 'Full', quantity: 3, price: 10.1),
        BillItem(code: 'b', name: 'B', type: 'Full', quantity: 2, price: 7.3),
        BillItem(code: 'c', name: 'C', type: 'Full', quantity: 1, price: 0.05),
      ];
      final total = roundMoney(items.fold(0.0, (s, i) => s + i.subtotal));
      expect(total, 44.95); // 30.30 + 14.60 + 0.05
    });
    test('dailyStats deltas carry exact paise, even from noisy inputs', () {
      expect(dailyStatsDeltaForSale(0.1 + 0.2, 'Cash')['totalSales'], 0.3);
      expect(dailyStatsDeltaForSale(0.1 + 0.2, 'Cash')['totalCash'], 0.3);
      expect(dailyStatsDeltaForRepayment(10.1 * 3, 'UPI')['totalUpi'], 30.3);
      expect(dailyStatsDeltaForRepayment(10.1 * 3, 'UPI')['creditReceived'], 30.3);
    });
    test('FinancialSummary comparisons survive accumulated noise', () {
      final sales = [for (var i = 0; i < 1000; i++) SaleRecord(0.1, 'Cash')];
      final s = FinancialSummary.fromRecords(sales, const []);
      expect(s.cashSales == 100.0, isFalse, reason: 'raw double sum is noisy');
      expect(roundMoney(s.cashSales), 100.0);
      expect(moneyEquals(s.expectedRegisterCash, 100.0), isTrue);
    });
  });
}
