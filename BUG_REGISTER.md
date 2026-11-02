# Bug Register

Branch: `stabilize/audit-and-modernize`. Baseline: `flutter analyze` clean, 9/9 tests passing.
Status key: FIXED (code changed + analyze/tests green), OPEN (confirmed in source, not yet changed), NEEDS-DECISION (business rule question).

| ID | Sev | Area | Finding (confirmed in source) | Status |
|----|-----|------|-------------------------------|--------|
| B-01 | P1 | Branch isolation | `CanteenProvider.initializeForStaff` swallowed all errors and fell back to canteen `main`, non-admin. A branch cashier with a failed read would be treated as `main` staff. | FIXED - errors now propagate; role splash applies the already-fetched doc via `applyStaffData` |
| B-02 | P1 | Auth | Role splash never checked `active == false`; deactivated staff got a dashboard that then failed on every read (rules deny). | FIXED - clean "deactivated" denial, then sign-out |
| B-03 | P1 | Billing | `_processSaveBill` had no re-entry guard until the transaction started; double tap during the credit-customer dialog could save two bills. | FIXED - `_saveFlowActive` guard around dialog+save+print |
| B-04 | P2 | Billing | `setState`/snackbar after the transaction without `mounted` check. | FIXED |
| B-05 | P2 | Admin dashboard | Recent-bills stream read the entire `bills` collection to show 4 rows (cost grows forever). | FIXED - `limit(4)`; `limit(100)` when a branch filter is active (client-side filter, avoids new index) |
| B-06 | P2 | Admin dashboard | Weekly stats query used a `documentId >=` range on IDs shaped `<canteenId>_<date>`, so every historical `main_*` doc matched. | FIXED - filters on the `date` field |
| B-07 | P1 | Data model | Two sources of truth: dashboards sum from `bills`; cashier/reconciliation use `dailyStats` aggregates. `dailyStats.totalCash/Upi` also include credit repayments, bill-derived "cash" does not. The two screens can show different numbers for the same day. | RESOLVED by decisions Q2-Q4: semantics documented, reconciliation preserved, Excel now separates sales/repayments |
| B-08 | P2 | Analytics | `admin_analytics_page` streams whole `bills`, `dailyStats`, `expenses` collections (3 nested StreamBuilders, no date window). `admin_master_credit_ledger_page` streams all Credit bills. | FIXED in code - bounded paged reads, period selector (default 6 months), aggregates computed page by page; equivalent to the original on synthetic data (ANALYTICS_OPTIMIZATION_REPORT.md). Not run on a device |
| B-09 | P2 | Export | `_exportExcelReport` downloads full bills/expenses/repayments/reconciliations collections in one go. | FIXED in code - period picker, cursor paging, retry/cancel, no partial file; paging proven on emulator (EXPORT_OPTIMIZATION_REPORT.md). Workbook validated on synthetic data; in-app run pending |
| B-10 | P3 | Startup | Role splash always waits a fixed 3 s timer before navigating. | OPEN |
| B-11 | P3 | Repayment | `_processRepayment` runs a non-transactional bills query inside the transaction; docs are re-read with `tx.get` so values are safe, but a bill created mid-flight is missed. Money is `double` (rounding drift possible). | OPEN (low risk) |
| B-12 | P2 | Offline | No sync-state UI (pending / failed / retry). `runTransaction` fails when offline, so nothing is falsely shown as saved, but the cashier gets a raw exception string. | OPEN |
| B-14 | P1 | Cashier reads | Cashier screens query bills/expenses by timestamp with no canteenId filter; denied by firestore.rules (emulator-proved). Likely cause of reported sync problem. | FIXED in code (6 screens scoped + `firestore.indexes.json`); **NOT DEPLOYED**: indexes must be deployed before releasing the app (see FIRESTORE_INDEX_AUDIT.md) |
| B-15 | P1 | Excel export | Net Position = Sales + Repayments - Expenses double counts repaid credit | FIXED - Excel shows Accrual Operating Position and Cash-Basis Movement; double-counting formula removed (workbook generation itself untested) |
| B-16 | P2 | Excel export | 'Cash/UPI Collected' excludes repayments, disagrees with dailyStats | FIXED - Cash Sales / UPI Sales renamed; Cash/UPI Repayments and Total Cash/UPI Received added |
| B-17 | P3 | Funds | monthlyFunds is global; expenses are per branch | INVESTIGATED - global fund vs per-branch cashier view documented (FINANCIAL_DATA_AUDIT.md s.11); no model change; decision pending |
| B-18 | P3 | Date windows | Day range ends 23:59:59 and uses device clock | FIXED - half-open IST day/month ranges (see FINANCIAL_DATA_AUDIT.md s.12) |
| B-19 | P1 | Indexes | Production has **no composite indexes**, yet existing queries on `cashReconciliations`, `notifications` and `menuItems` use equality + orderBy and need them. Unknown whether those screens currently fail. | OPEN - query shapes and rules verified in the emulator; indexes in `firestore.indexes.json`, NOT deployed; real-device verification PENDING (FIRESTORE_RELEASE_CHECKLIST.md) |
| B-20 | P3 | Rules | `menuItems` delete is allowed for any staff who can read the branch (cashiers can delete their branch's menu items); every other collection is admin-only for delete. Possibly intentional. | NEEDS-DECISION (rules not changed) |
| B-21 | P3 | Analytics/legacy | Branch `main` analytics must read unscoped because legacy documents have no `canteenId`; other branches' documents are downloaded then discarded for that view. | OPEN (needs a legacy backfill migration to fix; requires approval) |
| B-22 | P3 | dailyStats legacy | Windowed analytics filters `dailyStats` on the `date` field; any legacy document without it appears only under 'All time'. | OPEN (documented, emulator-tested) |

## Verified correct (no change needed)
- Bill + dailyStats + credit customer + counter are written in one Firestore transaction.
- Repayment + bill pending amounts + customer total + dailyStats are one transaction; cash reconciliation uses a transaction.
- Rules: branch isolation, active-staff check, counter increment-by-one, non-decreasing dailyStats for non-admins.

## Not done in this session
- Full redesign of the 23 screens, design-system extraction, emulator-based sync tests, widget/overflow tests on small devices, device printing test. None of these were run or verified; do not treat them as complete.
- OpenClaw was not installed (it is an assistant gateway app, not a Flutter/dev skill).
