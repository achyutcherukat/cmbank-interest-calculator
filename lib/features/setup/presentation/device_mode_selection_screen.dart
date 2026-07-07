import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../core/settings/device_mode_service.dart';
import 'restore_or_setup_screen.dart';
import 'secondary_restore_screen.dart';

/// First screen on a fresh install: choose whether this device is the Primary
/// (data entry, backs up to Drive) or a Secondary (read-only, syncs from Drive).
///
///  - Primary  → the Restore-or-setup screen (restore a backup, or set up fresh).
///  - Secondary → mark device_mode='secondary', then the Secondary restore screen.
class DeviceModeSelectionScreen extends StatefulWidget {
  const DeviceModeSelectionScreen({super.key, required this.onSetupComplete});

  final VoidCallback onSetupComplete;

  @override
  State<DeviceModeSelectionScreen> createState() =>
      _DeviceModeSelectionScreenState();
}

class _DeviceModeSelectionScreenState extends State<DeviceModeSelectionScreen> {
  final _settings = AppSettingsRepository();
  bool _writingSecondary = false;

  Future<void> _selectPrimary() async {
    // Pin a clean Primary identity even if Secondary was tapped earlier in this
    // session (which would have persisted device_mode='secondary').
    try {
      await _settings.upsertMany({
        'device_mode': (value: 'primary', type: 'string'),
      });
      await DeviceModeService.instance.refresh();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RestoreOrSetupScreen(onSetupComplete: widget.onSetupComplete),
      ),
    );
  }

  /// Marks this install as a Secondary device (atomic write of both keys),
  /// refreshes the cached flag, then opens the Secondary restore screen.
  Future<void> _selectSecondary() async {
    setState(() => _writingSecondary = true);
    try {
      await _settings.upsertMany({
        'device_mode': (value: 'secondary', type: 'string'),
        'device_name': (value: 'Secondary Device', type: 'string'),
      });
      await DeviceModeService.instance.refresh();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SecondaryRestoreScreen()),
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'cm_bank_setup',
          context: ErrorDescription('while marking device as secondary'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Could not set up secondary device. Please try again.'),
            backgroundColor: CMBColors.warningRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _writingSecondary = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CMBColors.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Set Up This Device',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: CMBColors.goldRich,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'How will this device be used?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: CMBColors.textOnNavySmall,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 40),
                _modeCard(
                  icon: Icons.point_of_sale,
                  title: 'Primary Device',
                  subtitle:
                      'Enter loans, manage cash & stock, backs up to Drive.',
                  onTap: _writingSecondary ? null : _selectPrimary,
                ),
                const SizedBox(height: 20),
                _modeCard(
                  icon: Icons.visibility,
                  title: 'Secondary Device',
                  subtitle: 'View-only. Syncs data from Drive automatically.',
                  onTap: _writingSecondary ? null : _selectSecondary,
                ),
                if (_writingSecondary) ...[
                  const SizedBox(height: 28),
                  const CircularProgressIndicator(color: CMBColors.goldRich),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Card(
      color: CMBColors.goldRich,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 110),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(icon, size: 44, color: CMBColors.navy),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: CMBColors.navy,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: CMBColors.navy,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
