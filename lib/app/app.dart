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
      // The UI is designed elderly-friendly (min 18sp text, 58px targets)
      // already — ignore the OS font-size setting so OEM defaults (e.g.
      // Xiaomi/Poco ship with enlarged text) don't compound on top of it.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.0)),
        child: child!,
      ),
      home: const StartupGate(),
    );
  }
}
