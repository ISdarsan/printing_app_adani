import 'package:flutter/material.dart';

class PrintBillPage extends StatelessWidget {
  const PrintBillPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Print Bill')),
      body: const Center(
        child: Text(
          'This is the Print Bill Page',
          style: TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}
