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
Global (organisation-wide), by decision. Screens label them as such. Not split per branch.

## Bill numbers
Per-branch counter `billCounter_<canteenId>`; `lastNumber` is a positive integer written by cashiers of that branch only.

## Where it is tested
`flutter test` (money, business time, repayment plan, dailyStats, sync) and `security-tests/transactions.test.mjs` (26 integration tests of the same logic against the emulator). The emulator tests use a JavaScript port of the Dart logic, which is a stated limit.
