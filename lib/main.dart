import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';
import 'core/services/backup_scheduler.dart';
import 'core/services/drive_service.dart';
import 'core/services/notification_service.dart';
import 'core/settings/app_settings_repository.dart';
import 'features/accounts/presentation/daily_accounts_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await AppDatabase.instance.initialize();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'cm_bank_database',
        context: ErrorDescription('while opening the local SQLite database'),
      ),
    );
  }

  // Backup infrastructure — all best-effort, never block app launch.
  _initBackupInfra();

  runApp(const CMBankApp());
}

Future<void> _initBackupInfra() async {
  try {
    await NotificationService.instance.init(
      onTap: (payload) async {
        if (payload == 'open_cash_book') {
          appNavigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const DailyAccountsScreen()),
          );
        }
      },
    );
  } catch (_) {}
  try {
    await DriveService.instance.trySilentSignIn();
  } catch (_) {}
  try {
    final settings = AppSettingsRepository();
    // Only schedule background work once the device has been set up.
    final setup = await settings.getBool('device_setup_complete');
    // Primary devices schedule background Drive backups. Secondary devices sync
    // in the foreground only (see home_screen) — reschedule() self-cancels on
    // Secondary, so calling it unconditionally is safe.
    if (setup) await BackupScheduler.reschedule();
  } catch (_) {}
}
