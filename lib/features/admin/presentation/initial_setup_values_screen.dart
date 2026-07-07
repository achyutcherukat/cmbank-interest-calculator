import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../accounts/data/daily_balance_repository.dart';
import '../data/admin_repository.dart';
import '../data/audit_log_repository.dart';

class InitialSetupValuesScreen extends StatefulWidget {
  const InitialSetupValuesScreen({super.key});

  @override
  State<InitialSetupValuesScreen> createState() =>
      _InitialSetupValuesScreenState();
}

class _InitialSetupValuesScreenState extends State<InitialSetupValuesScreen> {
  final _settings = AppSettingsRepository();

  String? _openingCash;
  String? _openingUpi;
  String? _openingGrossWeight;
  String? _openingNetWeight;
  String? _openingGoldBalance;
  String? _appUseStartDate;
  bool _goldLocked = false;
  bool _bankLocked = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (!AdminSession.isValid && mounted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => Navigator.pop(context));
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _settings.getString('opening_cash'),
        _settings.getString('opening_upi'),
        _settings.getString('opening_stock_gross_weight'),
        _settings.getString('opening_stock_net_weight'),
        _settings.getString('opening_gold_account_balance'),
        _settings.getString('app_use_start_date'),
        _settings.getBool('opening_gold_account_balance_locked'),
        _settings.getBool('opening_bank_upi_balance_locked'),
      ]);
      if (mounted) {
        setState(() {
          _openingCash = results[0] as String?;
          _openingUpi = results[1] as String?;
          _openingGrossWeight = results[2] as String?;
          _openingNetWeight = results[3] as String?;
          _openingGoldBalance = results[4] as String?;
          _appUseStartDate = results[5] as String?;
          _goldLocked = results[6] as bool;
          _bankLocked = results[7] as bool;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtMoney(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final n = double.tryParse(raw.replaceAll(',', ''));
    if (n == null) return '—';
    return money(n);
  }

  String _fmtMoneyDecimal(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final n = double.tryParse(raw.replaceAll(',', ''));
    if (n == null) return '—';
    return moneyWithPaise(n);
  }

  String _fmtWeight(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final n = double.tryParse(raw);
    if (n == null) return '—';
    return '${n.toStringAsFixed(2)} g';
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? FlowColors.red : FlowColors.green,
    ));
  }

  // ── Edit flow ─────────────────────────────────────────────────────────────────

  void _showEditDialog() {
    final currentRaw = (_openingGoldBalance ?? '0').replaceAll(',', '');
    final formatted = () {
      final n = int.tryParse(currentRaw);
      if (n == null) return currentRaw;
      return _applyIndianFormat(n.toString());
    }();
    final ctrl = TextEditingController(text: formatted);
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) => AlertDialog(
          title: const Text(
            'Edit Opening Gold Account Balance',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FlowNoticeBox(
                icon: Icons.warning_amber_rounded,
                color: FlowColors.orange,
                backgroundColor: FlowColors.orangeLight,
                text:
                    'You can correct this value only once. After saving it will be permanently locked.',
              ),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [IndianNumberFormatter()],
                autofocus: true,
                style: const TextStyle(fontSize: 22),
                decoration: InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixText: '₹ ',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: const Text('Cancel',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.primary),
              onPressed: () {
                final raw =
                    ctrl.text.trim().replaceAll(',', '');
                final n = int.tryParse(raw);
                if (n == null || n < 0) {
                  setDlg(() => error = 'Enter a valid amount');
                  return;
                }
                Navigator.pop(ctx2);
                _showConfirmDialog(raw);
              },
              child: const Text('Save',
                  style: TextStyle(
                      fontSize: 16, color: FlowColors.textOnNavySmall)),
            ),
          ],
        ),
      ),
    );
  }

  void _showConfirmDialog(String newRaw) {
    final displayAmt = money(int.parse(newRaw));
    final oldRaw =
        (_openingGoldBalance ?? '0').replaceAll(',', '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Confirm One-Time Correction',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: FlowColors.primary),
        ),
        content: FlowNoticeBox(
          icon: Icons.lock_outline,
          color: FlowColors.orange,
          backgroundColor: FlowColors.orangeLight,
          text:
              'This value can only be corrected ONCE. After saving, it cannot be changed again through this screen. Please confirm the amount is correct: $displayAmt',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary),
            onPressed: () {
              Navigator.pop(ctx);
              _saveGoldBalance(oldRaw, newRaw);
            },
            child: const Text('CONFIRM',
                style: TextStyle(
                    fontSize: 16, color: FlowColors.textOnNavySmall)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveGoldBalance(String oldRaw, String newRaw) async {
    setState(() => _saving = true);
    try {
      await _settings.upsertMany({
        'opening_gold_account_balance': (value: newRaw, type: 'int'),
        'opening_gold_account_balance_locked': (value: 'true', type: 'bool'),
      });
      await AuditLogRepository.instance.log(
        actionCategory: 'SETTINGS',
        action: 'GOLD_ACCOUNT_BALANCE_CORRECTED',
        entityType: 'settings',
        oldValueJson: oldRaw,
        newValueJson: newRaw,
      );
      if (mounted) {
        setState(() {
          _openingGoldBalance = newRaw;
          _goldLocked = true;
          _saving = false;
        });
        _snack('Opening gold account balance updated');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Failed to save. Please try again.', error: true);
      }
    }
  }

  // ── Bank / UPI balance edit flow ─────────────────────────────────────────────

  void _showBankEditDialog() {
    final currentRaw = (_openingUpi ?? '0').replaceAll(',', '');
    final preText =
        double.tryParse(currentRaw)?.toStringAsFixed(2) ?? '0.00';
    final ctrl = TextEditingController(text: preText);
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) => AlertDialog(
          title: const Text(
            'Edit Opening Bank / UPI Balance',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FlowNoticeBox(
                icon: Icons.warning_amber_rounded,
                color: FlowColors.orange,
                backgroundColor: FlowColors.orangeLight,
                text:
                    'You can correct this value only once. After saving it will be permanently locked.',
              ),
              TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [IndianDecimalFormatter()],
                autofocus: true,
                style: const TextStyle(fontSize: 22),
                decoration: InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixText: '₹ ',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: const Text('Cancel',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.primary),
              onPressed: () {
                final raw = ctrl.text.trim().replaceAll(',', '');
                final val = double.tryParse(raw);
                if (val == null || val < 0) {
                  setDlg(() => error = 'Enter a valid amount');
                  return;
                }
                Navigator.pop(ctx2);
                _showBankConfirmDialog(val.toStringAsFixed(2));
              },
              child: const Text('Save',
                  style: TextStyle(
                      fontSize: 16, color: FlowColors.textOnNavySmall)),
            ),
          ],
        ),
      ),
    );
  }

  void _showBankConfirmDialog(String newRaw) {
    final displayAmt = moneyWithPaise(double.parse(newRaw));
    final oldRaw = (_openingUpi ?? '0').replaceAll(',', '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Confirm One-Time Correction',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: FlowColors.primary),
        ),
        content: FlowNoticeBox(
          icon: Icons.lock_outline,
          color: FlowColors.orange,
          backgroundColor: FlowColors.orangeLight,
          text:
              'This value can only be corrected ONCE. After saving, it cannot be changed again through this screen. Please confirm the amount is correct: $displayAmt',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary),
            onPressed: () {
              Navigator.pop(ctx);
              _saveBankBalance(oldRaw, newRaw);
            },
            child: const Text('CONFIRM',
                style: TextStyle(
                    fontSize: 16, color: FlowColors.textOnNavySmall)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveBankBalance(String oldRaw, String newRaw) async {
    setState(() => _saving = true);
    try {
      await _settings.upsertMany({
        'opening_upi': (value: newRaw, type: 'string'),
        'opening_bank_upi_balance_locked': (value: 'true', type: 'bool'),
      });

      // Sync the default bank account's opening_balance to match.
      final db = await AppDatabase.instance.database;
      final newVal = double.tryParse(newRaw) ?? 0.0;
      await db.update(
        'bank_accounts',
        {
          'opening_balance': newVal,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'is_default = 1 AND is_active = 1',
      );

      // Re-cascade daily balances from app start date so unlocked days
      // pick up the corrected opening balance.
      if (_appUseStartDate != null) {
        await DailyBalanceRepository.instance.cascadeFrom(_appUseStartDate!);
      }

      await AuditLogRepository.instance.log(
        actionCategory: 'SETTINGS',
        action: 'BANK_UPI_BALANCE_CORRECTED',
        entityType: 'settings',
        oldValueJson: oldRaw,
        newValueJson: newRaw,
      );
      if (mounted) {
        setState(() {
          _openingUpi = newRaw;
          _bankLocked = true;
          _saving = false;
        });
        _snack('Opening bank/UPI balance updated');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Failed to save. Please try again.', error: true);
      }
    }
  }

  static String _applyIndianFormat(String digits) {
    if (digits.length <= 3) return digits;
    final last3 = digits.substring(digits.length - 3);
    final rest = digits.substring(0, digits.length - 3);
    final buf = StringBuffer();
    final start = rest.length % 2;
    if (start > 0) buf.write(rest.substring(0, start));
    for (var i = start; i < rest.length; i += 2) {
      if (buf.isNotEmpty) buf.write(',');
      buf.write(rest.substring(i, i + 2));
    }
    return '$buf,$last3';
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text(
          'Initial Setup Values',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  children: [
                    _balancesCard(),
                    const SizedBox(height: 14),
                    _goldStockCard(),
                  ],
                ),
                if (_saving)
                  const ColoredBox(
                    color: Colors.black26,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }

  Widget _balancesCard() {
    return FlowCard(
      header: 'OPENING BALANCES',
      child: Column(
        children: [
          DetailRow(
            label: 'Opening Cash',
            value: _fmtMoney(_openingCash),
          ),
          _bankUpiBalanceRow(),
          _goldBalanceRow(),
          DetailRow(
            label: 'App Use Start Date',
            value: isoToDisplay(_appUseStartDate),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _bankUpiBalanceRow() {
    if (_bankLocked) {
      return DetailRow(
        label: 'Opening Bank / UPI Balance',
        value: _fmtMoneyDecimal(_openingUpi),
      );
    }

    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Flexible(
            child: Text(
              'Opening Bank / UPI Balance',
              style: TextStyle(fontSize: 17, color: FlowColors.medText),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmtMoneyDecimal(_openingUpi),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit,
                    size: 20, color: FlowColors.primary),
                tooltip: 'Edit (one-time correction)',
                onPressed: _showBankEditDialog,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _goldBalanceRow() {
    if (_goldLocked) {
      return DetailRow(
        label: 'Opening Gold Account Balance',
        value: _fmtMoney(_openingGoldBalance),
      );
    }

    // Editable — show value + edit button
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Flexible(
            child: Text(
              'Opening Gold Account Balance',
              style: TextStyle(fontSize: 17, color: FlowColors.medText),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmtMoney(_openingGoldBalance),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit,
                    size: 20, color: FlowColors.primary),
                tooltip: 'Edit (one-time correction)',
                onPressed: _showEditDialog,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _goldStockCard() {
    return FlowCard(
      header: 'OPENING GOLD STOCK',
      child: Column(
        children: [
          DetailRow(
            label: 'Opening Gross Weight',
            value: _fmtWeight(_openingGrossWeight),
          ),
          DetailRow(
            label: 'Opening Net Weight',
            value: _fmtWeight(_openingNetWeight),
            isLast: true,
          ),
        ],
      ),
    );
  }
}
