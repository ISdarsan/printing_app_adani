# Financial Precision Audit (B-11)

Scope: how money is stored, calculated, compared, rounded and displayed. No data was migrated or rewritten.

## 1. How money is represented
| Layer | Representation |
|---|---|
| Firestore | JSON numbers: `totalAmount`, `price`, `subtotal`, `pendingAmount`, `totalPending`, repayment/expense `amount`, `dailyStats.*`, `systemCash`, `actualCash`, `discrepancy`, `fundAmount`. Written as Dart `double` rupees (for example `30.299999999999997`) |
| Dart | `double` rupees everywhere; no `Decimal`, no integer paise |
| Aggregates | `FieldValue.increment(double)` on `dailyStats` and `creditCustomers.totalPending` (the server adds doubles) |
| Tax / GST / discount / service charge | **None exist in the code** (searched). A bill is the sum of `price x quantity` |
| Excel | values rounded to 2 decimals when written (`_r2`), 2-decimal number format |

IEEE-754 doubles cannot hold most decimals exactly (`0.15 * 3 = 0.44999999999999996`). Prices that are whole rupees or multiples of 0.25 are exact in binary and never show the problem. Prices such as 12.10, 7.30, 15.05 are not.

## 2. Verified problems (reproduced with the old logic on synthetic prices)
The old comparisons used exact `double` operators. Reproduced in `test/money_precision_test.dart` (the old logic is re-implemented in the test next to the fix):

| # | Where | Old logic | Measured on synthetic data | Effect |
|---|---|---|---|---|
| 1 | Credit repayment validation, `credit_detail_page` | `amount > 0 && amount <= _totalPending` | **2,288 of 24,000** price x quantity bills (9.5%) reject a repayment equal to the exact balance; 16,940 of 151,360 three-bill balances (11%) | cashier gets "Invalid amount" when paying a customer's full balance |
| 2 | Cash closing, `cash_reconciliation_page` | `discrepancy == 0` | 1,502 of 2,000 simulated days (75%) fail to show "Balanced" although the count is exact | wrong "Shortage/Surplus" status; a stored discrepancy like `-1.4e-13` in the audit log |
| 3 | Repayment distribution | `remainingAmount >= billPending` | 3,253 of 15,920 two-instalment payoffs (20%) leave dust, so the bill stays `Pending` forever | credit lists show bills outstanding that were paid |
| 4 | Credit limit, `print_bill_page` | `currentPending + total > 2000` | 108,104 of 2,518,464 accumulated balances (4.3%) that land exactly on the limit are blocked | a bill that should be allowed is refused |
| 5 | Price display | `toStringAsFixed(0)` on item prices | any price with paise | picker shows 12.50 as "13" while billing 12.50 |

**Exposure depends on your menu prices.** If every price is a whole rupee or a multiple of 0.25, items 1-4 cannot occur from price arithmetic (they can still arise from accumulated server-side increments of non-exact values, which is rarer). I cannot see your menu data, so I report the problem as verified in the logic and unquantified in production.

## 3. Fixes applied (no data migration)
New `lib/money.dart`: `toPaise`, `roundMoney`, `moneyEquals`, `moneyLessOrEqual`, `moneyGreater`, `planRepayment`, `formatRupees`. All decisions compare whole paise.

| Fix | Change |
|---|---|
| Repayment validation | `toPaise(amount) > 0 && moneyLessOrEqual(amount, pending)` |
| Repayment distribution | `planRepayment` allocates oldest-first in integer paise; same rule as before (a zero-balance "Pending" bill is closed; over-payment is not allocated); the last instalment now always clears the bill. Money conservation is tested |
| Bill totals | `BillItem.subtotal` and the bill total are rounded to the paisa when built, so new bills store clean 2-decimal numbers |
| `dailyStats` increments | `dailyStatsDeltaForSale/Repayment` round to the paisa before `FieldValue.increment` |
| Cash closing | discrepancy, `systemCash`, `actualCash` rounded to the paisa before storing; "Balanced / Shortage / Surplus" use paise. Old records with dust (for example `1e-13`) are shown correctly at read time, **without rewriting them** |
| Credit limit | `moneyGreater(pending + total, limit)` |
| Unsafe casts | closing screens used `as double` on Firestore numbers (would throw if a value had been stored as an integer); now `asDouble` |
| Price display | `formatRupees` on the item picker and menu chips (whole rupees stay "12", paise show "12.50"). Summary cards keep their whole-rupee style by design |

Unchanged on purpose: stored historical values, field names and types, `dailyStats` semantics, the Excel formulas, rounding of summary cards to whole rupees, the receipt (already 2 decimals).

## 4. Remaining exposure (low, documented)
- **Server-side accumulation.** `dailyStats` / `totalPending` are sums of doubles; over thousands of increments they can carry noise around 1e-12. Every comparison that matters is now in paise, and every display rounds, so the noise is invisible. A report that prints a raw double with more than 2 decimals would show it; none does (all use `toStringAsFixed`).
- **Half-paise inputs.** A typed amount with 3 decimals (for example `10.005`) is rounded to the nearest paisa by the comparisons; the repayment itself still stores what was typed. The input fields do not currently restrict decimals.
- **Old stored totals** such as `30.299999999999997` remain as they are. They compare and display correctly, they sum correctly to the paisa, and the Excel export rounds them.
- **Analytics and charts** use doubles for averages and percentages; rounding there is cosmetic.

## 5. Migration proposal: not recommended
A verified precision problem exists, but it is fully addressed at the points of comparison and writing, without touching data. Converting every amount to integer paise would change the stored schema, every reader, the Excel export and the released app's expectations (older app versions would misread it), for no remaining benefit. **No migration is proposed.** If you later want integer paise for new fields only, the helpers in `money.dart` are the single place to introduce it.

Optional, read-only follow-up: scan stored `creditCustomers.totalPending` / `bills.pendingAmount` / `dailyStats` for values with more than 2 decimals (and for bills whose status is `Pending` with `pendingAmount < 0.01`) to see whether dust already exists in production. Not run (no production access).

## 6. Tests
`test/money_precision_test.dart` (17 tests): the five problems above reproduced with the old logic and shown fixed on the same brute-force inputs (24,000 / 151,360 / 2,000 / 15,920 / 2,518,464 cases), `planRepayment` semantics and conservation, rounding helpers, `BillItem` totals, `dailyStats` deltas, price formatting.
