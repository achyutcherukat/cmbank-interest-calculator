import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../backup/presentation/backup_actions.dart';

/// Secondary-device first restore. Reuses the existing Settings → Backup →
/// Restore flow as-is: on success it re-pins the device as Secondary and reloads
/// the app via StartupGate (the restored database carries device_setup_complete
/// = true and the Primary's PINs, so the app proceeds to login then Home). On
/// failure the flow shows an error and returns here, leaving the button for a
/// retry.
class SecondaryRestoreScreen extends StatelessWidget {
  const SecondaryRestoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CMBColors.navy,
      appBar: AppBar(
        backgroundColor: CMBColors.navy,
        iconTheme: const IconThemeData(color: CMBColors.goldRich),
        title: const Text(
          'Secondary Device',
          style: TextStyle(
            color: CMBColors.textOnNavyLarge,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            const Icon(
              Icons.cloud_download_outlined,
              size: 72,
              color: CMBColors.goldRich,
            ),
            const SizedBox(height: 24),
            const Text(
              'Restore your data from Google Drive',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CMBColors.textOnNavyLarge,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'This device will load all loans, cash and stock from the latest '
              'Drive backup. Sign in with the same Google account used on the '
              'Primary device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CMBColors.textOnNavySmall,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 36),
            ElevatedButton.icon(
              onPressed: () => BackupActions.restoreFromDrive(context),
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('RESTORE FROM DRIVE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CMBColors.goldRich,
                foregroundColor: CMBColors.navy,
                minimumSize: const Size(double.infinity, 60),
                textStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'If a restore fails, tap Restore from Drive again to retry.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CMBColors.textOnNavyMuted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
