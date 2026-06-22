import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../settings/app_settings_repository.dart';
import 'backup_log_repository.dart';
import 'drive_service.dart';
import 'photo_sync_repository.dart';

/// Progress for the silent post-restore photo download (Part 5B).
class PhotoRestoreProgress {
  const PhotoRestoreProgress({required this.done, required this.total});
  final int done;
  final int total;
  bool get complete => done >= total;
}

class PhotoBackupResult {
  const PhotoBackupResult({required this.synced, required this.total, required this.failed});
  final int synced;
  final int total;
  final int failed;
}

class PhotoRestoreResult {
  const PhotoRestoreResult({
    required this.found,
    required this.restored,
    required this.failed,
  });
  final int found;
  final int restored;
  final int failed;
  bool get nothingToRestore => found == 0;
}

/// Uploads pending photos to Drive (Part 5A) and silently restores them after a
/// database restore (Part 5B). Inline single-photo restore supports Part 5C.
class PhotoBackupService {
  PhotoBackupService._();
  static final PhotoBackupService instance = PhotoBackupService._();

  final _settings = AppSettingsRepository();

  /// Drives the bottom "Restoring photos…" banner on the home screen. Null when
  /// no restore is in progress.
  final ValueNotifier<PhotoRestoreProgress?> restoreProgress =
      ValueNotifier<PhotoRestoreProgress?>(null);

  /// Set by _finishRestore() so the home screen starts the download after
  /// it's mounted — ensuring the progress banner is always visible.
  bool needsRestore = false;

  /// Incremented each time a bulk restore completes with at least one photo
  /// downloaded. RestorablePhotoThumb widgets listen to this to re-check their
  /// file and drop the placeholder without requiring a screen rebuild.
  final ValueNotifier<int> photosRestored = ValueNotifier(0);

  static const _maxKbByType = <String, int>{
    PhotoType.idProof: 200,
    PhotoType.gold: 300,
    PhotoType.document: 200,
  };

  // ── Part 5A: backup pending photos ───────────────────────────────────────────

  Future<PhotoBackupResult> backupPendingPhotos() async {
    final pending = await PhotoSyncRepository.instance.getUnsynced();
    if (pending.isEmpty) {
      return const PhotoBackupResult(synced: 0, total: 0, failed: 0);
    }

    var synced = 0;
    var failed = 0;
    for (final photo in pending) {
      try {
        final file = File(photo.localPath);
        if (!await file.exists()) {
          await PhotoSyncRepository.instance
              .markError(photo.id, 'local file missing');
          failed++;
          continue;
        }
        final raw = await file.readAsBytes();
        final maxKb = _maxKbByType[photo.photoType] ?? 300;
        final compressed = await compute(_compressEntry,
            _CompressArgs(raw, maxKb));
        final folder = await _driveFolderFor(photo);
        final fileName = p.basename(photo.localPath);
        final driveId = await DriveService.instance
            .uploadFile(fileName, compressed, folder);
        await PhotoSyncRepository.instance.markSynced(photo.id, driveId);
        synced++;
      } catch (e) {
        await PhotoSyncRepository.instance.markError(photo.id, e.toString());
        failed++;
      }
    }

    await _settings.upsertMany({
      'last_photo_backup': (value: DateTime.now().toIso8601String(), type: 'string'),
    });
    await BackupLogRepository.instance.log(
      operation: BackupOperation.backup,
      backupType: BackupType.photo,
      destination: BackupDestination.drive,
      status: failed == 0 ? BackupStatus.success : BackupStatus.failed,
      message: '$synced of ${pending.length} photos synced',
    );

    return PhotoBackupResult(
        synced: synced, total: pending.length, failed: failed);
  }

  // ── Part 5B: silent restore after database restore ───────────────────────────

  /// Downloads any synced photos that are missing locally. Runs in the
  /// background; updates [restoreProgress] for the home-screen banner.
  /// Returns counts so callers can show meaningful feedback.
  Future<PhotoRestoreResult> restoreMissingPhotos() async {
    // Ensure Drive session is alive before iterating.
    if (!DriveService.instance.isAuthenticated()) {
      await DriveService.instance.trySilentSignIn();
    }

    final synced = await PhotoSyncRepository.instance.getSynced();
    final missing = <PhotoSyncEntry>[];
    for (final photo in synced) {
      if (!await File(photo.localPath).exists()) missing.add(photo);
    }
    if (missing.isEmpty) {
      restoreProgress.value = null;
      return const PhotoRestoreResult(found: 0, restored: 0, failed: 0);
    }

    var done = 0;
    var restored = 0;
    restoreProgress.value = PhotoRestoreProgress(done: 0, total: missing.length);
    for (final photo in missing) {
      try {
        await _downloadToLocal(photo);
        restored++;
      } catch (e) {
        await PhotoSyncRepository.instance.markDownloadError(photo.id, e.toString());
      }
      done++;
      restoreProgress.value =
          PhotoRestoreProgress(done: done, total: missing.length);
    }
    restoreProgress.value = null;
    if (restored > 0) photosRestored.value++;
    return PhotoRestoreResult(
        found: missing.length,
        restored: restored,
        failed: missing.length - restored);
  }

  // ── Part 5C: inline single-photo restore ─────────────────────────────────────

  /// Restores one photo on demand from its placeholder. Returns the new local
  /// path, or null on failure.
  Future<String?> restoreSinglePhoto(String localPath) async {
    if (!DriveService.instance.isAuthenticated()) {
      await DriveService.instance.trySilentSignIn();
    }
    final entry =
        await PhotoSyncRepository.instance.findByLocalPath(localPath);
    if (entry == null || entry.drivePath == null) return null;
    try {
      return await _downloadToLocal(entry);
    } catch (_) {
      return null;
    }
  }

  // ── Internals ────────────────────────────────────────────────────────────────

  Future<String> _downloadToLocal(PhotoSyncEntry photo) async {
    final bytes = await DriveService.instance.downloadFile(photo.drivePath!);
    // Restore to the exact original path so pledge/customer tables remain valid.
    final file = File(photo.localPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return photo.localPath;
  }

  Future<String> _driveFolderFor(PhotoSyncEntry photo) async {
    switch (photo.photoType) {
      case PhotoType.gold:
        final no = await _pledgeNo(photo.pledgeId);
        return '${DriveService.drivePhotosFolder}/gold/$no';
      case PhotoType.document:
        final no = await _pledgeNo(photo.pledgeId);
        return '${DriveService.drivePhotosFolder}/document/$no';
      case PhotoType.idProof:
      default:
        return '${DriveService.drivePhotosFolder}/id_proof/${photo.customerId ?? 'unknown'}';
    }
  }

  Future<String> _pledgeNo(int? pledgeId) async {
    if (pledgeId == null) return 'unknown';
    final db = await AppDatabase.instance.database;
    final rows = await db.query('pledges',
        columns: ['pledge_no'], where: 'id = ?', whereArgs: [pledgeId], limit: 1);
    if (rows.isEmpty) return pledgeId.toString();
    return (rows.first['pledge_no'] as String?) ?? pledgeId.toString();
  }
}

class _CompressArgs {
  const _CompressArgs(this.bytes, this.maxKb);
  final Uint8List bytes;
  final int maxKb;
}

/// Re-encodes to JPEG, lowering quality (then downscaling) until under the size
/// target. Runs in an isolate via [compute].
Uint8List _compressEntry(_CompressArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) {
    final maxBytes = args.maxKb * 1024;
    if (args.bytes.length > maxBytes) {
      throw StateError(
          'Unrecognised image format: raw size ${args.bytes.length} bytes '
          'exceeds the ${args.maxKb} KB limit and cannot be compressed.');
    }
    return args.bytes;
  }
  final maxBytes = args.maxKb * 1024;

  var quality = 90;
  var working = decoded;
  Uint8List out = Uint8List.fromList(img.encodeJpg(working, quality: quality));

  while (out.length > maxBytes && quality > 30) {
    quality -= 10;
    out = Uint8List.fromList(img.encodeJpg(working, quality: quality));
  }

  // Still too large — progressively downscale.
  while (out.length > maxBytes && working.width > 600) {
    working = img.copyResize(working, width: (working.width * 0.8).round());
    out = Uint8List.fromList(img.encodeJpg(working, quality: 70));
  }

  return out;
}
