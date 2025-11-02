import 'package:flutter/material.dart';

class ExpensesPage extends StatelessWidget {
  const ExpensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Log Expense")),
      body: const Center(
        child: Text(
          "This is the Expenses Tracking Page",
          style: TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}