import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';
import 'core/services/backup_scheduler.dart';
import 'core/services/drive_service.dart';
import 'core/services/notification_service.dart';
import 'core/settings/app_settings_repository.dart';

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
    await NotificationService.instance.init();
  } catch (_) {}
  try {
    await DriveService.instance.trySilentSignIn();
  } catch (_) {}
  try {
    // Only schedule background backups once the device has been set up.
    final setup =
        await AppSettingsRepository().getBool('device_setup_complete');
    if (setup) await BackupScheduler.reschedule();
  } catch (_) {}
}
