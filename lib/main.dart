import 'package:flutter/material.dart';
import 'splash_page.dart';
import 'login_page.dart'; // 👈 make sure this matches your file name!
import 'admin_dashboard_page.dart';
import 'billing_dashboard_page.dart';
import 'today_sales_page.dart';
import 'add_item_page.dart';
import 'expenses_page.dart';
import 'logout_splash_page.dart';
import 'print_bill_page.dart';
import 'role_splash_page.dart';
// ADDED: Import for the new menu page
import 'menu_view_page.dart';

void main() {
  runApp(const MyApp());
}

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
        '/login': (context) => LoginPage(), // 👈 no const
        '/admin_dashboard': (context) => const AdminDashboardPage(), // Corrected name
        '/billing_dashboard': (context) => const BillingDashboardPage(), // Corrected name

        // ADDED: All your other pages
        '/role_splash': (context) =>
            RoleSplashPage(role: ''), // Base route, not used directly
        '/logout_splash': (context) => LogoutSplashPage(),
        '/print_bill': (context) => const PrintBillPage(),
        '/add_item': (context) => const AddItemPage(),
        '/today_sales': (context) => const TodaySalesPage(),
        '/expenses': (context) => const ExpensesPage(),
        '/view_menu': (context) => const MenuViewPage(), // The new menu page
      },
    );
  }
}

