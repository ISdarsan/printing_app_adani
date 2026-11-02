/// Money helpers. Amounts are stored as Dart `double` rupees (unchanged, no
/// data migration); every decision that compares amounts goes through whole
/// paise so binary floating point noise (0.15 * 3 == 0.44999999999999996)
/// can never turn "exactly equal" into "not equal".
///
/// Rounding is half away from zero on the paise value, like `num.round()`.
library;

/// Whole paise of [rupees] (rounded). 12.10 -> 1210.
int toPaise(num rupees) => (rupees * 100).round();

double fromPaise(int paise) => paise / 100.0;

/// [rupees] rounded to 2 decimals (nearest paise).
double roundMoney(num rupees) => fromPaise(toPaise(rupees));

bool moneyEquals(num a, num b) => toPaise(a) == toPaise(b);
bool moneyLessOrEqual(num a, num b) => toPaise(a) <= toPaise(b);
bool moneyGreaterOrEqual(num a, num b) => toPaise(a) >= toPaise(b);
bool moneyGreater(num a, num b) => toPaise(a) > toPaise(b);

/// A price as the cashier should read it: whole rupees without decimals
/// (12 -> "12"), otherwise two decimals (12.5 -> "12.50"), so a ₹12.50 item is
/// never shown as ₹13. Summary cards keep their whole-rupee style.
String formatRupees(num v) =>
    toPaise(v) % 100 == 0 ? (toPaise(v) ~/ 100).toString() : v.toStringAsFixed(2);

/// One bill's share of a repayment.
class RepaymentAllocation {
  final int index; // position in the oldest-first input list
  final double newPending; // 0.0 when fully paid
  final bool paid;
  const RepaymentAllocation(this.index, this.newPending, this.paid);
}

class RepaymentPlan {
  final List<RepaymentAllocation> allocations;

  /// Part of the repayment that exceeds the sum of the pending bills.
  final double unallocated;
  const RepaymentPlan(this.allocations, this.unallocated);
}

/// Applies [amount] to bills (oldest first), in whole paise.
///
/// Same rule as before: a bill is cleared when the money left covers its whole
/// pending amount, otherwise it keeps (pending - money left) and the money is
/// used up. The only change is the arithmetic: paise integers instead of
/// doubles, so a last instalment equal to the remaining balance always clears
/// the bill instead of leaving 0.0000000000001 outstanding.
RepaymentPlan planRepayment(List<double> pendingOldestFirst, double amount) {
  var remaining = toPaise(amount);
  final out = <RepaymentAllocation>[];
  for (var i = 0; i < pendingOldestFirst.length; i++) {
    if (remaining <= 0) break;
    final pending = toPaise(pendingOldestFirst[i]);
    if (remaining >= pending) {
      remaining -= pending;
      out.add(RepaymentAllocation(i, 0.0, true));
    } else {
      out.add(RepaymentAllocation(i, fromPaise(pending - remaining), false));
      remaining = 0;
    }
  }
  return RepaymentPlan(out, fromPaise(remaining));
}
