import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/settings/app_settings_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsRepository = AppSettingsRepository();
  final TextEditingController _rateController = TextEditingController();
  bool _saved = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadRate();
    _loadBiometric();
  }

  Future<void> _loadRate() async {
    final val = await _settingsRepository.getString('interest_rate') ??
        await _settingsRepository.getString('default_interest_rate');
    final rate = double.tryParse(val ?? '') ?? 18.0;
    setState(() {
      _rateController.text = rate.toStringAsFixed(2);
    });
  }

  Future<void> _loadBiometric() async {
    final enabled = await _settingsRepository.getBool('biometric_enabled');
    final auth = LocalAuthentication();
    final canCheck = await auth.canCheckBiometrics;
    final isSupported = await auth.isDeviceSupported();
    if (mounted) {
      setState(() {
        _biometricEnabled = enabled;
        _biometricAvailable = canCheck && isSupported;
      });
    }
  }

  Future<void> _saveBiometric(bool value) async {
    await _settingsRepository.upsertMany({
      'biometric_enabled': (value: value.toString(), type: 'bool'),
    });
    setState(() => _biometricEnabled = value);
  }

  Future<void> _saveRate() async {
    final text = _rateController.text.trim();
    final rate = double.tryParse(text);

    if (rate == null || rate <= 0 || rate > 100) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invalid Rate',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          content: const Text(
              'Please enter a valid interest rate between 0 and 100.',
              style: TextStyle(fontSize: 18)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK',
                  style: TextStyle(fontSize: 18, color: FlowColors.primary)),
            ),
          ],
        ),
      );
      return;
    }

    await _settingsRepository.upsertMany({
      'interest_rate': (value: rate.toStringAsFixed(2), type: 'string'),
    });

    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        title: const Text(
          'Settings',
          style: TextStyle(
              color: FlowColors.textOnNavyLarge, fontSize: 26, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: FlowColors.goldRich, size: 30),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20).withNavBarInset(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FlowColors.accent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: FlowColors.primaryLight, width: 1.5),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: FlowColors.primary, size: 26),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Default interest rate is 18% per annum. Change only if needed.',
                      style: TextStyle(fontSize: 17, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            const Text(
              'Interest Rate (% per annum)',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: FlowColors.primary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
              ],
              style: const TextStyle(fontSize: 24),
              decoration: const InputDecoration(
                suffixText: '%',
                suffixStyle: TextStyle(fontSize: 22, color: Colors.black87),
                hintText: '18.00',
                hintStyle: TextStyle(fontSize: 22, color: Colors.grey),
              ),
              onChanged: (_) => setState(() => _saved = false),
            ),

            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _saveRate,
              child: const Text('SAVE'),
            ),

            if (_saved) ...[
              const SizedBox(height: 20),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'Interest rate saved!',
                    style: TextStyle(
                        fontSize: 18,
                        color: Colors.green,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Security',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: FlowColors.primary),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: FlowColors.goldRich,
              title: const Text(
                'Fingerprint Login',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _biometricAvailable
                    ? 'Use fingerprint to unlock the app'
                    : 'Fingerprint not available on this device',
                style:
                    const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              value: _biometricEnabled,
              onChanged: _biometricAvailable ? _saveBiometric : null,
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }
}
