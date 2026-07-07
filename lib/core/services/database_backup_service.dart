import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../database/app_database.dart';
import '../settings/app_settings_repository.dart';
import 'backup_log_repository.dart';
import 'drive_service.dart';
import 'encryption_service.dart';
import 'notification_service.dart';
import 'photo_backup_service.dart';

const String kAppVersion = '1.0.0';
const double kDriveLowFreeMb = 2048; // 2 GB

class BackupResult {
  const BackupResult({
    required this.success,
    this.fileName,
    this.fileSizeMb,
    this.message,
    this.driveLowStorage = false,
  });

  final bool success;
  final String? fileName;
  final double? fileSizeMb;
  final String? message;
  final bool driveLowStorage;
}

enum RestoreErrorKind { wrongPin, corrupted, network, storage, notFound, unknown }

class RestoreException implements Exception {
  const RestoreException(this.kind, this.message);
  final RestoreErrorKind kind;
  final String message;
  @override
  String toString() => message;
}

/// Encrypted, compressed full-database backup to Google Drive + restore.
class DatabaseBackupService {
  DatabaseBackupService._();
  static final DatabaseBackupService instance = DatabaseBackupService._();

  final _settings = AppSettingsRepository();

  // ── Backup ───────────────────────────────────────────────────────────────────

  /// Runs a full database backup to Drive. [scheduled] controls whether a push
  /// notification is sent on failure (only scheduled failures notify, per spec).
  Future<BackupResult> backupToDrive({bool scheduled = false}) async {
    // Secondary devices are read-only mirrors: they only ever restore from
    // Drive, never back up to it. This is the single hard guarantee — it blocks
    // every caller (scheduled worker, manual backup, any future trigger).
    // Silent no-op: no upload, no backup_log entry, no failure notification.
    final mode = (await _settings.getString('device_mode'))?.trim().toLowerCase();
    if (mode == 'secondary') {
      return const BackupResult(
        success: false,
        message: 'This device is read-only and does not back up to Drive.',
      );
    }

    // 1. Drive must be authenticated.
    if (!DriveService.instance.isAuthenticated()) {
      final restored = await DriveService.instance.trySilentSignIn();
      if (!restored) {
        const msg = 'Google Drive not connected.';
        await _logFailed(BackupType.database, BackupDestination.drive, msg);
        if (scheduled) await NotificationService.instance.showBackupFailed();
        return const BackupResult(success: false, message: msg);
      }
    }

    bool driveLow = false;
    try {
      // 2. Storage check — warn but continue.
      try {
        final quota = await DriveService.instance.getStorageQuota();
        driveLow = quota.freeMb.isFinite && quota.freeMb < kDriveLowFreeMb;
        await _settings.upsertMany({
          'last_drive_free_mb': (
            value: quota.freeMb.isFinite ? quota.freeMb.toStringAsFixed(0) : '',
            type: 'string'
          ),
        });
      } catch (_) {
        // Quota lookup is best-effort.
      }

      // Sync pending photos before building the archive so the backup always
      // contains up-to-date drive_path values in photo_sync_log.
      await PhotoBackupService.instance.backupPendingPhotos();

      // 3-7. Build encrypted, compressed archive.
      final encrypted = await _buildEncryptedArchive();

      // 8. Upload.
      final fileName = 'cmbank_db_${_timestamp()}.enc';
      await DriveService.instance
          .uploadFile(fileName, encrypted, DriveService.driveBackupsFolder);
      final sizeMb = encrypted.length / (1024 * 1024);

      // 9. Retention + bookkeeping + log.
      final retentionDays = await _intSetting('backup_retention_days', 7);
      await _applyRetention(retentionDays);
      await _settings.upsertMany({
        'last_drive_backup': (
          value: DateTime.now().toIso8601String(),
          type: 'string'
        ),
      });
      double? freeMb;
      final freeStr = await _settings.getString('last_drive_free_mb');
      if (freeStr != null && freeStr.isNotEmpty) freeMb = double.tryParse(freeStr);
      await BackupLogRepository.instance.log(
        operation: BackupOperation.backup,
        backupType: BackupType.database,
        destination: BackupDestination.drive,
        status: BackupStatus.success,
        fileName: fileName,
        fileSize: sizeMb,
        driveStorageFree: freeMb,
      );

      return BackupResult(
        success: true,
        fileName: fileName,
        fileSizeMb: sizeMb,
        driveLowStorage: driveLow,
      );
    } catch (e) {
      final msg = 'Backup failed: $e';
      await _logFailed(BackupType.database, BackupDestination.drive, msg);
      if (scheduled) await NotificationService.instance.showBackupFailed();
      return BackupResult(success: false, message: msg, driveLowStorage: driveLow);
    }
  }

  // v2 backup format: magic marker prepended before the encrypted payload so
  // the key recovery copy can survive a complete device reset / fresh install.
  static const _headerMagic = [0x43, 0x4D, 0x02, 0x00]; // "CM\x02\x00"

  /// Builds the encrypted gzip(tar(db + metadata.json)) payload.
  /// Shared by Drive and local backup.
  Future<Uint8List> _buildEncryptedArchive() async {
    final dbPath = await AppDatabase.instance.databaseFilePath;

    // Flush WAL → main file before reading raw bytes. In WAL mode, recent
    // writes (markSynced, backup_log) live only in cm_bank.db-wal until a
    // checkpoint; reading the raw file without this misses those writes.
    final db = await AppDatabase.instance.database;
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');

    final dbBytes = await File(dbPath).readAsBytes();
    final checksum = EncryptionService.instance.generateChecksum(dbBytes);

    final metadata = jsonEncode({
      'version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'app_version': kAppVersion,
      'checksum': checksum,
    });

    final archive = Archive();
    archive.addFile(ArchiveFile(
        AppDatabase.instance.databaseFileName, dbBytes.length, dbBytes));
    final metaBytes = utf8.encode(metadata);
    archive.addFile(ArchiveFile('metadata.json', metaBytes.length, metaBytes));

    final tarBytes = TarEncoder().encode(archive);
    final gzBytes = GZipEncoder().encode(tarBytes);
    if (gzBytes == null) throw StateError('Compression failed.');
    final encrypted = await EncryptionService.instance
        .encryptBytes(Uint8List.fromList(gzBytes));

    // Prepend v2 cleartext header containing the PIN-encrypted key recovery
    // copy. This allows restore on a fresh install where the Keystore and
    // settings DB have both been wiped.
    final bke = await _settings.getString('backup_key_encrypted') ?? '';
    if (bke.isEmpty) return encrypted; // key not yet initialised — v1 fallback

    final headerBytes = utf8.encode(jsonEncode({'bke': bke}));
    final out = BytesBuilder()
      ..add(_headerMagic)
      ..add(_int32be(headerBytes.length))
      ..add(headerBytes)
      ..add(encrypted);
    return out.toBytes();
  }

  static Uint8List _int32be(int v) => Uint8List(4)
    ..[0] = (v >> 24) & 0xff
    ..[1] = (v >> 16) & 0xff
    ..[2] = (v >> 8) & 0xff
    ..[3] = v & 0xff;

  /// Exposes the encrypted payload to the local backup service.
  Future<Uint8List> buildEncryptedArchive() => _buildEncryptedArchive();

  // ── Restore ──────────────────────────────────────────────────────────────────

  Future<List<DriveFile>> listDriveBackups() async {
    try {
      final files =
          await DriveService.instance.listFiles(DriveService.driveBackupsFolder);
      files.sort((a, b) => (b.modifiedTime ?? DateTime(0))
          .compareTo(a.modifiedTime ?? DateTime(0)));
      return files;
    } catch (e) {
      throw RestoreException(RestoreErrorKind.network,
          'Could not load backups from Google Drive.');
    }
  }

  Future<void> restoreFromDrive(String driveFileId, String adminPin) async {
    Uint8List encrypted;
    try {
      encrypted = await DriveService.instance.downloadFile(driveFileId);
    } catch (e) {
      throw const RestoreException(
          RestoreErrorKind.network, 'Download failed.');
    }
    await restoreFromEncrypted(encrypted, adminPin,
        destination: BackupDestination.drive);
  }

  /// Decrypts, verifies and replaces the live database. Caller is responsible
  /// for triggering photo restore and restarting the app afterwards.
  Future<void> restoreFromEncrypted(
    Uint8List encrypted,
    String adminPin, {
    required String destination,
  }) async {
    // Capture this device's identity BEFORE the restore overwrites the local
    // settings table with the Primary device's values from the backup. Used
    // below to re-pin a Secondary device back to itself.
    final priorMode = await _settings.getString('device_mode');
    final priorName = await _settings.getString('device_name');

    // v2 format: detect cleartext header and pre-populate the key recovery
    // copy in settings so decryption works even on a completely fresh install.
    var payload = encrypted;
    if (payload.length >= 8 &&
        payload[0] == _headerMagic[0] &&
        payload[1] == _headerMagic[1] &&
        payload[2] == _headerMagic[2] &&
        payload[3] == _headerMagic[3]) {
      final headerLen = (payload[4] << 24) |
          (payload[5] << 16) |
          (payload[6] << 8) |
          payload[7];
      if (payload.length >= 8 + headerLen) {
        try {
          final header = jsonDecode(
                  utf8.decode(payload.sublist(8, 8 + headerLen)))
              as Map<String, dynamic>;
          final bke = header['bke'] as String?;
          if (bke != null && bke.isNotEmpty) {
            final existing =
                await _settings.getString('backup_key_encrypted');
            if (existing == null || existing.isEmpty) {
              await _settings.upsertMany({
                'backup_key_encrypted': (value: bke, type: 'string'),
              });
            }
          }
          payload = payload.sublist(8 + headerLen);
        } catch (_) {
          // Header unreadable — fall through and treat the whole buffer as v1.
        }
      }
    }

    // Decrypt (wrong PIN / corrupt key → wrongPin).
    Uint8List compressed;
    try {
      compressed =
          await EncryptionService.instance.decryptBytes(payload, adminPin);
    } catch (e) {
      throw const RestoreException(RestoreErrorKind.wrongPin,
          'Incorrect PIN. Cannot decrypt backup.');
    }

    // Decompress + extract.
    List<int> dbBytes;
    Map<String, dynamic> metadata;
    try {
      final tarBytes = GZipDecoder().decodeBytes(compressed);
      final archive = TarDecoder().decodeBytes(tarBytes);
      ArchiveFile? dbFile;
      ArchiveFile? metaFile;
      for (final f in archive) {
        if (f.name == 'metadata.json') metaFile = f;
        if (f.name == AppDatabase.instance.databaseFileName) dbFile = f;
      }
      if (dbFile == null || metaFile == null) {
        throw const FormatException('Missing entries in backup archive.');
      }
      metadata = jsonDecode(utf8.decode(metaFile.content as List<int>))
          as Map<String, dynamic>;
      dbBytes = dbFile.content as List<int>;
    } catch (e) {
      throw const RestoreException(
          RestoreErrorKind.corrupted, 'This backup file is corrupted.');
    }

    // Verify checksum.
    final checksum = metadata['checksum'] as String? ?? '';
    if (!EncryptionService.instance
        .verifyChecksum(Uint8List.fromList(dbBytes), checksum)) {
      await BackupLogRepository.instance.log(
        operation: BackupOperation.restore,
        backupType: BackupType.database,
        destination: destination,
        status: BackupStatus.failed,
        message: 'Checksum mismatch.',
      );
      throw const RestoreException(
          RestoreErrorKind.corrupted, 'This backup file is corrupted.');
    }

    // Atomically replace the live database file via temp-file + rename.
    // Writing to a sibling .restore_tmp file first means the live database is
    // never touched until rename() completes. On Android/POSIX, rename() within
    // the same directory is atomic, so a crash at any earlier point leaves the
    // original database fully intact.
    final dbPath = await AppDatabase.instance.databaseFilePath;
    final tmpFile = File('$dbPath.restore_tmp');
    try {
      // Write to temp while the live connection is still open and untouched.
      await tmpFile.writeAsBytes(dbBytes, flush: true);
      if (await tmpFile.length() != dbBytes.length) {
        throw const RestoreException(
            RestoreErrorKind.storage, 'Not enough storage space to restore.');
      }
      // Close the live connection immediately before the atomic swap.
      await AppDatabase.instance.close();
      // Remove stale WAL/SHM files so they cannot be replayed against the
      // restored database. SQLite's salt-matching already prevents replays
      // across different database files, but deleting removes all ambiguity.
      for (final ext in ['-wal', '-shm']) {
        try {
          final f = File('$dbPath$ext');
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      // rename() atomically replaces dbPath with the verified temp file.
      await tmpFile.rename(dbPath);
    } catch (e) {
      // Clean up temp file in all failure paths so it does not accumulate.
      try {
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {}
      if (e is RestoreException) rethrow;
      throw const RestoreException(RestoreErrorKind.storage,
          'Not enough storage space to restore.');
    }

    // The restored settings table now holds whatever the Primary device that
    // created this backup had. Re-pin this device's identity so a Secondary
    // device never appears as Primary, and record the sync time. The first DB
    // access here transparently re-opens the freshly-restored database (the
    // live connection was closed for the atomic swap above). This runs before
    // the function returns, so there is no window where the app considers
    // itself Primary after a Secondary restore.
    final wasSecondary = (priorMode ?? '').trim().toLowerCase() == 'secondary';
    if (wasSecondary) {
      final name = (priorName == null || priorName.trim().isEmpty)
          ? 'Secondary Device'
          : priorName;
      await _settings.upsertMany({
        'device_mode': (value: 'secondary', type: 'string'),
        'device_name': (value: name, type: 'string'),
        'last_sync_from_drive': (
          value: DateTime.now().toIso8601String(),
          type: 'string'
        ),
      });
    }

    // Centralised bulk photo auto-restore gate, keyed off this device's actual
    // identity after re-pinning. Only Primary devices bulk-download missing
    // photos; Secondary devices skip it entirely (the inline per-photo
    // tap-to-restore mechanism is independent and keeps working). UI call sites
    // no longer set this flag — the decision lives here so it applies to every
    // restore path (wizard, manual, and the scheduled sync).
    final effectiveMode = wasSecondary
        ? 'secondary'
        : ((await _settings.getString('device_mode'))?.trim().toLowerCase() ??
            'primary');
    PhotoBackupService.instance.needsRestore = effectiveMode == 'primary';

    // Persist the AES backup key into the Android Keystore so future headless
    // restores (the Secondary 30-minute background sync) can decrypt without an
    // admin PIN. On a Secondary device the key is otherwise only recovered into
    // memory during this interactive restore and is unavailable to the
    // background isolate. recoverKeyWithPin re-derives it from the just-restored
    // recovery copy using the PIN entered here and writes it to the Keystore.
    // Best-effort — a failure here must not fail the restore itself.
    try {
      if (!await EncryptionService.instance.hasKeystoreKey()) {
        await EncryptionService.instance.recoverKeyWithPin(adminPin);
      }
    } catch (_) {}

    await BackupLogRepository.instance.log(
      operation: BackupOperation.restore,
      backupType: BackupType.database,
      destination: destination,
      status: BackupStatus.success,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Future<void> _applyRetention(int days) async {
    try {
      final files =
          await DriveService.instance.listFiles(DriveService.driveBackupsFolder);
      final cutoff = DateTime.now().subtract(Duration(days: days));
      for (final f in files) {
        final t = f.modifiedTime;
        if (t != null && t.isBefore(cutoff)) {
          await DriveService.instance.deleteFile(f.id);
        }
      }
    } catch (_) {
      // Retention is best-effort; never fail the backup over cleanup.
    }
  }

  Future<int> _intSetting(String key, int fallback) async {
    final v = await _settings.getString(key);
    return int.tryParse(v ?? '') ?? fallback;
  }

  Future<void> _logFailed(
      String type, String destination, String message) async {
    await BackupLogRepository.instance.log(
      operation: BackupOperation.backup,
      backupType: type,
      destination: destination,
      status: BackupStatus.failed,
      message: message,
    );
  }

  String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}
