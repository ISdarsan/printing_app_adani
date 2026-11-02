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
