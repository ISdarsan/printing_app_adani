# UI / UX Audit

Branch `feature/ui-modernization-performance`. Date 2026-11-02.

## How this audit was done (read first)

- **Source inspection and automated scans of every screen file in `lib/`**, plus widget tests that render the shared and billing components at several screen sizes and text scales.
- **No screen was inspected visually.** The app was not run on a phone, emulator or desktop in this session, and **no screenshots exist**. Anything about "how it looks" below is inferred from the code and design tokens, not seen.
- Scans used: Firestore listener usage, builders without error handling, controller/timer disposal, raw error text shown to users, font sizes, hard-coded colours, tap-target sizes, `Semantics` use, adaptive-layout code, measured WCAG colour contrast.

## App-wide findings

| # | Finding | Evidence | Status |
|---|---|---|---|
| A1 | A design system already exists (`lib/theme.dart`): colour tokens, Inter font bundled, solid cards with hairline borders, gradient button, app bar, stat card, badge, input theme. | file inspected | kept, not rebuilt |
| A2 | No shared loading / empty / error views. Each screen improvised, or had none. | 8 screens had no error handling at all | **fixed**: `lib/state_views.dart` |
| A3 | Technical error text shown to staff (`Error: [cloud_firestore/permission-denied] …`). | 8 places | **fixed**: plain language + Retry; guarded by a test |
| A4 | `textHint` colour contrast 2.8:1 (WCAG AA needs 4.5:1). | computed | **fixed** (4.6:1), tested for every text token |
| A5 | About 25% of text uses are 11 px or smaller (104 of 412). | grep count | **not changed** (needs device QA; see limitations) |
| A6 | Only the login page and sync banner contain adaptive layout code. Orientation is locked to portrait (`main.dart`). Phones are the target; tablets will show a stretched phone layout. | grep + code | documented, not changed |
| A7 | No `Semantics` anywhere outside the billing screen before this work. | grep | partly fixed (billing, login); the rest remains |
| A8 | 13 files use hard-coded `Color(0x…)` instead of tokens (cash reconciliation 7). | grep | documented, not changed |
| A9 | Very large screen files: `admin_dashboard_page` 2606 lines, `print_bill_page` 2612. | wc | documented |
| A10 | No standalone Settings screen exists; actions live in the dashboard drawers. | file list | n/a |

## Screen by screen

| Screen (file) | Problems found | Done in this branch | Still open |
|---|---|---|---|
| **Login** (`login_page`) | No keyboard "go", no autofill hints, empty fields caused a server call then said "invalid password", password eye had no label, forgot-password showed the service's raw message. Already had spinner, double-tap guard, error box, scroll for small screens. | Keyboard next/done and Enter signs in, autofill hints, empty-field message, tooltip, plain-language reset errors. 9 widget tests, no overflow at 320×480, 200% text, landscape, tablet. **Sign-in logic unchanged.** | Visual QA |
| **Splash / role splash / logout splash** | Not changed. Role splash enforces deactivated/missing staff (covered by the existing auth-flow tests). | – | – |
| **Admin dashboard** (`admin_dashboard_page`) | 6 cards opened **new Firestore listeners on every rebuild**, including one on the whole month of bills. 17 small-font uses. Branch filter is client-side. | Listeners cached per card and branch/day. Calculations untouched. | Monthly sales still listens to all bills of the month (cost grows with volume); consider `dailyStats` (a business-definition decision, not made here). 2600-line file. |
| **Cashier dashboard** (`billing_dashboard_page`) | Already uses one small `dailyStats` document for today. Bell badge and notice banner re-opened listeners on rebuild. | Bell/banner cached. | – |
| **Billing / POS** (`print_bill_page`) | Cart rows overflowed with long item names (98 px at 320 wide). Full/Half chips were tappable only on a ~28 px pill. Remove button ~28 px. +/- unlabelled. | Names wrap (2 lines, ellipsis). Chip tap area is the full 46 px row, remove target 44×44, labels for screen readers. Widgets made public (no behaviour change) and covered by 17 widget tests incl. small phone and 200% text. Bill creation, create-once and printing code **untouched**. | Whole page rebuilds on each search keystroke (not measured, sub-widgets are small); item search speed on real menus; real printer. |
| **Printer sheet / status bar** | Not changed. | – | Needs a real device (Bluetooth). |
| **Menu management** (`add_item_page`, `menu_view_page`) | No error handling on the item list; raw error text in menu view. | Error view with Retry in both. Admin-only delete untouched (source test still passes). | – |
| **Customers and credit** (`credit_customers_page`, `admin_credit_customers_page`, `admin_master_credit_ledger_page`) | Search controllers never disposed; raw error text. | Disposed; friendly error + Retry. | Search is client-side over the loaded list. |
| **Credit detail and repayment** (`credit_detail_page`) | Raw error text in both tabs; repayment dialog controller is local and never disposed (no listeners, low severity); dialog not dismissible by tapping outside (intentional). | Friendly error + working Retry (streams re-opened). Repayment logic untouched. | Dialog controller dispose (risky to do without a device pass). |
| **Expenses** (`expenses_page`, `expense_detail_page`, `admin_expense_report_page`) | Report page: no error handling, two streams created in `build`. | Cached streams, error view with Retry. | – |
| **Funds** (`funds_received_page`, `admin_monthly_cashflow_page`) | No error handling: a failed load showed fund and spending as ₹0. Streams re-created on every access. Cashflow amount controller not disposed. | Error views (inline) with Retry, cached streams, controller disposed. Cashier labels "Organisation Fund" kept (existing wording test passes). | – |
| **Cash reconciliation** (`cash_reconciliation_page`) | **Financial-safety defect:** until the stats arrived, or if they failed, expected cash silently counted as ₹0, so a closing could be submitted against ₹0. No error handling. | The form now waits for the real figure and shows an error with Retry instead. Mutation-verified guard test. | – |
| **Analytics and reports** (`admin_analytics_page`, `analytics_page`, `daily_sales_report_page`, `monthly_sales_breakdown_page`, `today_sales_page`, `all_bills_page`) | Analytics already has loading, progress, retry and "refresh failed, showing earlier figures" (good). It printed the raw error. Daily/monthly/today pages re-created streams in `build`; monthly breakdown had no error handling; today's sales printed raw error. | Friendly errors, cached streams, error views. | 18 small-font uses in analytics. Charts not visually reviewed for misleading scales. |
| **Excel export** (in admin dashboard) | – | Not changed. Workbook still passes 56 checks with a real parser. | Share flow needs a device. |
| **Staff management** (admin dashboard) | Not changed (permissions and auth are out of scope). | – | – |
| **Notices** (`notifications_page`, `notification_detail_page`, `send_notification_page`) | Notices list had no error handling. | Error view with Retry (works on a stateless page via `RetryScope`). | – |
| **Sync strip** (`sync_banner`) | Already shows pending / offline / failed. Billing says a connection is required; offline billing is unsupported by decision. | – | – |

## Proposed next improvements (not done)

1. Device-test then raise 9–11 px text to at least 12 px, screen by screen.
2. Inject the Firestore instance into the dashboards so they can be widget-tested (admin/cashier dashboards, customer search, repayment dialog, closing page could not be widget-tested for this reason).
3. Split the two 2600-line files into widgets.
4. Replace hard-coded colours with tokens.
5. Add a tablet layout if tablets are actually used.
