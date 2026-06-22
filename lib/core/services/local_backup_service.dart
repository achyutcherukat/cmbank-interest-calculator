import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../settings/app_settings_repository.dart';
import 'backup_log_repository.dart';
import 'database_backup_service.dart';

class LocalBackupResult {
  const LocalBackupResult({required this.success, this.path, this.message});
  final bool success;
  final String? path;
  final String? message;
}

class PickedBackup {
  const PickedBackup({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;
}

/// Manual encrypted backup to the device Downloads folder, plus file-picker
/// restore (Part 6). The Downloads copy survives app uninstall.
class LocalBackupService {
  LocalBackupService._();
  static final LocalBackupService instance = LocalBackupService._();

  static const _downloadsDir = '/storage/emulated/0/Download/CMBank';

  final _settings = AppSettingsRepository();

  /// Requests the storage permission appropriate for the device. Returns true
  /// when writing to Downloads is permitted.
  Future<bool> ensureStoragePermission() async {
    // Android 11+ : MANAGE_EXTERNAL_STORAGE; older : WRITE_EXTERNAL_STORAGE.
    if (await Permission.manageExternalStorage.isGranted) return true;
    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return true;
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  Future<LocalBackupResult> backupToDevice() async {
    try {
      if (!await ensureStoragePermission()) {
        const msg = 'Storage permission denied.';
        await _logFailed(msg);
        return const LocalBackupResult(success: false, message: msg);
      }

      final dir = Directory(_downloadsDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final encrypted =
          await DatabaseBackupService.instance.buildEncryptedArchive();
      final fileName = 'cmbank_local_${_timestamp()}.enc';
      final path = '${dir.path}/$fileName';
      await File(path).writeAsBytes(encrypted, flush: true);
      final sizeMb = encrypted.length / (1024 * 1024);

      await _settings.upsertMany({
        'last_local_backup': (
          value: DateTime.now().toIso8601String(),
          type: 'string'
        ),
      });
      await BackupLogRepository.instance.log(
        operation: BackupOperation.backup,
        backupType: BackupType.database,
        destination: BackupDestination.local,
        status: BackupStatus.success,
        fileName: fileName,
        fileSize: sizeMb,
      );

      return LocalBackupResult(success: true, path: path);
    } catch (e) {
      final msg = 'Local backup failed: $e';
      await _logFailed(msg);
      return LocalBackupResult(success: false, message: msg);
    }
  }

  /// Opens a file picker (default Downloads/CMBank) filtered to .enc files.
  Future<PickedBackup?> pickEncryptedFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    if (!file.name.toLowerCase().endsWith('.enc')) {
      throw const RestoreException(
          RestoreErrorKind.corrupted, 'Please select a .enc backup file.');
    }
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return null;
    return PickedBackup(bytes: bytes, name: file.name);
  }

  /// Restores from a picked local backup. UI handles PIN + typed confirmation.
  Future<void> restoreFromDevice(Uint8List bytes, String adminPin) async {
    await DatabaseBackupService.instance.restoreFromEncrypted(
      bytes,
      adminPin,
      destination: BackupDestination.local,
    );
  }

  Future<void> _logFailed(String message) async {
    await BackupLogRepository.instance.log(
      operation: BackupOperation.backup,
      backupType: BackupType.database,
      destination: BackupDestination.local,
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
