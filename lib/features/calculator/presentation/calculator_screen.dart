import 'package:flutter/material.dart';

import '../../../core/settings/app_settings_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/pledge_id_search_popup.dart';
import '../../../shared/widgets/restricted_action.dart';
import '../../pledges/presentation/load_existing_pledge_screen.dart';
import '../../pledges/presentation/open_pledge_screen.dart';
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
    final val = await _settingsRepository.getString('interest_rate') ??
        await _settingsRepository.getString('default_interest_rate');
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
    final principal = double.tryParse(
        _principalController.text.trim().replaceAll(',', ''));
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

  // ─── Close Pledge (reusable search popup) ─────────────────────────────────

  /// Opens the reusable "Find Pledge" popup. A found *open* pledge opens its
  /// detail screen (interest as of today); a not-in-system pledge routes to the
  /// Load Existing Pledge screen pre-filled from the calculator, where staff
  /// confirm a migrate-and-close (or migrate-and-renew).
  void _openClosePledgeSearch() {
    final principal = double.tryParse(
            _principalController.text.trim().replaceAll(',', '')) ??
        0;
    showPledgeIdSearchPopup(
      context,
      contextDate: null,
      prefilledAmount: principal,
      prefilledOpenDate: _fromDate,
      onPledgeFound: (pledge) {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PledgeDetailScreen(pledgeId: pledge.id!)),
        );
      },
      onPledgeNotFound: (pledgeId) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LoadExistingPledgeScreen(
              prefilledPledgeId: pledgeId,
              prefilledAmount: principal,
              prefilledOpenDate: _fromDate,
              openDateEditable: true,
              closeDate: DateTime.now(),
              closeDateEditable: false,
              sourceContext: 'calculator',
            ),
          ),
        );
      },
    );
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
              inputFormatters: [IndianNumberFormatter()],
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
              RestrictedAction(
                child: SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _openClosePledgeSearch,
                  icon: const Icon(Icons.lock, size: 24),
                  label: const Text('CLOSE PLEDGE',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlowColors.primary,
                    foregroundColor: FlowColors.textOnNavyLarge,
                    side: const BorderSide(
                        color: FlowColors.borderOnNavy, width: 0.8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
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
