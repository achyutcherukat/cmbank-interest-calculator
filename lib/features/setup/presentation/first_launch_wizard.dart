import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../gold_stock/data/gold_rates_repository.dart';

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
  final _startingPledgeNoController = TextEditingController();
  final _openingCashController = TextEditingController(text: '0');
  final _openingUpiController = TextEditingController(text: '0');
  final _openingGoldAccountController = TextEditingController(text: '0');
  final _openingGrossWeightController = TextEditingController(text: '0');
  final _openingNetWeightController = TextEditingController(text: '0');
  final _settingsRepository = AppSettingsRepository();

  // The date from which this install begins tracking cash/stock. Migrated
  // pledges must pre-date this value; Cash Book and Stock Register navigate
  // no earlier than this date.
  DateTime _appStartDate = DateTime.now();

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
    _openingGoldAccountController.dispose();
    _openingGrossWeightController.dispose();
    _openingNetWeightController.dispose();
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
        'interest_rate': (
          value: _interestRateController.text.trim(),
          type: 'string',
        ),
        'starting_pledge_number': (
          value: _startingPledgeNoController.text.trim(),
          type: 'int',
        ),
        'opening_cash': (
          value: _openingCashController.text.trim().replaceAll(',', ''),
          type: 'string',
        ),
        'opening_upi': (
          value: _openingUpiController.text.trim().replaceAll(',', ''),
          type: 'string',
        ),
        'opening_gold_account_balance': (
          value: _openingGoldAccountController.text.trim().replaceAll(',', ''),
          type: 'int',
        ),
        'app_use_start_date': (
          value: _appStartDate.toIso8601String().substring(0, 10),
          type: 'string',
        ),
        'opening_gold_account_balance_date': (
          value: _appStartDate.toIso8601String().substring(0, 10),
          type: 'string',
        ),
        'opening_stock_gross_weight': (
          value: _openingGrossWeightController.text.trim(),
          type: 'string',
        ),
        'opening_stock_net_weight': (
          value: _openingNetWeightController.text.trim(),
          type: 'string',
        ),
        'device_setup_complete': (value: 'true', type: 'bool'),
        'biometric_enabled': (
          value: _biometricEnabled.toString(),
          type: 'bool',
        ),
      });

      // Seed the initial pledge rate into the gold_rates table.
      final pledgeRate =
          double.tryParse(_pledgeRateController.text.trim()) ?? 0;
      await GoldRatesRepository.instance.saveRates(pledgeRate: pledgeRate);

      await db.update(
        'users',
        {
          'pin_hash': adminPinHash,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'role = ?',
        whereArgs: ['admin'],
      );

      // Generate the AES-256 backup encryption key (Part 2 — on first launch).
      try {
        await EncryptionService.instance
            .ensureKeyInitialized(_adminPinController.text.trim());
      } catch (_) {
        // Non-fatal — the key can be created later from backup settings.
      }

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
                keyboardType: TextInputType.number,
                inputFormatters: [IndianNumberFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Opening Cash Balance (₹)',
                  prefixIcon: Icon(Icons.money),
                ),
                validator: (value) {
                  final n = int.tryParse(
                      (value ?? '').replaceAll(',', '').trim());
                  if (n == null || n < 0) return 'Enter a valid amount.';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _openingUpiController,
                keyboardType: TextInputType.number,
                inputFormatters: [IndianNumberFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Opening UPI Balance (₹)',
                  prefixIcon: Icon(Icons.phone_android),
                ),
                validator: (value) {
                  final n = int.tryParse(
                      (value ?? '').replaceAll(',', '').trim());
                  if (n == null || n < 0) return 'Enter a valid amount.';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _openingGoldAccountController,
                keyboardType: TextInputType.number,
                inputFormatters: [IndianNumberFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Gold Account Balance (₹)',
                  prefixIcon: Icon(Icons.account_balance),
                  helperText: 'Opening balance of the gold loan account',
                ),
                validator: (value) {
                  final n =
                      int.tryParse((value ?? '').trim().replaceAll(',', ''));
                  if (n == null || n < 0) {
                    return 'Enter a valid amount.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              _sectionTitle('Opening Gold Stock'),
              const SizedBox(height: 10),
              // App start date — the canonical boundary for Cash Book / Stock
              // Register navigation and Add Existing Loan date restrictions.
              _DatePickerTile(
                label: 'App Start Date',
                helperText:
                    'Date from which this app begins tracking daily cash and gold stock. '
                    'Add Existing Loan entries must be dated before this date.',
                selectedDate: _appStartDate,
                onChanged: (dt) => setState(() => _appStartDate = dt),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _openingGrossWeightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_decimalFormatter],
                decoration: const InputDecoration(
                  labelText: 'Opening Gross Weight (grams)',
                  prefixIcon: Icon(Icons.balance),
                  helperText: 'Total gross weight of gold you currently hold',
                ),
                validator: _validateNonNegativeDecimal,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _openingNetWeightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_decimalFormatter],
                decoration: const InputDecoration(
                  labelText: 'Opening Net Weight (grams)',
                  prefixIcon: Icon(Icons.scale),
                  helperText: 'Total net weight of gold you currently hold',
                ),
                validator: _validateNonNegativeDecimal,
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

// ─── Date picker row used for the App Start Date field ────────────────────────

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({
    required this.label,
    required this.selectedDate,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final String? helperText;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.event),
            border: const OutlineInputBorder(),
            suffixIcon: TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (picked != null) onChanged(picked);
              },
              child: const Text('CHANGE'),
            ),
          ),
          child: Text(
            _fmt(selectedDate),
            style: const TextStyle(fontSize: 16),
          ),
        ),
        if (helperText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 0, 0),
            child: Text(
              helperText!,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
      ],
    );
  }
}
