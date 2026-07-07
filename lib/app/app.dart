import 'package:flutter/material.dart';

import 'startup_gate.dart';
import 'theme.dart';

/// Global navigator key used by notification tap handlers that need to push
/// screens without a BuildContext (e.g. day-close summary notification).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class CMBankApp extends StatelessWidget {
  const CMBankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'CM Bank',
      debugShowCheckedModeBanner: false,
      theme: CMBankTheme.light,
      home: const StartupGate(),
    );
  }
}
