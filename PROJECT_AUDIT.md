# Project Audit (running)

Stack: Flutter, Firebase Auth, Cloud Firestore, ~16k lines in `lib/` (largest: `admin_dashboard_page.dart` 2956, `print_bill_page.dart` 2469, `admin_analytics_page.dart` 1134). State is local `setState` + `StreamBuilder`; branch scope lives in static `CanteenProvider`.

## Data flow (verified)
- Writes: bill, repayment and cash closing are Firestore transactions. `dailyStats` is a maintained aggregate (sales fields + collection fields); see FINANCIAL_DATA_AUDIT.md.
- Reads: admin screens read whole collections (analytics, ledger, export); cashier screens use unscoped timestamp queries that the rules deny (B-14).
- Security: `firestore.rules` enforces active staff, branch isolation, counter +1, non-decreasing dailyStats for non-admins; emulator suite in `security-tests/` (9 tests passing).

## Status
- Pass 1 (bbb41f7): B-01..B-06 fixed.
- Pass 2: B-07 investigated; B-14..B-18 found; decisions Q1-Q4 pending. See BUG_REGISTER.md.
- Not yet audited line by line: expenses, funds, notifications, menu/add item, printing, export sheets, theme.

## Phase 2 additions
- New modules: `lib/business_time.dart` (IST day/month ranges and keys), `lib/financial_metrics.dart` (dailyStats deltas, summaries, Excel summary rows).
- Cashier read path now branch-scoped (B-14); needs the 6 indexes in `firestore.indexes.json` (production currently has none, see FIRESTORE_INDEX_AUDIT.md and B-19).
- Excel export restructured per decisions Q3/Q4 (EXCEL_REPORT_AUDIT.md).
- Decisions recorded: Q1 option A, Q2 keep expected cash = totalCash, Q3 show both positions, Q4 separate sales/repayments. B-17 (global funds) documented, not changed.
- Tests: 63 Dart + 10 emulator; see TEST_RESULTS.md for what is not covered.
- Still not audited line by line: expenses entry, funds screens beyond queries, notifications, menu/add item, printing, theme.
