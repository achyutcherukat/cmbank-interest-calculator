import '../settings/app_settings_repository.dart';
import 'backup_log_repository.dart';
import 'database_backup_service.dart';
import 'drive_service.dart';
import 'photo_sync_repository.dart';
import 'storage_service.dart';

/// Aggregated backup status for the home status bar (Part 9) and the admin
/// backup settings (Part 11).
class BackupStatusSnapshot {
  const BackupStatusSnapshot({
    this.lastDriveBackup,
    this.lastDriveBackupFailedAt,
    this.lastPhotoBackup,
    this.pendingPhotos = 0,
    this.totalPhotos = 0,
    this.lastLocalBackup,
    this.driveFreeMb,
    this.deviceFreeMb,
    this.driveAuthed = false,
    this.signedInEmail = '',
  });

  final DateTime? lastDriveBackup;
  final DateTime? lastDriveBackupFailedAt;
  final DateTime? lastPhotoBackup;
  final int pendingPhotos;
  final int totalPhotos;
  final DateTime? lastLocalBackup;
  final double? driveFreeMb;
  final double? deviceFreeMb;
  final bool driveAuthed;
  final String signedInEmail;

  bool get driveStorageLow =>
      driveFreeMb != null && driveFreeMb! < kDriveLowFreeMb;
  bool get deviceStorageLow =>
      deviceFreeMb != null && deviceFreeMb! < StorageService.lowMb;
  bool get deviceStorageCritical =>
      deviceFreeMb != null && deviceFreeMb! < StorageService.criticalMb;

  /// True when the most recent Drive backup attempt failed after the last
  /// success (or there has never been a success).
  bool get lastBackupFailed {
    if (lastDriveBackupFailedAt == null) return false;
    if (lastDriveBackup == null) return true;
    return lastDriveBackupFailedAt!.isAfter(lastDriveBackup!);
  }
}

class BackupStatusService {
  BackupStatusService._();
  static final BackupStatusService instance = BackupStatusService._();

  final _settings = AppSettingsRepository();

  Future<BackupStatusSnapshot> load({bool includeDeviceStorage = true}) async {
    final lastDrive = _parse(await _settings.getString('last_drive_backup'));
    final lastPhoto = _parse(await _settings.getString('last_photo_backup'));
    final lastLocal = _parse(await _settings.getString('last_local_backup'));
    final freeStr = await _settings.getString('last_drive_free_mb');
    final driveFree = (freeStr != null && freeStr.isNotEmpty)
        ? double.tryParse(freeStr)
        : null;

    final pending = await PhotoSyncRepository.instance.countPending();
    final total = await PhotoSyncRepository.instance.countTotal();

    final lastFailed = await BackupLogRepository.instance.latest(
      operation: BackupOperation.backup,
      backupType: BackupType.database,
      destination: BackupDestination.drive,
      status: BackupStatus.failed,
    );

    final deviceFree =
        includeDeviceStorage ? await StorageService.instance.freeDeviceMb() : null;

    return BackupStatusSnapshot(
      lastDriveBackup: lastDrive,
      lastDriveBackupFailedAt: _parse(lastFailed?.createdAt),
      lastPhotoBackup: lastPhoto,
      pendingPhotos: pending,
      totalPhotos: total,
      lastLocalBackup: lastLocal,
      driveFreeMb: driveFree,
      deviceFreeMb: deviceFree,
      driveAuthed: DriveService.instance.isAuthenticated(),
      signedInEmail: DriveService.instance.getSignedInEmail(),
    );
  }

  DateTime? _parse(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso);
  }
}

/// Formats a timestamp as `DD/MM/YYYY HH:MM` (app-wide convention). Returns
/// `Never` for null.
String formatBackupTime(DateTime? dt) {
  if (dt == null) return 'Never';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

/// Formats a date as `DD/MM/YYYY`. Returns `Never` for null.
String formatBackupDate(DateTime? dt) {
  if (dt == null) return 'Never';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year}';
}
