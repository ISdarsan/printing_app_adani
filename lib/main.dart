import 'package:flutter/material.dart';

// --- ADDED ---
import 'package:firebase_core/firebase_core.dart'; // Import Firebase
import 'firebase_options.dart'; // This file was created by the tool
// -------------

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
import 'notifications_page.dart'; // <-- 1. IMPORT ADDED

// --- MODIFIED ---
void main() async { // Make this 'async'
  // Make sure Flutter is ready
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Run the app
  runApp(const MyApp());
}
// ----------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FoodPrint',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/',
      routes: {
        // Core routes
        '/': (context) => const SplashPage(),
        '/login': (context) => LoginPage(),
        '/admin_dashboard': (context) => const AdminDashboardPage(),
        '/billing_dashboard': (context) => const BillingDashboardPage(),

        // All your other pages
        '/role_splash': (context) =>
            RoleSplashPage(role: ''),
        '/logout_splash': (context) => LogoutSplashPage(),
        '/print_bill': (context) => const PrintBillPage(),
        '/add_item': (context) => const AddItemPage(),
        '/today_sales': (context) => const TodaySalesPage(),
        '/expenses': (context) => const ExpensesPage(),
        '/view_menu': (context) => const MenuViewPage(),
        '/funds_received': (context) => const FundsReceivedPage(),
        '/notifications': (context) => const NotificationsPage(), // <-- 2. ROUTE ADDED
      },
    );
  }
}