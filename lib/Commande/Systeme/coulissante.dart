import 'package:flutter/material.dart';

class SystemSlidinge extends StatefulWidget {
  const SystemSlidinge({super.key});

  @override
  State<SystemSlidinge> createState() => _SystemSlidingeState();
}

class _SystemSlidingeState extends State<SystemSlidinge> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text('System Slidinge'),
        centerTitle: true,
      ),
    );
  }
}
