import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/settings/app_settings_repository.dart';
import 'backup_actions.dart';

/// Full-screen, non-dismissable error shown when `PRAGMA integrity_check` fails
/// on launch (Part 7). The database is NOT auto-wiped; the only way forward is
/// to restore from a backup.
class DatabaseErrorScreen extends StatefulWidget {
  const DatabaseErrorScreen({super.key});

  @override
  State<DatabaseErrorScreen> createState() => _DatabaseErrorScreenState();
}

class _DatabaseErrorScreenState extends State<DatabaseErrorScreen> {
  String _lastDrive = 'Never';
  String _lastLocal = 'Never';
  String _atRisk = 'Unknown';

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    // Best-effort — the database may be unreadable.
    try {
      final settings = AppSettingsRepository();
      final drive = await settings.getString('last_drive_backup');
      final local = await settings.getString('last_local_backup');
      final driveDt = (drive != null && drive.isNotEmpty)
          ? DateTime.tryParse(drive)
          : null;
      final localDt = (local != null && local.isNotEmpty)
          ? DateTime.tryParse(local)
          : null;
      final mostRecent = [driveDt, localDt]
          .whereType<DateTime>()
          .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      if (mounted) {
        setState(() {
          _lastDrive = _fmt(driveDt);
          _lastLocal = _fmt(localDt);
          _atRisk = _risk(mostRecent);
        });
      }
    } catch (_) {
      // Leave defaults.
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return 'Never';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  String _risk(DateTime? since) {
    if (since == null) return 'Unknown (no backups found)';
    final d = DateTime.now().difference(since);
    if (d.inDays > 0) return '${d.inDays} day(s) of data';
    if (d.inHours > 0) return '${d.inHours} hour(s) of data';
    return '${d.inMinutes} minute(s) of data';
  }

  @override
  Widget build(BuildContext context) {
    // Block back navigation — the user must restore.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: CMBColors.navy,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.error_outline,
                      color: CMBColors.warningRed, size: 64),
                  const SizedBox(height: 18),
                  const Text(
                    'Database Error',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: CMBColors.goldRich),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'The app database has been corrupted and cannot be opened. '
                    'Please restore from a backup to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  _infoRow('Last Drive backup', _lastDrive),
                  _infoRow('Last local backup', _lastLocal),
                  _infoRow('Estimated data at risk', _atRisk),
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CMBColors.goldRich,
                      foregroundColor: CMBColors.navy,
                    ),
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('RESTORE FROM DRIVE'),
                    onPressed: () => BackupActions.restoreFromDrive(context),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CMBColors.goldRich,
                      side: const BorderSide(color: CMBColors.goldRich),
                      minimumSize: const Size(double.infinity, 56),
                    ),
                    icon: const Icon(Icons.sd_storage),
                    label: const Text('RESTORE FROM DEVICE'),
                    onPressed: () => BackupActions.restoreFromDevice(context),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _contactSupport,
                    child: const Text('CONTACT SUPPORT',
                        style: TextStyle(color: Colors.white60)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _contactSupport() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Contact Support'),
        content: const Text(
          'Please contact your software provider with this message and the '
          'date of your last backup. Do not uninstall the app — your local '
          'backup in Downloads/CMBank may still be recoverable.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 14)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
