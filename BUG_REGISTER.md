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
| B-07 | P1 | Data model | Two sources of truth: dashboards sum from `bills`; cashier/reconciliation use `dailyStats` aggregates. `dailyStats.totalCash/Upi` also include credit repayments, bill-derived "cash" does not. The two screens can show different numbers for the same day. | INVESTIGATED - see FINANCIAL_DATA_AUDIT.md. Semantics are consistent (dailyStats sales fields = sales only; totalCash/Upi = sales + repayments); no code change made; decisions Q1-Q4 pending |
| B-08 | P2 | Analytics | `admin_analytics_page` streams whole `bills`, `dailyStats`, `expenses` collections (3 nested StreamBuilders, no date window). `admin_master_credit_ledger_page` streams all Credit bills. | OPEN |
| B-09 | P2 | Export | `_exportExcelReport` downloads full bills/expenses/repayments/reconciliations collections in one go. | OPEN |
| B-10 | P3 | Startup | Role splash always waits a fixed 3 s timer before navigating. | OPEN |
| B-11 | P3 | Repayment | `_processRepayment` runs a non-transactional bills query inside the transaction; docs are re-read with `tx.get` so values are safe, but a bill created mid-flight is missed. Money is `double` (rounding drift possible). | OPEN (low risk) |
| B-12 | P2 | Offline | No sync-state UI (pending / failed / retry). `runTransaction` fails when offline, so nothing is falsely shown as saved, but the cashier gets a raw exception string. | OPEN |

| B-14 | P1 | Cashier reads | Cashier screens query bills/expenses by timestamp with no canteenId filter; denied by firestore.rules (emulator-proved). Likely cause of reported sync problem. | NEEDS-DECISION (Q1: composite index deploy) |
| B-15 | P1 | Excel export | Net Position = Sales + Repayments - Expenses double counts repaid credit | NEEDS-DECISION (Q3) |
| B-16 | P2 | Excel export | 'Cash/UPI Collected' excludes repayments, disagrees with dailyStats | NEEDS-DECISION (Q4) |
| B-17 | P3 | Funds | monthlyFunds is global; expenses are per branch | NEEDS-DECISION |
| B-18 | P3 | Date windows | Day range ends 23:59:59 and uses device clock | OPEN |

## Verified correct (no change needed)
- Bill + dailyStats + credit customer + counter are written in one Firestore transaction.
- Repayment + bill pending amounts + customer total + dailyStats are one transaction; cash reconciliation uses a transaction.
- Rules: branch isolation, active-staff check, counter increment-by-one, non-decreasing dailyStats for non-admins.

## Not done in this session
- Full redesign of the 23 screens, design-system extraction, emulator-based sync tests, widget/overflow tests on small devices, device printing test. None of these were run or verified; do not treat them as complete.
- OpenClaw was not installed (it is an assistant gateway app, not a Flutter/dev skill).
