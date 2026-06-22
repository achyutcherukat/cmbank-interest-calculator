import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../database/app_database.dart';
import '../settings/app_settings_repository.dart';
import 'database_backup_service.dart';

/// WorkManager task identifiers.
const String kBackupTaskName = 'cmb_scheduled_backup';
const String kBackupUniqueName = 'cmb_scheduled_backup_periodic';

/// Background entry point. Must be a top-level / static function annotated with
/// `vm:entry-point` so it survives tree-shaking and can run in the background
/// isolate.
@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // Background isolate: the database/plugins must be re-initialised here.
      await AppDatabase.instance.initialize();

      final settings = AppSettingsRepository();
      final startStr = await settings.getString('backup_start_time') ?? '09:00';
      final endStr = await settings.getString('backup_end_time') ?? '17:30';

      // Only back up inside the configured daily window; otherwise skip silently.
      if (!_withinWindow(startStr, endStr)) return true;

      await DatabaseBackupService.instance.backupToDrive(scheduled: true);
      return true;
    } catch (e) {
      debugPrint('Scheduled backup task failed: $e');
      return false;
    }
  });
}

bool _withinWindow(String startHHmm, String endHHmm) {
  final now = DateTime.now();
  final start = _todayAt(startHHmm);
  final end = _todayAt(endHHmm);
  return !now.isBefore(start) && !now.isAfter(end);
}

DateTime _todayAt(String hhmm) {
  final now = DateTime.now();
  final parts = hhmm.split(':');
  final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 9;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return DateTime(now.year, now.month, now.day, h, m);
}

/// Registers/reschedules the repeating backup task. WorkManager enforces a
/// 15-minute minimum frequency. Call [BackupScheduler.reschedule] whenever the
/// schedule settings change; the schedule survives app restarts.
class BackupScheduler {
  const BackupScheduler._();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await Workmanager().initialize(
      backupCallbackDispatcher,
      isInDebugMode: false,
    );
    _initialized = true;
  }

  static Future<void> reschedule() async {
    await init();
    final settings = AppSettingsRepository();
    final freqStr = await settings.getString('backup_frequency') ?? '30';
    final freq = int.tryParse(freqStr) ?? 30;
    final minutes = freq < 15 ? 15 : freq;

    await Workmanager().cancelByUniqueName(kBackupUniqueName);
    await Workmanager().registerPeriodicTask(
      kBackupUniqueName,
      kBackupTaskName,
      frequency: Duration(minutes: minutes),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  static Future<void> cancel() async {
    await init();
    await Workmanager().cancelByUniqueName(kBackupUniqueName);
  }
}
