import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../app/theme.dart';

class FirstLaunchWizard extends StatefulWidget {
  const FirstLaunchWizard({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<FirstLaunchWizard> createState() => _FirstLaunchWizardState();
}

class _FirstLaunchWizardState extends State<FirstLaunchWizard> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController(text: 'CM Bank');
  final _commonPinController = TextEditingController();
  final _confirmCommonPinController = TextEditingController();
  final _adminPinController = TextEditingController();
  final _confirmAdminPinController = TextEditingController();
  final _interestRateController = TextEditingController(text: '18.00');
  final _pledgeRateController = TextEditingController(text: '0.00');
  final _startingPledgeNoController = TextEditingController(text: '3200');
  final _openingCashController = TextEditingController(text: '0');
  final _openingUpiController = TextEditingController(text: '0');
  final _openingStockWeightController = TextEditingController(text: '0');
  final _openingStockCountController = TextEditingController(text: '0');
  final _settingsRepository = AppSettingsRepository();

  bool _isSaving = false;
  bool _biometricEnabled = false;

  @override
  void dispose() {
    _businessNameController.dispose();
    _commonPinController.dispose();
    _confirmCommonPinController.dispose();
    _adminPinController.dispose();
    _confirmAdminPinController.dispose();
    _interestRateController.dispose();
    _pledgeRateController.dispose();
    _startingPledgeNoController.dispose();
    _openingCashController.dispose();
    _openingUpiController.dispose();
    _openingStockWeightController.dispose();
    _openingStockCountController.dispose();
    super.dispose();
  }

  Future<void> _saveSetup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final commonPinHash = PinHasher.hash(_commonPinController.text);
      final adminPinHash = PinHasher.hash(_adminPinController.text);
      final db = await AppDatabase.instance.database;

      await _settingsRepository.upsertMany({
        'business_name': (
          value: _businessNameController.text.trim(),
          type: 'string',
        ),
        'common_pin_hash': (value: commonPinHash, type: 'string'),
        'admin_pin_hash': (value: adminPinHash, type: 'string'),
        'default_interest_rate': (
          value: _interestRateController.text.trim(),
          type: 'double',
        ),
        'default_pledge_rate': (
          value: _pledgeRateController.text.trim(),
          type: 'double',
        ),
        'starting_pledge_number': (
          value: _startingPledgeNoController.text.trim(),
          type: 'int',
        ),
        'opening_cash': (
          value: _openingCashController.text.trim(),
          type: 'double',
        ),
        'opening_upi': (
          value: _openingUpiController.text.trim(),
          type: 'double',
        ),
        'opening_stock_weight': (
          value: _openingStockWeightController.text.trim(),
          type: 'double',
        ),
        'opening_stock_count': (
          value: _openingStockCountController.text.trim(),
          type: 'int',
        ),
        'first_launch_completed': (value: 'true', type: 'bool'),
        'biometric_enabled': (
          value: _biometricEnabled.toString(),
          type: 'bool',
        ),
      });

      await db.update(
        'users',
        {
          'pin_hash': adminPinHash,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'role = ?',
        whereArgs: ['admin'],
      );

      if (mounted) widget.onComplete();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'cm_bank_setup',
          context: ErrorDescription('while saving first launch settings'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setup could not be saved. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: CMBColors.navy,
        title: const Text(
          'First Setup',
          style: TextStyle(
            color: CMBColors.textOnNavyLarge,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _sectionTitle('Business'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _businessNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Business Name',
                  prefixIcon: Icon(Icons.storefront),
                ),
                validator: _required,
              ),
              const SizedBox(height: 24),
              _sectionTitle('Login PINs'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _commonPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [_pinFormatter, _pinLengthFormatter],
                decoration: const InputDecoration(
                  labelText: 'Common Staff PIN',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: _validatePin,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmCommonPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [_pinFormatter, _pinLengthFormatter],
                decoration: const InputDecoration(
                  labelText: 'Confirm Staff PIN',
                  prefixIcon: Icon(Icons.lock_reset),
                ),
                validator: (value) => _validatePinMatch(
                  value,
                  _commonPinController.text,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _adminPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [_pinFormatter, _pinLengthFormatter],
                decoration: const InputDecoration(
                  labelText: 'Admin PIN',
                  prefixIcon: Icon(Icons.admin_panel_settings),
                ),
                validator: _validatePin,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmAdminPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [_pinFormatter, _pinLengthFormatter],
                decoration: const InputDecoration(
                  labelText: 'Confirm Admin PIN',
                  prefixIcon: Icon(Icons.verified_user),
                ),
                validator: (value) => _validatePinMatch(
                  value,
                  _adminPinController.text,
                ),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: CMBColors.goldRich,
                title: const Text(
                  'Enable fingerprint login',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                value: _biometricEnabled,
                onChanged: (value) {
                  setState(() => _biometricEnabled = value);
                },
              ),
              const SizedBox(height: 24),
              _sectionTitle('Defaults'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _interestRateController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                inputFormatters: [_decimalFormatter],
                decoration: const InputDecoration(
                  labelText: 'Interest Rate (% p.a.)',
                  prefixIcon: Icon(Icons.percent),
                ),
                validator: _validatePositiveDecimal,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _pledgeRateController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_decimalFormatter],
                decoration: const InputDecoration(
                  labelText: 'Pledge Rate (₹ per gram)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                validator: _validateNonNegativeDecimal,
              ),
              const SizedBox(height: 24),
              _sectionTitle('Starting Pledge Number'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _startingPledgeNoController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'First Pledge Number',
                  prefixIcon: Icon(Icons.tag),
                  helperText: 'New pledges will be numbered from here',
                ),
                validator: (value) {
                  final n = int.tryParse(value?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid pledge number.';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              _sectionTitle('Opening Balances'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _openingCashController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_decimalFormatter],
                decoration: const InputDecoration(
                  labelText: 'Opening Cash Balance (₹)',
                  prefixIcon: Icon(Icons.money),
                ),
                validator: _validateNonNegativeDecimal,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _openingUpiController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_decimalFormatter],
                decoration: const InputDecoration(
                  labelText: 'Opening UPI Balance (₹)',
                  prefixIcon: Icon(Icons.phone_android),
                ),
                validator: _validateNonNegativeDecimal,
              ),
              const SizedBox(height: 24),
              _sectionTitle('Opening Gold Stock'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _openingStockWeightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_decimalFormatter],
                decoration: const InputDecoration(
                  labelText: 'Opening Stock Weight (grams)',
                  prefixIcon: Icon(Icons.balance),
                  helperText: 'Total gold weight you currently hold',
                ),
                validator: _validateNonNegativeDecimal,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _openingStockCountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Opening Item Count',
                  prefixIcon: Icon(Icons.format_list_numbered),
                  helperText: 'Number of gold items you currently hold',
                ),
                validator: (value) {
                  final n = int.tryParse(value?.trim() ?? '');
                  if (n == null || n < 0) return 'Enter a valid item count.';
                  return null;
                },
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveSetup,
                icon: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: CMBColors.textOnNavyLarge,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_isSaving ? 'SAVING' : 'COMPLETE SETUP'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: CMBColors.navy,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  String? _validatePin(String? value) {
    final pin = value?.trim() ?? '';
    if (pin.length != 6) return 'PIN must be exactly 6 digits.';
    return null;
  }

  String? _validatePinMatch(String? value, String original) {
    final pinError = _validatePin(value);
    if (pinError != null) return pinError;
    if (value?.trim() != original.trim()) {
      return 'PINs do not match.';
    }
    return null;
  }

  String? _validatePositiveDecimal(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed <= 0 || parsed > 100) {
      return 'Enter a valid value between 0 and 100.';
    }
    return null;
  }

  String? _validateNonNegativeDecimal(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) {
      return 'Enter a valid value.';
    }
    return null;
  }

  static final _pinFormatter = FilteringTextInputFormatter.digitsOnly;
  static final _pinLengthFormatter = LengthLimitingTextInputFormatter(6);
  static final _decimalFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'^\d+\.?\d{0,2}'),
  );
}
