import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _authRepository = AuthRepository();

  bool _isChecking = true;
  bool _isAuthenticating = false;
  bool _canUseBiometrics = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  @override
  void dispose() {
    _pinController.dispose();
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
      if (mounted) {
        setState(() {
          _canUseBiometrics = false;
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _unlockWithPin() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _errorText = 'Enter your PIN.');
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
      setState(() => _errorText = 'Incorrect PIN.');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.account_balance,
                    color: CMBankTheme.primary,
                    size: 64,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'CM Bank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CMBankTheme.primary,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 34),
                  TextField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: const TextStyle(fontSize: 24),
                    decoration: InputDecoration(
                      labelText: 'Common PIN',
                      prefixIcon: const Icon(Icons.lock_outline),
                      errorText: _errorText,
                    ),
                    onSubmitted: (_) => _unlockWithPin(),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _isAuthenticating ? null : _unlockWithPin,
                    icon: _isAuthenticating
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login),
                    label: Text(_isAuthenticating ? 'UNLOCKING' : 'UNLOCK'),
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
                        foregroundColor: CMBankTheme.primary,
                        side: const BorderSide(
                          color: CMBankTheme.primary,
                          width: 1.5,
                        ),
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
