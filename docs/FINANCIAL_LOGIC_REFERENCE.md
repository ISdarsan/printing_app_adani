# Financial Logic Reference

Source files: `lib/money.dart`, `lib/business_time.dart`, and the services that write `bills`, `repayments`, `dailyStats`.

## Money
- All arithmetic is done in **whole paise** (integers): `toPaise`, `roundMoney`, `formatRupees`. No floating-point sums are stored or compared.
- Repayments are split with `planRepayment` so the parts add up to exactly the amount paid.
- A credit customer's pending can only decrease through repayments; "Paid" means 0 pending (also enforced by the candidate rules).

## Business day
- Fixed IST (UTC+05:30). A day is the half-open range `[start, nextStart)`: a bill at exactly midnight belongs to the new day, never to both.
- `date` strings are `yyyy-MM-dd` in IST; `dailyStats` ids are `<canteenId>_<date>`.

## Bill
- Document id = `clientRequestId`. A second create with the same id is rejected (create-once).
- Payment mode: `Cash`, `UPI` or `Credit`. Credit bills start `Pending` with `pending == total`.
- Timestamp is the server time.

## dailyStats fields
| Field | Meaning |
|---|---|
| `totalSales` | sales only (all modes) |
| `totalBills` | number of bills |
| `totalCredit` | credit **sales** only |
| `totalCash`, `totalUpi` | sales **plus repayments** received in that mode |
| `creditReceived` | repayments only |

## Derived numbers on screen
- **Accrual position** = sales − expenses.
- **Cash-basis movement** = cash + UPI sales + repayments − expenses.
- **Expected cash for closing** = `totalCash` (decision Q2).
- Reconciliation difference = actual cash − expected cash; both stored with the closing.

## Monthly funds
**Assigned per canteen** (owner decision, 2026-11-02; this replaces the earlier "one organisation-wide fund" decision).

- Document: `monthlyFunds/<canteenId>_<yyyy-MM>` with `canteenId`, `canteenName`, `monthYear`, `fundAmount`, `lastUpdated`, `updatedBy`, `monthLabel`. Code: `lib/fund_budget.dart`.
- A canteen's budget is compared only with **that canteen's** expenses. Remaining = budget - that canteen's spending, in whole paise.
- Alert when less than 15% of a canteen's budget is left, or when it is exceeded. A canteen with no budget set (or 0) has no alert.
- Cashier: sees only their own canteen's budget. Admin: Expense Report has a canteen selector; a budget is set for one chosen canteen. "All canteens" shows the total of the budgets set against everything spent and cannot be edited.
- The previous shared documents (id = month only) are **not** treated as any canteen's budget. They are left in the database untouched and ignored; the admin re-enters each canteen's budget.

## Bill numbers
Per-branch counter `billCounter_<canteenId>`; `lastNumber` is a positive integer written by cashiers of that branch only.

## Where it is tested
`flutter test` (money, business time, repayment plan, dailyStats, sync) and `security-tests/transactions.test.mjs` (26 integration tests of the same logic against the emulator). The emulator tests use a JavaScript port of the Dart logic, which is a stated limit.
