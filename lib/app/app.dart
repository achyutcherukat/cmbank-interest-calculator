import 'package:flutter/material.dart';

import 'startup_gate.dart';
import 'theme.dart';

class CMBankApp extends StatelessWidget {
  const CMBankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CM Bank',
      debugShowCheckedModeBanner: false,
      theme: CMBankTheme.light,
      home: const StartupGate(),
    );
  }
}
