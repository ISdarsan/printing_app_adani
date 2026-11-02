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

## Phase 3 additions (Excel validation, B-08, B-09, index/rules review)
- New pure modules: `report_records.dart` (small records), `excel_report_builder.dart` (workbook), `paged_fetch.dart` (paging engine), `export_range.dart`, `analytics_calc.dart` (moved analytics maths + periods). Firestore adapters: `report_data_loader.dart`, `analytics_loader.dart`.
- `admin_dashboard_page.dart` export is now: choose period -> paged read with progress/cancel -> build -> share, with Retry on failure and no partial file. `admin_analytics_page.dart` shrank 1,134 -> 922 lines and no longer holds live listeners on whole collections.
- Tools: `tool/validate_workbook.py` (independent XLSX check), `tool/compare_rules.mjs` (read-only rules diff).
- Tests: 145 Dart + 25 emulator + 56 workbook checks; see TEST_RESULTS.md for what is not covered (no device, no Dart-to-emulator integration, indexes unverifiable offline).
- New findings: B-19 (production has no composite indexes; three existing cashier queries need them), B-20 (menu delete allowed for cashiers), B-21/B-22 (legacy documents without `canteenId` / `date`).
- Architecture note: report logic is now separated from UI and Firestore (records -> pure builders -> thin adapters), which is what made the independent validation possible.
- Still not audited line by line: expenses entry, notifications, menu/add item, printing, theme.

## Phase 4 additions (release preparation, cashier reliability, sync)
- New modules: `money.dart` (paise logic), `today_summary.dart` (dashboard card from `dailyStats`), `role_routing.dart` (authorization decision), `sync_status.dart` / `sync_banner.dart` / `connection_probe.dart` / `tracked_write.dart` (status strip, create-once, idempotent writes).
- Behavioural changes: login has no fixed wait; staff lookup reads the server; bills and repayments carry `clientRequestId` and are checked against the server before any repeat; expenses and notices are written with `set` on a pre-chosen id; money comparisons are in whole paise; the cashier dashboard card reads one `dailyStats` document; every bills query is descending (index count 6 -> 5).
- Tools: `tool/check_indexes.mjs` (index registry vs source vs file), `tool/rules_diff.mjs` + `tool/compare_rules.mjs` (rule-by-rule diff, 7 tests).
- Tests: 232 Dart + 27 emulator + 7 rules-diff + 56 workbook checks (TEST_RESULTS.md).
- Still unverified: production rules vs repository (PRODUCTION_RULES_COMPARISON.md), anything on a physical device (CASHIER_DEVICE_TEST_PLAN.md), deployed index state.
- Architecture note: decisions that must be right (authorization, money comparison, create-once, sync state) now live in small pure functions with direct tests; screens only call them.
