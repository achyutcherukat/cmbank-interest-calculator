import 'dart:io';

import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/services/crash_recovery.dart';
import '../core/settings/app_settings_repository.dart';
import '../features/admin/data/audit_log_repository.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/backup/presentation/database_error_screen.dart';
import '../features/calculator/presentation/home_screen.dart';
import '../features/setup/presentation/restore_or_setup_screen.dart';
import 'theme.dart';

/// Result of the launch-time checks.
enum _StartupState { corrupt, needsSetup, ready }

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> with WidgetsBindingObserver {
  final AppSettingsRepository _settingsRepository = AppSettingsRepository();
  late Future<_StartupState> _startup;
  bool _isAuthenticated = false;
  bool _crashNoticeShown = false;
  DateTime? _backgroundedAt;

  static const _lockTimeout = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startup = _runStartupChecks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _backgroundedAt = DateTime.now();
      // Mark a clean exit point for crash detection (Part 7).
      CrashRecovery.instance.markClean();
    } else if (state == AppLifecycleState.resumed) {
      CrashRecovery.instance.markRunning();
      if (_isAuthenticated) {
        final bg = _backgroundedAt;
        if (bg != null && DateTime.now().difference(bg) >= _lockTimeout) {
          setState(() => _isAuthenticated = false);
        }
        _backgroundedAt = null;
      }
    }
  }

  /// Runs the launch-time integrity + crash-recovery checks (Part 7).
  Future<_StartupState> _runStartupChecks() async {
    final dbPath = await AppDatabase.instance.databaseFilePath;

    // Remove any stray temp file left by an interrupted restore.
    try {
      final tmp = File('$dbPath.restore_tmp');
      if (tmp.existsSync()) await tmp.delete();
    } catch (_) {}

    // 1. Database integrity — only if the file already exists.
    //    On a fresh install there is no file yet; skipping is correct because
    //    there is nothing to be corrupt. Catching a creation failure as
    //    "corrupt" was the regression that showed DatabaseErrorScreen on fresh
    //    install instead of RestoreOrSetupScreen.
    if (File(dbPath).existsSync()) {
      try {
        await AppDatabase.instance.initialize();
      } catch (_) {
        return _StartupState.corrupt;
      }
      bool healthy;
      try {
        healthy = await AppDatabase.instance.isHealthy();
      } catch (_) {
        healthy = false;
      }
      if (!healthy) return _StartupState.corrupt;
    } else {
      // Fresh install: create the database now. If creation fails (e.g.
      // storage full) we still route to the setup screen — not the corruption
      // screen — because there is nothing to restore from.
      try {
        await AppDatabase.instance.initialize();
      } catch (_) {
        // Fall through; RestoreOrSetupScreen handles the failure gracefully.
      }
    }

    // 2. Crash recovery — note an unclean previous shutdown, then mark running.
    try {
      if (await CrashRecovery.instance.wasUncleanShutdown()) {
        await CrashRecovery.instance.logRecovery();
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _showCrashNotice());
      }
      await CrashRecovery.instance.markRunning();
    } catch (_) {
      // Non-critical.
    }

    // 3. Audit log auto-purge — silent, non-blocking.
    try {
      final retentionStr =
          await _settingsRepository.getString('audit_log_retention_days');
      final retention = int.tryParse(retentionStr ?? '') ?? 90;
      await AuditLogRepository.instance.purge(retention);
    } catch (_) {}

    // 4. First-launch state.
    bool setup;
    try {
      setup = await _settingsRepository.getBool('device_setup_complete');
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'cm_bank_startup',
          context: ErrorDescription('while reading first launch settings'),
        ),
      );
      setup = true;
    }
    return setup ? _StartupState.ready : _StartupState.needsSetup;
  }

  void _showCrashNotice() {
    if (_crashNoticeShown || !mounted) return;
    _crashNoticeShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 8),
        backgroundColor: CMBColors.warningOrange,
        content: Text(
          'The app was closed unexpectedly. Your last action may not have been '
          'saved. Please verify your most recent entries.',
        ),
      ),
    );
  }

  void _handleSetupComplete() {
    setState(() {
      _startup = Future.value(_StartupState.ready);
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
    return FutureBuilder<_StartupState>(
      future: _startup,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _StartupLoadingScreen();
        }

        switch (snapshot.data!) {
          case _StartupState.corrupt:
            return const DatabaseErrorScreen();
          case _StartupState.needsSetup:
            return RestoreOrSetupScreen(onSetupComplete: _handleSetupComplete);
          case _StartupState.ready:
            return _isAuthenticated
                ? HomeScreen(onLock: _handleLock)
                : LoginScreen(onAuthenticated: _handleAuthenticated);
        }
      },
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: CMBColors.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: AssetImage('assets/images/cmb_logo.png'),
              width: 180,
              height: 180,
            ),
            SizedBox(height: 56),
            CircularProgressIndicator(color: CMBColors.goldRich),
          ],
        ),
      ),
    );
  }
}
