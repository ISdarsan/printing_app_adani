import 'package:flutter/material.dart';

class TodaySalesPage extends StatelessWidget {
  const TodaySalesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Sales")),
      body: const Center(
        child: Text(
          "This is the Today's Sales Page",
          style: TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}