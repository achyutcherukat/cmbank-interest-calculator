import 'package:flutter/material.dart';

import '../../../app/startup_gate.dart';
import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/database_backup_service.dart';
import '../../../core/services/drive_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/services/local_backup_service.dart';
import '../../../core/services/photo_backup_service.dart';

/// Shared backup/restore flows + dialogs used by the admin backup settings
/// (Part 11) and the database-error recovery screen (Part 7). Each entry point
/// owns its own progress indicators, confirmations and result snackbars.
class BackupActions {
  const BackupActions._();

  // ── Drive backup ─────────────────────────────────────────────────────────────

  static Future<void> backupNow(BuildContext context) async {
    if (!await _ensureKey(context)) return;
    if (!context.mounted) return;
    final result = await _withProgress<BackupResult>(
      context,
      'Backing up to Google Drive…',
      () => DatabaseBackupService.instance.backupToDrive(),
    );
    if (!context.mounted || result == null) return;
    if (result.success) {
      _snack(context,
          'Backup complete (${result.fileSizeMb?.toStringAsFixed(1) ?? '?'} MB).');
    } else {
      _snack(context, result.message ?? 'Backup failed.', error: true);
    }
  }

  static Future<void> restorePhotosNow(BuildContext context) async {
    if (!DriveService.instance.isAuthenticated()) {
      await DriveService.instance.trySilentSignIn();
    }
    if (!DriveService.instance.isAuthenticated()) {
      if (context.mounted) {
        _snack(context,
            'Not signed in to Google Drive. Sign in from the backup settings first.',
            error: true);
      }
      return;
    }
    if (!context.mounted) return;
    final result = await _withProgress<PhotoRestoreResult>(
      context,
      'Restoring photos from Google Drive…',
      () => PhotoBackupService.instance.restoreMissingPhotos(),
    );
    if (!context.mounted || result == null) return;
    if (result.nothingToRestore) {
      _snack(context,
          'No photos to restore — all present locally or none synced to Drive.');
    } else if (result.failed > 0) {
      _snack(
          context,
          '${result.restored} of ${result.found} photos restored. '
          '${result.failed} failed — check Drive connection.',
          error: true);
    } else {
      _snack(context,
          '${result.restored} photo${result.restored == 1 ? '' : 's'} restored successfully.');
    }
  }

  static Future<void> backupToDevice(BuildContext context) async {
    if (!await _ensureKey(context)) return;
    if (!context.mounted) return;
    final result = await _withProgress<LocalBackupResult>(
      context,
      'Saving backup to device…',
      () => LocalBackupService.instance.backupToDevice(),
    );
    if (!context.mounted || result == null) return;
    if (result.success) {
      _snack(context, 'Backup saved to Downloads/CMBank/');
    } else {
      _snack(context, result.message ?? 'Local backup failed.', error: true);
    }
  }

  // ── Restore ──────────────────────────────────────────────────────────────────

  static Future<void> restoreFromDrive(BuildContext context) async {
    try {
      // Step 0: ensure Drive is authenticated.
      if (!DriveService.instance.isAuthenticated()) {
        if (!context.mounted) return;
        final ok = await _withProgress<bool>(
              context,
              'Signing in to Google Drive…',
              () => DriveService.instance.signIn(),
            ) ??
            false;
        if (!ok) {
          if (context.mounted) {
            _snack(context, 'Could not sign in to Google Drive.', error: true);
          }
          return;
        }
      }
      if (!context.mounted) return;

      // Step 1: list backups.
      List<DriveFile> files;
      try {
        files = await _withProgress<List<DriveFile>>(
              context,
              'Loading backups…',
              () => DatabaseBackupService.instance.listDriveBackups(),
            ) ??
            [];
      } on RestoreException catch (e) {
        if (context.mounted) _snack(context, e.message, error: true);
        return;
      }
      if (!context.mounted) return;
      if (files.isEmpty) {
        _snack(
            context,
            'No backups found on Google Drive. Please check you are signed '
            'into the correct Google account.',
            error: true);
        return;
      }

      // Step 2: pick backup.
      final selected = await _pickBackup(context, files);
      if (selected == null || !context.mounted) return;

      // Step 3: PIN prompt. Correctness is verified during decryption —
      // calling verifyAdminPin here would fail when the DB is inaccessible.
      final pin = await promptPin(context);
      if (pin == null || !context.mounted) return;

      // Step 4: confirm.
      if (!await _confirmTypeRestore(context)) return;
      if (!context.mounted) return;

      // Step 5: restore (wrong PIN throws RestoreException(wrongPin)).
      try {
        await _withProgress<void>(
          context,
          'Restoring from Google Drive…',
          () => DatabaseBackupService.instance.restoreFromDrive(selected.id, pin),
        );
      } on RestoreException catch (e) {
        if (context.mounted) _snack(context, e.message, error: true);
        return;
      }
      if (!context.mounted) return;
      await _finishRestore(context);
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Restore failed unexpectedly. Please try again.',
            error: true);
      }
    }
  }

  static Future<void> restoreFromDevice(BuildContext context) async {
    try {
      // Step 1: pick file.
      PickedBackup? picked;
      try {
        picked = await LocalBackupService.instance.pickEncryptedFile();
      } on RestoreException catch (e) {
        if (context.mounted) _snack(context, e.message, error: true);
        return;
      }
      if (picked == null || !context.mounted) return;

      // Step 2: PIN prompt. Correctness is verified during decryption.
      final pin = await promptPin(context);
      if (pin == null || !context.mounted) return;

      // Step 3: confirm.
      if (!await _confirmTypeRestore(context)) return;
      if (!context.mounted) return;

      // Step 4: restore (wrong PIN throws RestoreException(wrongPin)).
      try {
        await _withProgress<void>(
          context,
          'Restoring from device…',
          () => LocalBackupService.instance.restoreFromDevice(picked!.bytes, pin),
        );
      } on RestoreException catch (e) {
        if (context.mounted) _snack(context, e.message, error: true);
        return;
      }
      if (!context.mounted) return;
      await _finishRestore(context);
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Restore failed unexpectedly. Please try again.',
            error: true);
      }
    }
  }

  // ── Key bootstrap ────────────────────────────────────────────────────────────

  /// Ensures an encryption key exists before a backup. On installs created
  /// before backups existed, prompts for the admin PIN to generate one.
  static Future<bool> _ensureKey(BuildContext context) async {
    if (await EncryptionService.instance.hasKeystoreKey()) return true;
    if (!context.mounted) return false;
    final pin = await promptPin(context,
        title: 'Set up backup encryption',
        message: 'Enter the admin PIN to create the backup encryption key.');
    if (pin == null) return false;
    if (!await EncryptionService.instance.verifyAdminPin(pin)) {
      if (context.mounted) _snack(context, 'Incorrect PIN.', error: true);
      return false;
    }
    await EncryptionService.instance.ensureKeyInitialized(pin);
    return true;
  }

  // ── Shared dialogs ───────────────────────────────────────────────────────────

  static Future<String?> promptPin(
    BuildContext context, {
    String title = 'Enter Admin PIN',
    String? message,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message != null) ...[
              Text(message, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Admin PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((v) => (v == null || v.isEmpty) ? null : v);
  }

  static Future<bool> _confirmTypeRestore(BuildContext context) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final canRestore = controller.text.trim().toUpperCase() == 'RESTORE';
          return AlertDialog(
            title: const Text('Confirm Restore'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will replace ALL current data. This cannot be undone.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text('Type RESTORE to confirm:',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'RESTORE'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: CMBColors.warningRed),
                onPressed: canRestore ? () => Navigator.pop(ctx, true) : null,
                child: const Text('RESTORE'),
              ),
            ],
          );
        },
      ),
    );
    return ok ?? false;
  }

  static Future<DriveFile?> _pickBackup(
      BuildContext context, List<DriveFile> files) {
    return showModalBottomSheet<DriveFile>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select a backup to restore',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (_, i) {
                  final f = files[i];
                  return ListTile(
                    leading: const Icon(Icons.cloud_done,
                        color: CMBColors.navy),
                    title: Text(_displayTime(f.modifiedTime)),
                    subtitle: Text('${f.sizeMb.toStringAsFixed(2)} MB'),
                    onTap: () => Navigator.pop(ctx, f),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  /// Re-opens the database, kicks off silent photo restore, and returns the user
  /// to a fresh app root (logical restart) after a successful restore.
  static Future<void> _finishRestore(BuildContext context) async {
    await AppDatabase.instance.initialize();
    // Defer photo restore until home screen is mounted so the banner shows.
    PhotoBackupService.instance.needsRestore = true;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore complete'),
        content: const Text(
            'Data restored successfully. The app will now reload.'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const StartupGate()),
      (route) => false,
    );
  }

  static Future<T?> _withProgress<T>(
    BuildContext context,
    String message,
    Future<T> Function() task,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(message: message),
    );
    try {
      final result = await task();
      return result;
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  static void _snack(BuildContext context, String message,
      {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? CMBColors.warningRed : CMBColors.navy,
      ),
    );
  }

  static String _displayTime(DateTime? dt) {
    if (dt == null) return 'Unknown date';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}  '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(color: CMBColors.navy),
          const SizedBox(width: 20),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
