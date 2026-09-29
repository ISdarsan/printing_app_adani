import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'theme.dart';

import 'splash_page.dart';
import 'login_page.dart';
import 'admin_dashboard_page.dart';
import 'billing_dashboard_page.dart';
import 'today_sales_page.dart';
import 'add_item_page.dart';
import 'expenses_page.dart';
import 'logout_splash_page.dart';
import 'print_bill_page.dart';
import 'role_splash_page.dart';
import 'menu_view_page.dart';
import 'funds_received_page.dart';
import 'notifications_page.dart';
import 'daily_sales_report_page.dart';
import 'all_bills_page.dart';
import 'admin_analytics_page.dart';
import 'admin_expense_report_page.dart';
import 'monthly_sales_breakdown_page.dart';
import 'send_notification_page.dart';
import 'credit_customers_page.dart';
import 'cash_reconciliation_page.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background notifications are handled by the app lifecycle; this is kept as a safe no-op.
  debugPrint(
      'Background FCM message received: ${message.messageId ?? 'unknown'}');
}

Future<void> _persistFcmToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    final messaging = FirebaseMessaging.instance;
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('canteenStaff')
        .doc(user.uid)
        .set({
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (e) {
    debugPrint('FCM token persistence error: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode for a consistent mobile experience
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Dark status bar icons to match our dark theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Firebase Cloud Messaging
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Retrieve token for debugging / console notification sends
    final token = await messaging.getToken();
    debugPrint("FCM Registration Token: $token");
    await _persistFcmToken();
  } catch (e) {
    debugPrint("FCM initialization error: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FoodPrint',
      theme: buildAppTheme(),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashPage(),
        '/login': (context) => LoginPage(),
        '/admin_dashboard': (context) => const AdminDashboardPage(),
        '/billing_dashboard': (context) => const BillingDashboardPage(),
        '/role_splash': (context) => RoleSplashPage(role: ''),
        '/logout_splash': (context) => LogoutSplashPage(),
        '/print_bill': (context) => const PrintBillPage(),
        '/add_item': (context) => const AddItemPage(),
        '/today_sales': (context) => const TodaySalesPage(),
        '/expenses': (context) => const ExpensesPage(),
        '/view_menu': (context) => const MenuViewPage(),
        '/funds_received': (context) => const FundsReceivedPage(isAdmin: false),
        '/funds_received_admin': (context) =>
            const FundsReceivedPage(isAdmin: true),
        '/notifications': (context) => const NotificationsPage(),
        '/daily_sales_report': (context) => const DailySalesReportPage(),
        '/all_bills_page': (context) => const AllBillsPage(),
        '/admin_analytics': (context) => const AdminAnalyticsPage(),
        '/monthly_sales_breakdown': (context) =>
            const MonthlySalesBreakdownPage(),
        '/send_notification': (context) => const SendNotificationPage(),
        '/admin_expense_report': (context) => const AdminExpenseReportPage(),
        '/credit_customers': (context) => const CreditCustomersPage(),
        '/cash_reconciliation_cashier': (context) =>
            const CashReconciliationPage(isAdmin: false),
        '/cash_reconciliation_admin': (context) =>
            const CashReconciliationPage(isAdmin: true),
      },
    );
  }
}
