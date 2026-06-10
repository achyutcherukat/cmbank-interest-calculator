import 'package:flutter/material.dart';

import '../core/settings/app_settings_repository.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/calculator/presentation/home_screen.dart';
import '../features/setup/presentation/first_launch_wizard.dart';
import 'theme.dart';

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> with WidgetsBindingObserver {
  final AppSettingsRepository _settingsRepository = AppSettingsRepository();
  late Future<bool> _isFirstLaunchComplete;
  bool _isAuthenticated = false;
  DateTime? _backgroundedAt;

  static const _lockTimeout = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isFirstLaunchComplete = _loadFirstLaunchState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _isAuthenticated) {
      final bg = _backgroundedAt;
      if (bg != null &&
          DateTime.now().difference(bg) >= _lockTimeout) {
        setState(() => _isAuthenticated = false);
      }
      _backgroundedAt = null;
    }
  }

  Future<bool> _loadFirstLaunchState() async {
    try {
      return _settingsRepository.getBool('first_launch_completed');
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'cm_bank_startup',
          context: ErrorDescription('while reading first launch settings'),
        ),
      );
      return true;
    }
  }

  void _handleSetupComplete() {
    setState(() {
      _isFirstLaunchComplete = Future.value(true);
      _isAuthenticated = true;
    });
  }

  void _handleAuthenticated() {
    setState(() => _isAuthenticated = true);
  }

  void _handleLock() {
    setState(() => _isAuthenticated = false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isFirstLaunchComplete,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _StartupLoadingScreen();
        }

        if (snapshot.data == true && _isAuthenticated) {
          return HomeScreen(onLock: _handleLock);
        }

        if (snapshot.data == true) {
          return LoginScreen(onAuthenticated: _handleAuthenticated);
        }

        return FirstLaunchWizard(onComplete: _handleSetupComplete);
      },
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: CMBankTheme.primary),
      ),
    );
  }
}
