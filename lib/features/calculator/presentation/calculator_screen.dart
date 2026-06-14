import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/settings/app_settings_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../pledges/data/pledge_repository.dart';
import '../data/calc_history_repository.dart';
import '../data/interest_calculator.dart';
import 'history_screen.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _principalController = TextEditingController();
  final _fromDateController = TextEditingController();
  final _toDateController = TextEditingController();
  final _settingsRepository = AppSettingsRepository();

  DateTime? _fromDate;
  DateTime? _toDate;
  int? _numberOfDays;

  double _simpleInterest = 0.0;
  double _totalAmount = 0.0;
  bool _hasResult = false;
  String _minimumChargeNote = '';
  double _interestRate = 18.0;

  @override
  void initState() {
    super.initState();
    _loadInterestRate();
    _toDate = DateTime.now();
    _toDateController.text = _formatDate(_toDate!);
    CalcHistoryRepository.instance.migrateFromSharedPreferences();
  }

  @override
  void dispose() {
    _principalController.dispose();
    _fromDateController.dispose();
    _toDateController.dispose();
    super.dispose();
  }

  Future<void> _loadInterestRate() async {
    final val = await _settingsRepository.getString('default_interest_rate');
    if (mounted) {
      setState(() => _interestRate = double.tryParse(val ?? '') ?? 18.0);
    }
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  DateTime? _parseDate(String text) {
    try {
      final parts = text.split('/');
      if (parts.length == 3) {
        return DateTime(
            int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      }
    } catch (_) {}
    return null;
  }

  void _updateDays() {
    if (_fromDate != null && _toDate != null) {
      final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      final to = DateTime(_toDate!.year, _toDate!.month, _toDate!.day);
      setState(() => _numberOfDays = to.difference(from).inDays);
    } else {
      setState(() => _numberOfDays = null);
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final initial =
        isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: FlowColors.primary,
            onPrimary: Colors.white,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
          _fromDateController.text = _formatDate(picked);
        } else {
          _toDate = picked;
          _toDateController.text = _formatDate(picked);
        }
        _hasResult = false;
        _minimumChargeNote = '';
      });
      _updateDays();
    }
  }

  void _onDateTyped(String value, bool isFrom) {
    final parsed = _parseDate(value);
    if (parsed != null) {
      if (isFrom) {
        _fromDate = parsed;
      } else {
        _toDate = parsed;
      }
      _updateDays();
    }
    setState(() {
      _hasResult = false;
      _minimumChargeNote = '';
    });
  }

  Future<void> _calculate() async {
    final principal = double.tryParse(_principalController.text.trim());
    if (principal == null || principal <= 0) {
      _showError('Please enter a valid principal amount.');
      return;
    }
    if (_fromDate == null) {
      _showError('Please select the From Date.');
      return;
    }
    if (_toDate == null) {
      _showError('Please select the To Date.');
      return;
    }
    if (_numberOfDays == null || _numberOfDays! <= 0) {
      _showError('To Date must be after From Date.');
      return;
    }

    await _loadInterestRate();

    final result = InterestCalculator.calculate(
      principal: principal,
      fromDate: _fromDate!,
      toDate: _toDate!,
      ratePercent: _interestRate,
    );

    setState(() {
      _simpleInterest = result.interest;
      _totalAmount = result.total;
      _minimumChargeNote = result.note;
      _hasResult = true;
    });
  }

  // ─── Close Pledge Dialog ──────────────────────────────────────────────────

  void _showClosePledgeDialog() {
    final pledgeNoCtrl = TextEditingController();
    String? selectedMode;
    String? dialogError;
    bool isSaving = false;

    final principal = double.tryParse(_principalController.text.trim()) ?? 0;
    final fromISO =
        '${_fromDate!.year.toString().padLeft(4, '0')}-${_fromDate!.month.toString().padLeft(2, '0')}-${_fromDate!.day.toString().padLeft(2, '0')}';
    final toISO =
        '${_toDate!.year.toString().padLeft(4, '0')}-${_toDate!.month.toString().padLeft(2, '0')}-${_toDate!.day.toString().padLeft(2, '0')}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Close Pledge',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.primary)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Calculation summary inside dialog
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: FlowColors.accent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: FlowColors.primaryLight),
                    ),
                    child: Column(
                      children: [
                        _dlgRow('Principal', money(principal)),
                        const Divider(height: 16),
                        _dlgRow('Interest', money(_simpleInterest)),
                        const Divider(height: 16),
                        _dlgRow('Total', money(_totalAmount), bold: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Pledge Number *',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: pledgeNoCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (_) {
                      if (dialogError != null) {
                        setDialogState(() => dialogError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Payment Received Via',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _modeButton(
                          label: 'Cash',
                          value: 'cash',
                          selected: selectedMode == 'cash',
                          onTap: () => setDialogState(() {
                            selectedMode = 'cash';
                            dialogError = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _modeButton(
                          label: 'UPI',
                          value: 'upi',
                          selected: selectedMode == 'upi',
                          onTap: () => setDialogState(() {
                            selectedMode = 'upi';
                            dialogError = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error,
                            color: Colors.red, size: 20),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dialogError!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(fontSize: 17, color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: FlowColors.primary),
                onPressed: isSaving
                    ? null
                    : () async {
                        final no = pledgeNoCtrl.text.trim();
                        if (no.isEmpty) {
                          setDialogState(() =>
                              dialogError = 'Pledge number is required.');
                          return;
                        }
                        if (selectedMode == null) {
                          setDialogState(() =>
                              dialogError = 'Select Cash or UPI.');
                          return;
                        }

                        setDialogState(() => isSaving = true);

                        final existing = await PledgeRepository.instance
                            .getPledgeByNumber(no);

                        if (!ctx.mounted) return;

                        if (existing != null) {
                          final msg = existing.status == 'open'
                              ? 'Pledge $no is currently open in the system. Please close it from the Open Pledge screen.'
                              : 'Pledge $no is already closed in the system.';
                          setDialogState(() {
                            isSaving = false;
                            dialogError = msg;
                          });
                          return;
                        }

                        // Not in DB — save as manual closed pledge
                        try {
                          await PledgeRepository.instance
                              .createManualClosedPledge(
                            pledgeNumber: no,
                            pledgeDate: fromISO,
                            closureDate: toISO,
                            principal: principal,
                            interest: _simpleInterest,
                            total: _totalAmount,
                            interestRate: _interestRate,
                            paymentMode: selectedMode!,
                          );

                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);

                          if (mounted) {
                            _resetFields();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Pledge $no closed. ${money(_totalAmount)} received via ${selectedMode == 'cash' ? 'Cash' : 'UPI'}.'),
                                backgroundColor: FlowColors.green,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        } catch (e) {
                          if (!ctx.mounted) return;
                          setDialogState(() {
                            isSaving = false;
                            dialogError = 'Error: $e';
                          });
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: FlowColors.textOnNavyLarge),
                      )
                    : const Text('CONFIRM CLOSE',
                        style: TextStyle(fontSize: 16, color: FlowColors.textOnNavySmall)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dlgRow(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 15, color: Colors.black54)),
        Text(value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: FlowColors.primary)),
      ],
    );
  }

  Widget _modeButton({
    required String label,
    required String value,
    required bool selected,
    required VoidCallback onTap,
  }) {
    Widget iconWidget = value == 'cash'
        ? const Icon(Icons.payments, size: 18, color: FlowColors.primary)
        : const Icon(Icons.qr_code_scanner, size: 18, color: FlowColors.primary);

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? FlowColors.accent : Colors.white,
        side: BorderSide(
            color: selected ? FlowColors.primary : Colors.black26,
            width: 2),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          iconWidget,
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                  color: FlowColors.primary)),
        ],
      ),
    );
  }

  void _resetFields() {
    final today = DateTime.now();
    setState(() {
      _principalController.clear();
      _fromDateController.clear();
      _toDateController.text = _formatDate(today);
      _fromDate = null;
      _toDate = today;
      _numberOfDays = null;
      _simpleInterest = 0.0;
      _totalAmount = 0.0;
      _minimumChargeNote = '';
      _hasResult = false;
    });
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invalid Input',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK',
                style: TextStyle(fontSize: 18, color: FlowColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        iconTheme: const IconThemeData(color: FlowColors.goldRich, size: 30),
        title: const Text('Interest Calculator',
            style: TextStyle(
                color: FlowColors.textOnNavyLarge,
                fontSize: 24,
                fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: FlowColors.goldRich, size: 30),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
        ],
      ),
      backgroundColor: FlowColors.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            _label('Principal Amount (₹)'),
            const SizedBox(height: 8),
            TextField(
              controller: _principalController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(
                prefixText: '₹  ',
                prefixStyle: TextStyle(fontSize: 22, color: Colors.black87),
                hintText: '0',
                hintStyle: TextStyle(fontSize: 22, color: Colors.grey),
              ),
              onChanged: (_) => setState(() {
                _hasResult = false;
              }),
            ),
            const SizedBox(height: 24),
            _label('From Date'),
            const SizedBox(height: 8),
            TextField(
              controller: _fromDateController,
              style: const TextStyle(fontSize: 22),
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                hintText: 'DD/MM/YYYY',
                hintStyle:
                    const TextStyle(fontSize: 20, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_month,
                      color: FlowColors.primary, size: 28),
                  onPressed: () => _pickDate(true),
                ),
              ),
              onChanged: (v) => _onDateTyped(v, true),
            ),
            const SizedBox(height: 24),
            _label('To Date'),
            const SizedBox(height: 8),
            TextField(
              controller: _toDateController,
              style: const TextStyle(fontSize: 22),
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                hintText: 'DD/MM/YYYY',
                hintStyle:
                    const TextStyle(fontSize: 20, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_month,
                      color: FlowColors.primary, size: 28),
                  onPressed: () => _pickDate(false),
                ),
              ),
              onChanged: (v) => _onDateTyped(v, false),
            ),
            if (_numberOfDays != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Number of days: $_numberOfDays',
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate, size: 26),
                label: const Text('CALCULATE',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ),
            // Result card comes first
            if (_hasResult) ...[
              const SizedBox(height: 28),
              FlowCard(
                backgroundColor: FlowColors.accent,
                header: 'Calculation Result',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _resultRow('Simple Interest', money(_simpleInterest)),
                    const Divider(height: 24, thickness: 1),
                    _resultRow('Total Amount', money(_totalAmount), bold: true),
                    if (_minimumChargeNote.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.info,
                              color: Colors.orange, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _minimumChargeNote,
                              style: const TextStyle(
                                  fontSize: 17,
                                  color: Colors.orange,
                                  fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Close Pledge button at the bottom after results
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _showClosePledgeDialog,
                  icon: const Icon(Icons.lock, size: 24),
                  label: const Text('CLOSE PLEDGE',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlowColors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: FlowColors.primary),
      );

  Widget _resultRow(String label, String value, {bool bold = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87)),
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  color: FlowColors.primary)),
        ],
      );
}
