# Financial Data Audit (B-07)

Scope: every place a money figure is written or read. All statements below were traced to code (file:line at commit `bbb41f7` + this pass), not inferred from field names.

## 1. Writers (who changes money fields)

| Event | File | Writes |
|---|---|---|
| New bill (one transaction) | `print_bill_page.dart` `_saveBill` | `bills/{id}` (totalAmount, paymentMode, pendingAmount/creditStatus for Credit); `dailyStats/{canteen}_{date}` merge-increment via `dailyStatsDeltaForSale`; `creditCustomers.totalPending += total` (Credit); `counters/billCounter_{canteen}` |
| Credit repayment (one transaction) | `credit_detail_page.dart` `_processRepayment` | oldest-first reduction of `bills.pendingAmount`/`creditStatus`; `creditCustomers.totalPending -= amount`; `repayments/{id}`; `dailyStats` via `dailyStatsDeltaForRepayment` |
| Cash closing | `cash_reconciliation_page.dart` | `cashReconciliations/{canteen}_{date}` with `systemCash = dailyStats.totalCash` at submit time |
| Expense | `expenses_page.dart` | `expenses/{id}` (amount, category, canteenId; **no payment mode**) |
| Monthly fund | `funds_received_page.dart`, `admin_monthly_cashflow_page.dart`, `admin_expense_report_page.dart` | `monthlyFunds/{yyyy-MM}.fundAmount` (global, not per canteen) |

## 2. What `dailyStats` actually contains

| Field | Meaning (from writers) |
|---|---|
| `totalSales` | Sales revenue (cash + UPI + credit). **Repayments never added.** |
| `totalBills` | Count of bills. |
| `totalCredit` | Credit sales issued that day. |
| `totalCash` | Cash sales **+ cash repayments** (physical cash that entered the till). |
| `totalUpi` | UPI sales **+ UPI repayments**. |
| `creditReceived` | Repayments of any mode. |

Answer to the audit question: `dailyStats` holds sales **and** repayments, split as above. Sales fields are sales-only; `totalCash`/`totalUpi` are collection fields.

## 3. Metric definitions and how each screen computes them today

| Metric | Definition | Source today |
|---|---|---|
| Sales revenue | All bills incl. credit | admin dashboard "today/month" and cashier dashboard: sum of `bills.totalAmount`; analytics/weekly chart: `dailyStats.totalSales` |
| Credit sales | Bills with paymentMode Credit | dashboard: bills; Today's Sales page: bills; dailyStats `totalCredit` |
| Cash sales | Bills paid Cash | dashboard / Today's Sales: bills (sales only) |
| UPI sales | Bills paid UPI | same |
| Cash repayments / UPI repayments | `repayments` by `paymentMode` | `repayments` docs; folded into `dailyStats.totalCash/Upi` |
| Total cash movement | cash sales + cash repayments | `dailyStats.totalCash` |
| Total UPI movement | UPI sales + UPI repayments | `dailyStats.totalUpi` |
| Expenses | sum `expenses.amount` | expenses collection (no mode) |
| Expected register cash | cash movement | cashier reconciliation reads `dailyStats.totalCash` (includes cash repayments, excludes expenses) |
| Daily / monthly revenue | sales revenue | bills (dashboards, daily report, monthly breakdown) or `dailyStats.totalSales` (analytics) |

Both sources agree for sales revenue as long as every bill is written together with its `dailyStats` increment. That holds today (single transaction). They differ **by definition** for cash/UPI because bill-derived cash is sales-only and `dailyStats` is sales + repayments.

## 4. Worked example (hypothetical day, same data as `test/financial_metrics_test.dart`)

Sales: Cash 500, Cash 300, UPI 400, Credit 200, Credit 300. Repayments: Cash 250, UPI 100. Expenses 200.

| Metric | Value |
|---|---|
| Sales revenue | 1700 |
| Credit sales | 500 |
| Cash sales / UPI sales | 800 / 400 |
| Cash repayments / UPI repayments | 250 / 100 |
| Total cash movement (= dailyStats.totalCash) | 1050 |
| Total UPI movement (= dailyStats.totalUpi) | 500 |
| Expected register cash | 1050 |
| Credit still owed | 500 - 350 = 150 |
| Cash-basis net (collections - expenses) | 1550 - 200 = 1350 |
| Accrual net (revenue - expenses) | 1700 - 200 = 1500 |
| Excel "Net Position (Sales + Repayments - Expenses)" | 1700 + 350 - 200 = **1850** |

The last row double counts: a credit sale is counted at sale time and again when repaid.

## 5. Findings

| ID | Sev | Finding |
|---|---|---|
| B-14 | **P1** | Cashier screens query `bills`/`expenses` by `timestamp` range with **no `canteenId` filter**: `billing_dashboard_page` (stats + expenses), `today_sales_page`, `daily_sales_report_page`, `all_bills_page`, `monthly_sales_breakdown_page`, `funds_received_page`. They then filter by branch on the device. Against `firestore.rules` these queries are denied for non-admins (proved in the emulator: `security-tests` test 2, plus the pre-existing unscoped-list test). If the deployed rules equal the repo rules, cashiers see errors/zeros on these screens. This is a likely cause of the reported "not synchronized" symptom. Not verifiable from here: whether production rules differ from the repo. |
| B-15 | P1 | Excel export "Net Position = Sales + Repayments - Expenses" double counts every repaid credit sale (example above: +350). |
| B-16 | P2 | Excel row "Cash Collected"/"UPI Collected" uses bill-derived cash/UPI sales, so it excludes repayments received; it disagrees with `dailyStats.totalCash/Upi` and with reconciliation. Label is misleading. |
| B-17 | P3 | `monthlyFunds` is one global document per month while expenses are per branch; the cashier fund/balance view sums expenses of the whole fund month. Needs confirmation that funds are intended to be global. |
| B-18 | P3 | Day windows end at 23:59:59 (not exclusive next-midnight), and the device clock defines "today"; a bill saved at 23:59:59.5 falls outside range-based screens but inside `dailyStats`. |

## 6. Business decisions (all answered; see section 9 onward for what was applied)

**Q1 - Cashier read path (B-14).** To make these queries legal they must add `canteenId == <branch>`. A `canteenId` equality plus a `timestamp` range needs a composite index on `bills` and `expenses` (`canteenId ASC, timestamp ASC/DESC`). Index creation is a production Firebase change. Options:
 (a) Add `firestore.indexes.json` to the repo and, with your approval, deploy it; then scope the six screens. *(recommended)*
 (b) No new index: cashier "today" cards read `dailyStats/{branch}_{today}` by document id (always allowed, no index), and bill lists query `canteenId ==` only and filter dates on the device (reads all branch bills; cost grows).
 Please also confirm whether the live rules match `firestore.rules` in this repo.

**Q2 - Are expenses paid out of the register cash?** Expenses have no payment mode and draw against the monthly CSR fund, so the code currently treats expected cash = cash sales + cash repayments (no expense deduction). If cashiers pay expenses from the till, expected cash must subtract them. Which is correct?

**Q3 - Net position in the Excel report (B-15).** Choose: cash basis (collections - expenses), accrual (sales - expenses), or keep as is. Recommendation: show both labelled rows and drop the double-counting formula.

**Q4 - Excel "Cash/UPI Collected" (B-16).** Should it include repayments (matches reconciliation) or stay sales-only with a relabel such as "Cash Sales"? Recommendation: add separate "Cash Repayments"/"UPI Repayments" rows and relabel the existing rows "Cash Sales"/"UPI Sales".

## 7. Safe reconciliation strategy for historical data (nothing executed)

1. Read-only: for each canteen and date, derive `FinancialSummary` from `bills` + `repayments` and compare to the stored doc with `dailyStatsDrift()` (in `lib/financial_metrics.dart`). Run against a Firestore export or the emulator, never write.
2. Produce a drift report (canteen, date, field, stored, derived). Review with you.
3. Only after approval, correct by writing an explicit adjustment record (new collection) or fix the specific docs in a one-off, backed-up admin script. No bulk overwrite.
4. Known benign drift source: bills created before `dailyStats` existed or repayments created before `creditReceived` existed.

## 8. Code changes in this pass (no behavior change)

- New `lib/financial_metrics.dart`: pure functions `dailyStatsDeltaForSale/Repayment`, `FinancialSummary`, `dailyStatsDrift`, and net-position helpers.
- `print_bill_page.dart` and `credit_detail_page.dart` now build their `dailyStats` increments from those helpers. Field names and values are identical to before.

---

# Phase 2: decisions applied (Q1-Q4, B-17, B-18)

## 9. What changed, calculation by calculation

| Area | Before | After |
|---|---|---|
| Excel "Net Position" | Sales + Repayments - Expenses (double counts repaid credit) | Two rows: **Accrual Operating Position** = Sales Revenue - Expenses; **Cash-Basis Movement** = Cash Sales + UPI Sales + Cash Repayments + UPI Repayments - Expenses |
| Excel "Cash/UPI Collected" | Cash/UPI **sales** under a "Collected" label | Renamed **Cash Sales / UPI Sales**; new Cash Repayments, UPI Repayments, **Total Cash Received**, **Total UPI Received** (= dailyStats totalCash/totalUpi) |
| Expected register cash | `dailyStats.totalCash` | **Unchanged** (Q2). Expenses are not deducted |
| Day/month query ranges | `>= 00:00:00` and `<= 23:59:59` on the device clock | `[start, nextStart)` in IST (`lib/business_time.dart`) |
| dailyStats / reconciliation doc id date | device-local date | IST business date (identical on IST phones) |
| Cashier bills/expenses queries | no `canteenId` filter (rejected by rules) | `canteenId ==` for cashiers; admin unscoped as before |

Not changed: how bills, repayments, dailyStats, customer balances and bill counters are written; Firestore rules; stored historical data.

## 10. Q2: expenses and register cash (documented, behavior preserved)
Evidence from the code about how expenses are really paid:
- Cashiers log expenses with a proof photo; categories are Vegetables, Gas, Groceries, Maintenance, Other. These are typical **petty-cash purchases**, so some may well be paid from the till.
- Nothing records the payment source (no `paymentMode`/`paidFrom` field), and `cashReconciliations` stores only `systemCash`, `actualCash`, `discrepancy`.
- Effect today: if a cashier pays a vegetable bill from the till and logs it, expected cash stays higher than the physical cash, producing a shortage of the same amount in the closing.
- Per your decision this is **not** changed. If you later want it handled, the smallest safe change is an optional "paid from register cash" flag on new expenses, subtracted only when set. That is a schema addition and needs your approval.

## 11. B-17: are monthly funds global or per canteen?
Facts:
- `monthlyFunds/{yyyy-MM}` has one `fundAmount` per month, no `canteenId`. Only admins can write it; any active staff can read it (rules).
- Admin dashboard banner and Expense Report compare the fund with **all branches' expenses** for the month: consistent with a global fund.
- The **cashier** banner (`billing_dashboard_page`, `_buildBudgetAlertBanner`) and Funds Received page compare the same global fund with **only that branch's expenses** (they filter with `matchesSelectedCanteen`).
- Result: a cashier sees a fund that is shared by all branches measured against their own spending only, so "balance remaining" and the used-percentage look healthier than the organisation-wide reality, and every branch sees the same full fund.
- Branch-level cashflow therefore has no allocated budget to compare to. A branch's true share cannot be computed from existing data.

Options for a decision (no change made): (1) keep it global and make the cashier screens show the organisation-wide spend against the fund (or label "your branch spend" separately); (2) allocate per canteen, using doc id `<canteenId>_<yyyy-MM>` and a `canteenId` field, with admin screens summing across branches. Option 2 needs a rules update and a data migration plan.

## 12. B-18: day boundaries (implemented)
- Business timezone: fixed IST, UTC+05:30, no DST (`BusinessTime`). Ranges are UTC instants, so results do not depend on the phone's timezone setting.
- Applied to: cashier dashboard, Today's Sales, Daily Sales Report, Bills History, Monthly Breakdown, Funds Received, budget banners (cashier and admin), admin dashboard day/month streams, weekly lookback, monthly cashflow, expense report month grouping, analytics (weekly start, expense month grouping, time-slot hour), Excel timestamps, dailyStats/reconciliation ids, bill and repayment `dailyStats` date.
- Intentionally unchanged: analytics rolling windows ("last 7/14/30 days" are elapsed-time windows, not calendar days), display of individual bill times on screen (device clock; identical on IST phones), `expenses_page` date picker (writes the picked instant).
- Known limit: an expense whose timestamp was set by the picker at local midnight on a non-IST phone could fall on the previous IST day. All users are in India today.
