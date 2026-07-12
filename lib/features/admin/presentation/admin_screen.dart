import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../features/auth/data/auth_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../data/admin_repository.dart';
import 'admin_home_screen.dart';

// ─── Admin PIN Gate ───────────────────────────────────────────────────────────

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _pinCtrl = TextEditingController();
  final _authRepo = AuthRepository();
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Skip PIN if already authenticated within 30 minutes
    if (AdminSession.isValid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _proceed());
    }
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length != 6) {
      setState(() => _error = 'Enter your 6-digit admin PIN');
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    final valid = await _authRepo.verifyAdminPin(pin);
    if (!mounted) return;
    setState(() => _checking = false);

    if (valid) {
      AdminSession.authenticate();
      _proceed();
    } else {
      _pinCtrl.clear();
      setState(() => _error = 'Incorrect admin PIN. Try again.');
    }
  }

  void _proceed() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If already valid, show a brief loading state while redirecting
    if (AdminSession.isValid) {
      return const Scaffold(
        backgroundColor: FlowColors.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Admin',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28).withNavBarInset(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: FlowColors.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.admin_panel_settings,
                    color: FlowColors.primary, size: 44),
              ),
              const SizedBox(height: 24),
              const Text('Admin Authentication',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.primary)),
              const SizedBox(height: 8),
              const Text(
                'Enter your 6-digit admin PIN to continue',
                style: TextStyle(fontSize: 16, color: FlowColors.medText),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                autofocus: true,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(
                    fontSize: 28,
                    letterSpacing: 12,
                    fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: '••••••',
                  hintStyle: const TextStyle(
                      fontSize: 28,
                      letterSpacing: 12,
                      color: Colors.black26),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: FlowColors.primaryLight),
                  ),
                  errorText: _error,
                  errorStyle: const TextStyle(fontSize: 15),
                ),
                onSubmitted: (_) => _verify(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _checking ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlowColors.primary,
                    foregroundColor: FlowColors.textOnNavyLarge,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _checking
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: FlowColors.textOnNavyLarge, strokeWidth: 2.5))
                      : const Text('VERIFY PIN',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
