import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../settings/app_settings_repository.dart';
import 'backup_log_repository.dart';
import 'database_backup_service.dart';
import 'drive_service.dart';

/// Foreground Secondary-device sync: pulls the latest backup from Drive through
/// the shared restore pipeline (which re-pins the device as Secondary and skips
/// bulk photo restore).
///
/// Runs on the main isolate only — the previous WorkManager background worker
/// was removed because swapping the database file from a separate isolate while
/// the app held an open handle hung the UI. Callers (Home pull-to-refresh and
/// the foreground auto-sync timer) show their own progress UI and reload after.
///
/// Never throws: failures are logged to backup_log and surface only as a stale
/// "Last Synced" time. Returns true on success (or a Primary no-op).
Future<bool> runSecondarySync() async {
  try {
    await AppDatabase.instance.initialize();

    final settings = AppSettingsRepository();
    final mode =
        (await settings.getString('device_mode'))?.trim().toLowerCase();
    if (mode != 'secondary') return true; // Primary/unconfigured: no-op.

    // Drive must be authenticated. Silent sign-in only (no UI here).
    if (!DriveService.instance.isAuthenticated()) {
      await DriveService.instance.trySilentSignIn();
    }
    if (!DriveService.instance.isAuthenticated()) {
      await _logSyncFailed('Google Drive not connected.');
      return false;
    }

    // Newest backup first.
    final files = await DatabaseBackupService.instance.listDriveBackups();
    if (files.isEmpty) {
      await _logSyncFailed('No backups found on Google Drive.');
      return false;
    }

    // Reuse the shared restore pipeline. The admin PIN is ignored when the
    // Keystore AES key is present (persisted during the first interactive
    // restore), so an empty PIN is correct for this headless sync.
    await DatabaseBackupService.instance.restoreFromDrive(files.first.id, '');
    return true;
  } catch (e) {
    debugPrint('Secondary sync failed: $e');
    await _logSyncFailed('Scheduled sync failed: $e');
    return false;
  }
}

Future<void> _logSyncFailed(String message) async {
  try {
    await BackupLogRepository.instance.log(
      operation: BackupOperation.restore,
      backupType: BackupType.database,
      destination: BackupDestination.drive,
      status: BackupStatus.failed,
      message: message,
    );
  } catch (_) {
    // Logging is best-effort.
  }
}
