# Adani CSR Canteen Billing Application

A premium, feature-rich Flutter billing and management application developed for **Adani CSR Canteen** operations. Built with a modern dark-themed glassmorphism interface, the app enables streamlined order placement, credit book tracking, daily cash reconciliation, real-time analytics, multi-canteen management, and automated reporting — all backed by Firebase.

> **Version:** `1.0.5+6` &nbsp;|&nbsp; **Flutter SDK:** `>=3.0.0 <4.0.0` &nbsp;|&nbsp; **Platform:** Android (primary), Windows

---

## ✨ Key Features

### 1. POS Billing & Invoicing
- **Interactive Cart** — Quick food-item search with real-time total updates.
- **Multi-Mode Payments** — Cash, UPI, and Credit.
- **Receipt Generation** — Formats bill details ready for Bluetooth thermal printing or sharing.
- **Bluetooth Thermal Printing** — Connects to ESC/POS printers; runtime `BLUETOOTH_SCAN` permission handling for Android 12+.

### 2. Credit Ledger & Customer Management
- **Customer Directory** — Add, update, and track regular credit customers.
- **Credit Tracking** — Logs unpaid orders under individual customer profiles.
- **Payment Logging** — Accept partial or full settlements with dynamic payment-method logging.
- **Master Credit Ledger** — Admin-exclusive audit trail for all credit transactions (per-canteen).

### 3. Daily Cash Reconciliation & Closing
- **Closing Register** — Cashiers count actual cash at shift end.
- **Discrepancy Calculation** — Automatically highlights shortages or surpluses vs. Firestore system totals.
- **Secure Submissions** — Locks records with cashier identity and timestamp after submission.
- **Audit Logs** — Admin dashboard shows historical trends across closing sessions.

### 4. Expense & Cashflow Management
- **Expense Logger** — Log day-to-day canteen purchases (vegetables, gas, etc.).
- **Fund Logs** — Track cash inflows and monthly budget top-ups.
- **Per-Canteen Budgets** — Monthly budgets are assigned individually per canteen (replacing the old shared org-wide fund).
- **Daily Sales Reports** — Cash vs. UPI vs. Credit breakdown per day.

### 5. Multi-Canteen Admin Controls
- **Canteen Chooser** — Admins can switch canteen scope across Manage Menu, Master Ledger, Closing Logs, and Analytics.
- **Main Canteen** — Designated main canteen is protected from accidental deletion; other canteens can be safely removed.
- **Auto Admin Assignment** — Admins are automatically assigned to every canteen on creation.
- **Safe Canteen Deletion** — Cascades cleanup without orphaning any data.

### 6. Admin Analytics & Reporting
- **Data Visualization** — Real-time sales trends, item performance, and payment-mode splits via `fl_chart`.
- **Excel Exports** — Multi-sheet reports (Bills, Expenses, Repayments, Cash Reconciliations) via `excel` package.
- **Share & Print** — Instantly share Excel worksheets via system share options (`share_plus`).

### 7. Notifications & SMS Broadcasts
- **In-App Notices** — Canteen-scoped admin notices stored in Firestore and shown during active sessions.
- **SMS Specials** — Broadcast templates for special menus/updates *(Coming soon)*.

---

## 🛠 Technology Stack

| Layer | Technology |
|---|---|
| **Framework** | [Flutter](https://flutter.dev/) `>=3.0.0 <4.0.0` |
| **Auth** | Firebase Auth — role-based (Admin / Cashier) |
| **Database** | Cloud Firestore — real-time document storage |
| **Printing** | `blue_thermal_printer` + `esc_pos_utils_plus` |
| **Charts** | `fl_chart` |
| **Exports** | `excel`, `share_plus`, `path_provider` |
| **UI** | `lottie`, `animated_text_kit`, Inter font family |
| **Preferences** | `shared_preferences` |

---

## 📁 Directory Structure

```
lib/
├── main.dart                             # App entry point & route registration
├── theme.dart                            # Dark theme, glassmorphism styles, and colors
├── sms_broadcast_helper.dart             # SMS utility and template generator
│
├── billing_dashboard_page.dart           # Cashier main portal, navigation, and notices
├── print_bill_page.dart                  # Cart, item select, payment selection, bill checkout
├── all_bills_page.dart                   # Historical bill log viewer
│
├── credit_customers_page.dart            # Credit book directory (cashier)
├── credit_detail_page.dart              # Individual credit tracking and repayment
│
├── cash_reconciliation_page.dart         # Daily register closing & discrepancy view
│
├── admin_dashboard_page.dart             # Admin portal, Excel exporter, user management
├── admin_analytics_page.dart             # Visual reports, graphs, and category stats
├── admin_master_credit_ledger_page.dart  # Full credit history audit (per-canteen)
├── admin_monthly_cashflow_page.dart      # Cashflow, per-canteen budgets & investments
├── admin_expense_report_page.dart        # Expense audit and filtering
│
├── expenses_page.dart                    # Log single/recurring canteen expenses
├── expense_detail_page.dart             # Expense item detail view
│
├── funds_received_page.dart              # Monthly reports and cash inflow ledger
├── today_sales_page.dart                 # Current day's sales summary
├── daily_sales_report_page.dart          # Day-by-day historical sales
├── monthly_sales_breakdown_page.dart     # Monthly revenue overview
│
├── notification_detail_page.dart         # Notification detail view
├── notifications_page.dart              # Received announcements and alerts
├── send_notification_page.dart          # Admin-only in-app notice broadcaster
│
├── login_page.dart                       # User sign-in interface
├── role_splash_page.dart                 # Role verification & authorization gate
└── splash_page.dart                      # App launch branding screen
```

---

## 🚀 Getting Started

### Prerequisites
```bash
flutter doctor
```

### 1. Clone & Fetch Dependencies
```bash
git clone https://github.com/ISdarsan/printing_app_adani.git
cd printing_app_adani
flutter pub get
```

### 2. Configure Firebase
- **Android**: Place `google-services.json` in `android/app/`
- **iOS**: Place `GoogleService-Info.plist` in `ios/Runner/`
- **Web** *(optional)*: Add Firebase Web config in `web/index.html`

### 3. Run the App
```bash
flutter run
```

### 4. Build Release

**Android APK:**
```bash
flutter build apk --release
```

**Windows:**
```bash
flutter build windows --release
```

---

## 📋 Recent Changelog

| Version | Highlights |
|---|---|
| `1.0.5+6` | Android 12+ Bluetooth runtime permission (`BLUETOOTH_SCAN`); multi-canteen admin choosers; per-canteen budgets; safe main-canteen deletion guard; crash hardening & back-button bill protection |
| `1.0.4` | Full analysis sweep — wrong-phone-date guard, budget usage bar, UI modernization |
| `1.0.3` | Monthly budgets per canteen (replaces shared org-wide fund) |

---

*Built with ❤️ for Adani CSR Canteen operations.*
