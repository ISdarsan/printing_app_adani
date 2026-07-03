# Adani CSR Canteen Billing Application

A premium, feature-rich Flutter billing and management application developed for Adani CSR Canteen operations. Built with a modern, high-fidelity dark-themed glassmorphism interface, the application enables streamlined order placement, credit book tracking, daily cash reconciliation, real-time analytics, and automated reporting.

---

## 🌟 Key Features

### 1. POS Billing & Invoicing
- **Interactive Cart**: Quick search for food items with real-time total updates.
- **Multi-Mode Payments**: Options for **Cash**, **UPI**, and **Credit**.
- **Receipt Generation**: Formats and packages receipt details ready for printing or sharing.

### 2. Credit Ledger & Customer Management
- **Customer Directory**: Add, update, and track status of regular canteen credit customers.
- **Credit Tracking**: Logs individual unpaid orders under customer profiles.
- **Payment Logging**: Accept partial or complete settlements, logging payment methods dynamically.
- **Master Credit Ledger**: Admin-exclusive detailed transaction logs for auditing.

### 3. Daily Cash Reconciliation & Closing
- **Closing Register**: Cashiers count actual cash in the register at the end of their shift.
- **Discrepancy Calculation**: Automatically highlights shortages or surpluses compared to Firestore system sales.
- **Secure Submissions**: Logs the cashier identity, closing timestamp, and discrepancy notes. Once submitted, records are locked.
- **Audit Logs**: Admin dashboard allows historical log tracking to identify trends.

### 4. Expense & Cashflow Management
- **Expense Logger**: Cashiers can log local day-to-day purchases (e.g., vegetables, gas) directly from the register.
- **Fund Logs**: Track additional cash inflows, monthly budgets, and capital additions.
- **Daily Sales Reports**: Detailed breakdown of Cash vs. UPI vs. Credit splits for each day.

### 5. Admin Analytics & Reporting
- **Data Visualization**: Real-time sales trends, item performance, and payment mode splits powered by `fl_chart`.
- **Excel Exports**: Generates multi-sheet Excel reports (`excel` package) for Bills, Expenses, Repayments, and Cash Reconciliations.
- **Share & Print**: Share Excel worksheets instantly via system share options (`share_plus`).

### 6. Notifications & SMS Broadcasts
- **Push Notifications**: Broadcast urgent administrative announcements to all active terminals using Firebase Cloud Messaging.
- **SMS Specials**: Utility templates for broadcasting special menus or updates.

---

## 🛠️ Technology Stack

- **Framework**: [Flutter](https://flutter.dev/) (Targeting SDK `>=3.0.0 <4.0.0`)
- **Database & Backend**: Firebase Suite
  - **Firebase Auth**: Role-based access control (Admin vs. Cashier).
  - **Cloud Firestore**: Real-time document storage for sales, expenses, and ledgers.
  - **Firebase Messaging**: Cloud-to-device push notifications.
- **Libraries**:
  - `fl_chart`: For responsive visual data analytics.
  - `excel`: Programmatic worksheet creation.
  - `share_plus`: File sharing capability.
  - `google_fonts`: Premium typography (`Poppins` and others).
  - `lottie`: Vector animations for interactive elements.

---

## 📁 Directory Structure

```
lib/
├── main.dart                           # Application entry point & route registration
├── theme.dart                          # Application styling, dark theme definitions, and colors
├── sms_broadcast_helper.dart           # SMS utility and template generator
│
├── cash_reconciliation_page.dart       # Daily register closing, calculations, and admin log view
│
├── billing_dashboard_page.dart         # POS cashier main portal, navigation, and notices
├── print_bill_page.dart                # Cart, item select, payment selection, and bill checkout
│
├── credit_customers_page.dart          # Credit book directory for cashier
├── credit_detail_page.dart             # Individual credit tracking and repayment gateway
│
├── admin_dashboard_page.dart           # Admin portal, excel exporter, user management
├── admin_analytics_page.dart           # Visual reports, graphs, and category statistics
├── admin_master_credit_ledger_page.dart# Complete credit history auditing
├── admin_monthly_cashflow_page.dart    # Cashflow management, budgets, and investments
├── admin_expense_report_page.dart      # Audits and filters for daily expenses
│
├── expenses_page.dart                  # Log single or recurring canteen expenses
├── expense_detail_page.dart            # Detail view for an expense item
│
├── funds_received_page.dart            # Monthly reports, cash inflow ledger
├── today_sales_page.dart               # Summary of the current day's sales and payment methods
├── daily_sales_report_page.dart        # Day-by-day historical sales summaries
├── monthly_sales_breakdown_page.dart   # Monthly revenue overview
│
├── notifications_page.dart             # Received announcements and alerts
├── send_notification_page.dart         # Admin-only push notification broadcaster
│
├── login_page.dart                     # User sign-in interface
├── role_splash_page.dart               # Role verification and authorization gate
└── splash_page.dart                    # Application launch branding screen
```

---

## ⚙️ Getting Started

### Prerequisites
Make sure you have Flutter installed and configured on your machine.
```bash
flutter doctor
```

### 1. Clone & Fetch Dependencies
Clone the repository, navigate to the project directory, and pull all package dependencies:
```bash
git clone https://github.com/ISdarsan/printing_app_adani.git
cd printing_app_adani
flutter pub get
```

### 2. Configure Firebase
Ensure your Firebase Project is configured and the configuration files are added:
- **Android**: Place your `google-services.json` in `android/app/`.
- **iOS**: Place your `GoogleService-Info.plist` in `ios/Runner/`.
- **Web** (if building for web): Initialize Firebase Web configurations in `web/index.html`.

### 3. Run the App
To start the app on an emulator, simulator, or connected device:
```bash
flutter run
```

### 4. Build Release Version
To compile the release bundle:

**Android (APK):**
```bash
flutter build apk --release
```

**Windows:**
```bash
flutter build windows --release
```
