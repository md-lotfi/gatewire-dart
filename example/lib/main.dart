import 'package:flutter/material.dart';

import 'verification_demo_screen.dart';

void main() {
  runApp(const GateWireExampleApp());
}

class GateWireExampleApp extends StatelessWidget {
  const GateWireExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GateWire SDK Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: const VerificationDemoScreen(),
    );
  }
}
