import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_branding.dart';
import '../../../app/theme.dart';
import '../data/auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pinController = TextEditingController();
  final _adminPinController = TextEditingController();
  final _authRepository = AuthRepository();

  bool _isChecking = true;
  bool _isAuthenticating = false;
  bool _canUseBiometrics = false;
  bool _useAdminPin = false;
  String? _errorText;

  static final _inputFormatters = [
    FilteringTextInputFormatter.digitsOnly,
  ];

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _adminPinController.dispose();
    super.dispose();
  }

  Future<void> _loadBiometricState() async {
    try {
      final available = await _authRepository.isBiometricLoginAvailable();
      if (mounted) {
        setState(() {
          _canUseBiometrics = available;
          _isChecking = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _unlockWithPin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _errorText = 'Enter your 6-digit PIN.');
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorText = null;
    });

    final valid = await _authRepository.verifyCommonPin(pin);
    if (!mounted) return;
    setState(() => _isAuthenticating = false);

    if (valid) {
      widget.onAuthenticated();
    } else {
      _pinController.clear();
      setState(() => _errorText = 'Incorrect PIN. Try admin PIN if needed.');
    }
  }

  Future<void> _unlockWithAdminPin() async {
    final pin = _adminPinController.text.trim();
    if (pin.length != 6) {
      setState(() => _errorText = 'Enter your 6-digit admin PIN.');
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorText = null;
    });

    final valid = await _authRepository.verifyAdminPin(pin);
    if (!mounted) return;
    setState(() => _isAuthenticating = false);

    if (valid) {
      widget.onAuthenticated();
    } else {
      _adminPinController.clear();
      setState(() => _errorText = 'Incorrect admin PIN.');
    }
  }

  Future<void> _unlockWithBiometrics() async {
    setState(() {
      _isAuthenticating = true;
      _errorText = null;
    });

    try {
      final valid = await _authRepository.authenticateWithBiometrics();
      if (!mounted) return;
      if (valid) {
        widget.onAuthenticated();
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = 'Fingerprint unlock is not available.');
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  void _toggleAdminPin() {
    setState(() {
      _useAdminPin = !_useAdminPin;
      _errorText = null;
      _pinController.clear();
      _adminPinController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CMBColors.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    AppBranding.logoAsset,
                    width: 196,
                    height: 196,
                  ),
                  const SizedBox(height: 40),

                  if (!_useAdminPin) ...[
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        ..._inputFormatters,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      style: const TextStyle(fontSize: 24),
                      decoration: InputDecoration(
                        labelText: 'PIN (6 digits)',
                        prefixIcon: const Icon(Icons.lock_outline),
                        errorText: _errorText,
                      ),
                      onSubmitted: (_) => _unlockWithPin(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _isAuthenticating ? null : _unlockWithPin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CMBColors.goldRich,
                        foregroundColor: CMBColors.navy,
                      ),
                      icon: _isAuthenticating
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: CMBColors.navy,
                              ),
                            )
                          : const Icon(Icons.login),
                      label: Text(_isAuthenticating ? 'UNLOCKING…' : 'UNLOCK'),
                    ),
                    if (_canUseBiometrics) ...[
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _isChecking || _isAuthenticating
                            ? null
                            : _unlockWithBiometrics,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('USE FINGERPRINT'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                          foregroundColor: CMBColors.goldRich,
                          side: const BorderSide(
                            color: CMBColors.goldRich,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: _toggleAdminPin,
                      child: const Text(
                        'Forgot PIN? Use Admin PIN',
                        style: TextStyle(fontSize: 17, color: CMBColors.goldLight),
                      ),
                    ),
                  ] else ...[
                    // Admin PIN mode
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: CMBColors.goldRich),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.admin_panel_settings,
                              color: CMBColors.goldRich, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Enter the Admin PIN to unlock.',
                              style: TextStyle(fontSize: 17, color: CMBColors.goldLight),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextField(
                      controller: _adminPinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        ..._inputFormatters,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      style: const TextStyle(fontSize: 24),
                      decoration: InputDecoration(
                        labelText: 'Admin PIN (6 digits)',
                        prefixIcon:
                            const Icon(Icons.admin_panel_settings),
                        errorText: _errorText,
                      ),
                      onSubmitted: (_) => _unlockWithAdminPin(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed:
                          _isAuthenticating ? null : _unlockWithAdminPin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CMBColors.goldRich,
                        foregroundColor: CMBColors.navy,
                      ),
                      icon: _isAuthenticating
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: CMBColors.navy,
                              ),
                            )
                          : const Icon(Icons.login),
                      label: Text(
                          _isAuthenticating ? 'UNLOCKING…' : 'UNLOCK WITH ADMIN PIN'),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: _toggleAdminPin,
                      child: const Text(
                        '← Back to PIN',
                        style: TextStyle(fontSize: 17, color: CMBColors.goldLight),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
