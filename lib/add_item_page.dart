import 'package:flutter/material.dart';

class AddItemPage extends StatelessWidget {
  const AddItemPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Item')),
      body: const Center(
        child: Text(
          'This is the Add Item Page',
          style: TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}
