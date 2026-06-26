import 'package:flutter/material.dart';

import '../../../app/app_branding.dart';
import '../../../app/startup_gate.dart';
import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/database_backup_service.dart';
import '../../../core/services/drive_service.dart';
import '../../../core/services/local_backup_service.dart';
import '../../../core/services/photo_backup_service.dart';
import '../../backup/presentation/backup_actions.dart';
import 'first_launch_wizard.dart';

class RestoreOrSetupScreen extends StatefulWidget {
  const RestoreOrSetupScreen({super.key, required this.onSetupComplete});

  final VoidCallback onSetupComplete;

  @override
  State<RestoreOrSetupScreen> createState() => _RestoreOrSetupScreenState();
}

class _RestoreOrSetupScreenState extends State<RestoreOrSetupScreen> {
  bool _loading = false;
  String _loadingMessage = '';
  bool _showWizard = false;

  // ── Drive restore ─────────────────────────────────────────────────────────

  Future<void> _driveRestore() async {
    _setLoading(true, 'Signing in to Google...');
    final signedIn = await DriveService.instance.signIn();
    if (!signedIn) {
      _setLoading(false);
      if (mounted) _snack('Could not sign in to Google. Please try again.', error: true);
      return;
    }

    _setLoading(true, 'Checking for backups...');
    List<DriveFile> files;
    try {
      files = await DatabaseBackupService.instance.listDriveBackups();
    } on RestoreException catch (e) {
      _setLoading(false);
      if (mounted) _snack(e.message, error: true);
      return;
    }
    _setLoading(false);
    if (!mounted) return;

    if (files.isEmpty) {
      _snack(
        'No backups found in this Google account. '
        'Try signing in with a different account or start fresh.',
        error: true,
      );
      return;
    }

    final selected = await _pickBackup(files);
    if (selected == null || !mounted) return;

    final pin = await BackupActions.promptPin(
      context,
      title: 'Enter Admin PIN',
      message: 'Enter the Admin PIN from your original CM Bank setup.',
    );
    if (pin == null || !mounted) return;

    _setLoading(true, 'Restoring your data...');
    try {
      await DatabaseBackupService.instance.restoreFromDrive(selected.id, pin);
    } on RestoreException catch (e) {
      _setLoading(false);
      if (mounted) {
        _snack(
          e.kind == RestoreErrorKind.wrongPin
              ? 'Incorrect PIN. Please try again.'
              : e.message,
          error: true,
        );
      }
      return;
    }
    _setLoading(false);
    if (!mounted) return;
    await _finishRestore();
  }

  // ── File restore ──────────────────────────────────────────────────────────

  Future<void> _fileRestore() async {
    PickedBackup? picked;
    try {
      picked = await LocalBackupService.instance.pickEncryptedFile();
    } on RestoreException catch (e) {
      if (mounted) _snack(e.message, error: true);
      return;
    }
    if (picked == null || !mounted) return;

    final pin = await BackupActions.promptPin(
      context,
      title: 'Enter Admin PIN',
      message: 'Enter the Admin PIN from your original CM Bank setup.',
    );
    if (pin == null || !mounted) return;

    _setLoading(true, 'Restoring your data...');
    try {
      await LocalBackupService.instance.restoreFromDevice(picked.bytes, pin);
    } on RestoreException catch (e) {
      _setLoading(false);
      if (mounted) {
        _snack(
          e.kind == RestoreErrorKind.wrongPin
              ? 'Incorrect PIN. Please try again.'
              : e.message,
          error: true,
        );
      }
      return;
    }
    _setLoading(false);
    if (!mounted) return;
    await _finishRestore();
  }

  // ── Post-restore ──────────────────────────────────────────────────────────

  Future<void> _finishRestore() async {
    await AppDatabase.instance.initialize();
    PhotoBackupService.instance.needsRestore = true;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore complete'),
        content:
            const Text('Your data has been restored successfully.'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const StartupGate()),
      (route) => false,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _setLoading(bool loading, [String message = '']) =>
      setState(() {
        _loading = loading;
        _loadingMessage = message;
      });

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? CMBColors.warningRed : CMBColors.navy,
      duration: const Duration(seconds: 5),
    ));
  }

  Future<DriveFile?> _pickBackup(List<DriveFile> files) {
    return showModalBottomSheet<DriveFile>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select a backup to restore',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (_, i) {
                  final f = files[i];
                  return ListTile(
                    leading:
                        const Icon(Icons.cloud_done, color: CMBColors.navy),
                    title: Text(_fmtTime(f.modifiedTime)),
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

  static String _fmtTime(DateTime? dt) {
    if (dt == null) return 'Unknown date';
    final t = dt.toLocal();
    String z(int v) => v.toString().padLeft(2, '0');
    return '${z(t.day)}/${z(t.month)}/${t.year}  ${z(t.hour)}:${z(t.minute)}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_showWizard) {
      return FirstLaunchWizard(onComplete: widget.onSetupComplete);
    }
    return Scaffold(
      backgroundColor: CMBColors.navy,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Image.asset(
                    AppBranding.logoAsset,
                    width: 140,
                    height: 140,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Restore your data or set up as new.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CMBColors.textOnNavySmall,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _driveRestore,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Restore from Google Drive'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CMBColors.goldRich,
                      foregroundColor: CMBColors.navy,
                      disabledBackgroundColor:
                          CMBColors.goldRich.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _fileRestore,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Restore from File (.enc)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CMBColors.textOnNavySmall,
                      side: const BorderSide(color: CMBColors.borderOnNavy),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() => _showWizard = true),
                    child: const Text(
                      'Start Fresh Setup →',
                      style: TextStyle(
                          color: CMBColors.textOnNavyMuted, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (_loading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 48),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                            color: CMBColors.navy),
                        const SizedBox(height: 16),
                        Text(
                          _loadingMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
