import 'package:flutter/material.dart';
import 'splash_page.dart';
import 'login_page.dart'; // 👈 make sure this matches your file name!
import 'admin_dashboard_page.dart';
import 'billing_dashboard_page.dart';

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
        '/': (context) => const SplashPage(),
        '/login': (context) => LoginPage(), // 👈 no const
        '/adminDashboard': (context) => const AdminDashboardPage(),
        '/billingDashboard': (context) => const BillingDashboardPage(),
      },
    );
  }
}
