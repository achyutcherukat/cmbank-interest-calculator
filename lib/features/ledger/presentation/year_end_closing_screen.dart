import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/services/ledger_posting_service.dart';
import '../../../core/services/ledger_report_service.dart';
import '../../../core/utils/ledger_amount_formatter.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../admin/data/admin_repository.dart';
import '../data/chart_of_accounts_repository.dart';
import '../data/ledger_account_model.dart';

/// Year-End Closing Wizard (Prompt 11): zeroes a financial year's Income and
/// Expense accounts and transfers the net profit/loss straight to the two
/// Partner Capital accounts per the CA-provided split — one balanced MANUAL
/// entry, tracked in `ledger_year_end_closures` so a year can never be closed
/// twice.
///
/// Reuses the P&L computation (`LedgerReportService.getTypeMovements`); the
/// figures are read-only here — corrections happen upstream via
/// Edit/reversal before closing, never by overriding a total on this screen.
class YearEndClosingScreen extends StatefulWidget {
  const YearEndClosingScreen({super.key});

  @override
  State<YearEndClosingScreen> createState() => _YearEndClosingScreenState();
}

class _YearEndClosingScreenState extends State<YearEndClosingScreen> {
  final _service = LedgerReportService.instance;

  bool _loading = true;
  bool _computing = false;
  bool _saving = false;
  String? _error;
  String? _loadError;

  int _currentStep = 0;

  // Financial-year selection.
  List<int> _fyOptions = const [];
  int _fyStartYear = 0;
  Map<String, Object?>? _closure; // existing closure for the selected FY

  // Partner Capital accounts (codes 3001 / 3002).
  LedgerAccount? _partnerA;
  LedgerAccount? _partnerB;

  // Computed P&L for the selected FY.
  List<TrialBalanceRow> _income = const [];
  List<TrialBalanceRow> _expenses = const [];

  // Step 3 split entry.
  final _ctrlA = TextEditingController();
  final _ctrlB = TextEditingController();

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

  @override
  void dispose() {
    _ctrlA.dispose();
    _ctrlB.dispose();
    super.dispose();
  }

  // ─── Financial-year helpers (Indian FY: 1 Apr – 31 Mar) ─────────────────────

  static String _fyLabel(int startYear) =>
      '$startYear-${((startYear + 1) % 100).toString().padLeft(2, '0')}';

  static ({String from, String to}) _fyRange(int startYear) => (
        from: '$startYear-04-01',
        to: '${startYear + 1}-03-31',
      );

  static String _fyLastDay(int startYear) => '${startYear + 1}-03-31';

  /// The most recent FY that has already ended (past its 31 March).
  static int _mostRecentEndedFYStart(DateTime today) {
    final currentStart = today.month >= 4 ? today.year : today.year - 1;
    return currentStart - 1;
  }

  // ─── Load ─────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final accounts = await ChartOfAccountsRepository.instance.getAll();
      _partnerA = _byCode(accounts, '3001');
      _partnerB = _byCode(accounts, '3002');
      if (_partnerA == null || _partnerB == null) {
        _loadError = 'Partner Capital accounts (3001 / 3002) are missing from '
            'the chart of accounts.';
        if (mounted) setState(() => _loading = false);
        return;
      }

      final recent = _mostRecentEndedFYStart(DateTime.now());
      _fyOptions = [for (var y = recent; y > recent - 6; y--) y];

      // Default to the most recent ended FY not yet closed.
      var defaultYear = recent;
      for (final y in _fyOptions) {
        if (await _service.getYearEndClosure(_fyLabel(y)) == null) {
          defaultYear = y;
          break;
        }
      }
      _fyStartYear = defaultYear;
      await _selectYear(defaultYear);
    } catch (_) {
      _loadError = 'Could not load the closing wizard. Please try again.';
    }
    if (mounted) setState(() => _loading = false);
  }

  static LedgerAccount? _byCode(List<LedgerAccount> accounts, String code) {
    for (final a in accounts) {
      if (a.code == code) return a;
    }
    return null;
  }

  Future<void> _selectYear(int year) async {
    setState(() {
      _computing = true;
      _fyStartYear = year;
      _error = null;
      _ctrlA.clear();
      _ctrlB.clear();
    });
    final closure = await _service.getYearEndClosure(_fyLabel(year));
    if (closure == null) {
      final range = _fyRange(year);
      _income = await _service.getTypeMovements('income', range.from, range.to);
      _expenses =
          await _service.getTypeMovements('expense', range.from, range.to);
    } else {
      _income = const [];
      _expenses = const [];
    }
    if (!mounted) return;
    setState(() {
      _closure = closure;
      _computing = false;
      _currentStep = 0;
    });
  }

  // ─── Derived figures ────────────────────────────────────────────────────────

  // Income accounts are credit-natured (figure = −net); expenses = net.
  double _incomeValue(TrialBalanceRow r) => -r.net;
  double _expenseValue(TrialBalanceRow r) => r.net;

  double get _totalIncome => _income.fold(0.0, (s, r) => s + _incomeValue(r));
  double get _totalExpenses =>
      _expenses.fold(0.0, (s, r) => s + _expenseValue(r));
  double get _netResult => _totalIncome - _totalExpenses;
  bool get _isProfit => _netResult > 0;

  List<TrialBalanceRow> get _nonZeroIncome =>
      _income.where((r) => r.net.abs() >= 0.005).toList();
  List<TrialBalanceRow> get _nonZeroExpenses =>
      _expenses.where((r) => r.net.abs() >= 0.005).toList();
  bool get _hasSomethingToClose =>
      _nonZeroIncome.isNotEmpty || _nonZeroExpenses.isNotEmpty;

  double _amount(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  double get _splitDifference =>
      (_amount(_ctrlA) + _amount(_ctrlB)) - _netResult.abs();

  // Paise-exact (see Opening Balance Wizard): inputs allow 2 decimals and
  // doubles can't represent most paise exactly, so compare rounded paise.
  bool get _splitMatches => (_splitDifference * 100).round() == 0;

  /// The exact lines the closing entry will post — also what Step 4 previews,
  /// so the preview and the posted entry can never diverge. Each Income/Expense
  /// account is zeroed by the opposite of its net balance (robust even for an
  /// unusual contra balance); the capital split is credited on a profit,
  /// debited on a loss.
  List<YearEndClosingLine> _buildLines() {
    final lines = <YearEndClosingLine>[];
    for (final r in [..._income, ..._expenses]) {
      final n = r.net; // debit − credit
      if (n.abs() < 0.005) continue;
      lines.add(YearEndClosingLine(
        accountId: r.accountId,
        accountName: r.name,
        debit: n < 0 ? -n : 0,
        credit: n > 0 ? n : 0,
      ));
    }
    final a = _amount(_ctrlA);
    final b = _amount(_ctrlB);
    if (a > 0.005) {
      lines.add(YearEndClosingLine(
        accountId: _partnerA!.id!,
        accountName: _partnerA!.name,
        debit: _isProfit ? 0 : a,
        credit: _isProfit ? a : 0,
      ));
    }
    if (b > 0.005) {
      lines.add(YearEndClosingLine(
        accountId: _partnerB!.id!,
        accountName: _partnerB!.name,
        debit: _isProfit ? 0 : b,
        credit: _isProfit ? b : 0,
      ));
    }
    return lines;
  }

  // ─── Post ─────────────────────────────────────────────────────────────────

  Future<void> _confirmAndPost() async {
    final lines = _buildLines();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Close FY ${_fyLabel(_fyStartYear)}?',
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'One closing entry dated '
                    '${isoToDisplay(_fyLastDay(_fyStartYear))}:',
                    style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 10),
                ...lines.map(_previewLine),
                const SizedBox(height: 12),
                const Text(
                  'This is a one-time, per-year action and cannot be edited '
                  'afterward — only corrected with a reversing entry.',
                  style: TextStyle(
                      fontSize: 13,
                      color: FlowColors.red,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: FlowColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONFIRM & POST',
                style: TextStyle(color: FlowColors.textOnNavyLarge)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await LedgerPostingService.instance.postYearEndClosing(
        financialYear: _fyLabel(_fyStartYear),
        entryDate: _fyLastDay(_fyStartYear),
        narration: 'Year-End Closing FY ${_fyLabel(_fyStartYear)}',
        lines: lines,
        totalIncome: _totalIncome,
        totalExpenses: _totalExpenses,
        netResult: _netResult,
        auditJson: jsonEncode({
          'financial_year': _fyLabel(_fyStartYear),
          'entry_date': _fyLastDay(_fyStartYear),
          'total_income': _totalIncome,
          'total_expenses': _totalExpenses,
          'net_result': _netResult,
          'partner_split': {
            _partnerA!.name: _amount(_ctrlA),
            _partnerB!.name: _amount(_ctrlB),
          },
          'lines': [
            for (final l in lines)
              {
                'account': l.accountName,
                if (l.debit > 0) 'debit': l.debit,
                if (l.credit > 0) 'credit': l.credit,
              },
          ],
        }),
      );
      if (!mounted) return;
      // Reload into the read-only closed state for this year.
      await _selectYear(_fyStartYear);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('FY ${_fyLabel(_fyStartYear)} closed successfully.')));
    } on LedgerPostingException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to post the closing entry. Please try again.';
        _saving = false;
      });
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Year-End Closing'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _errorView(_loadError!)
              : _closure != null
                  ? _closedView()
                  : _wizard(),
    );
  }

  Widget _errorView(String message) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: FlowColors.red)),
        ),
      );

  // ── Already-closed (read-only) ────────────────────────────────────────────

  Widget _closedView() {
    final c = _closure!;
    final income = (c['total_income'] as num?)?.toDouble() ?? 0;
    final expenses = (c['total_expenses'] as num?)?.toDouble() ?? 0;
    final net = (c['net_result'] as num?)?.toDouble() ?? 0;
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 16, 16, 32).withNavBarInset(context),
      children: [
        _fySelectorCard(),
        const SizedBox(height: 4),
        FlowCard(
          borderColor: FlowColors.green,
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: FlowColors.green, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FY ${_fyLabel(_fyStartYear)} is already closed',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                        'Closed on '
                        '${isoToDisplay((c['closed_at'] as String? ?? '').split('T').first)}',
                        style: const TextStyle(
                            fontSize: 13, color: FlowColors.medText)),
                  ],
                ),
              ),
            ],
          ),
        ),
        FlowCard(
          header: 'CLOSURE SUMMARY',
          child: Column(
            children: [
              _summaryRow('Total Income', income),
              _summaryRow('Total Expenses', expenses),
              const Divider(height: 18),
              _summaryRow(net >= 0 ? 'Net Profit' : 'Net Loss', net.abs(),
                  emphasized: true),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'A closed year cannot be closed again. To correct it, reverse the '
            'closing journal entry from the General Ledger, then re-run this '
            'wizard.',
            style: TextStyle(fontSize: 13, color: FlowColors.medText),
          ),
        ),
      ],
    );
  }

  // ── Wizard (manual paged flow) ────────────────────────────────────────────
  //
  // A plain ListView rather than a Material Stepper — the rest of the app's
  // wizards are ListView-based, and Stepper's shrink-wrapping viewport misbehaves
  // inside this navigation stack.

  static const _stepTitles = <String>[
    'Select financial year',
    'Review the year',
    'Partner split',
    'Confirm & post',
  ];

  Widget _wizard() {
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 16, 16, 32).withNavBarInset(context),
      children: [
        _stepHeader(),
        const SizedBox(height: 12),
        _stepContent(),
        const SizedBox(height: 20),
        _navButtons(),
      ],
    );
  }

  Widget _stepHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STEP ${_currentStep + 1} OF ${_stepTitles.length}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: FlowColors.medText,
                letterSpacing: 1.0)),
        const SizedBox(height: 2),
        Text(_stepTitles[_currentStep],
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
      ],
    );
  }

  Widget _stepContent() {
    switch (_currentStep) {
      case 0:
        return _fySelectorCard();
      case 1:
        return _summaryStep();
      case 2:
        return _splitStep();
      default:
        return _confirmStep();
    }
  }

  Widget _navButtons() {
    final isLast = _currentStep == 3;
    return Row(
      children: [
        if (_currentStep > 0) ...[
          OutlinedButton(
            onPressed: _saving ? null : () => setState(() => _currentStep -= 1),
            child: const Text('Back'),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: isLast
              ? ElevatedButton.icon(
                  onPressed: _saving ? null : _confirmAndPost,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: FlowColors.goldRich))
                      : const Icon(Icons.playlist_add_check),
                  label: const Text('REVIEW & POST'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlowColors.primary,
                    foregroundColor: FlowColors.goldRich,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                )
              : ElevatedButton(
                  onPressed: _canContinue() ? _onContinue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlowColors.primary,
                    foregroundColor: FlowColors.textOnNavyLarge,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('NEXT'),
                ),
        ),
      ],
    );
  }

  bool _canContinue() {
    switch (_currentStep) {
      case 0:
        return !_computing && _closure == null;
      case 1:
        return _hasSomethingToClose;
      case 2:
        return _splitMatches;
      default:
        return false;
    }
  }

  void _onContinue() {
    if (_currentStep < 3 && _canContinue()) {
      setState(() => _currentStep += 1);
    }
  }

  // ── Step 1: FY selector ───────────────────────────────────────────────────

  Widget _fySelectorCard() {
    return FlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Financial year to close',
              style: TextStyle(fontSize: 13, color: FlowColors.medText)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _fyStartYear,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final y in _fyOptions)
                DropdownMenuItem<int>(value: y, child: Text('FY ${_fyLabel(y)}')),
            ],
            onChanged: _computing
                ? null
                : (v) {
                    if (v != null) _selectYear(v);
                  },
          ),
          if (_computing)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  // ── Step 2: computed summary ──────────────────────────────────────────────

  Widget _summaryStep() {
    if (!_hasSomethingToClose) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No income or expense activity in this financial year — there is '
          'nothing to close.',
          style: TextStyle(fontSize: 14, color: FlowColors.medText),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _accountList('Income', _nonZeroIncome, _incomeValue),
        const SizedBox(height: 10),
        _accountList('Expenses', _nonZeroExpenses, _expenseValue),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: FlowColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _totalRow('Total Income', _totalIncome),
              const SizedBox(height: 6),
              _totalRow('Total Expenses', _totalExpenses),
              const Divider(color: Colors.white24, height: 18),
              _totalRow(_isProfit ? 'Net Profit' : 'Net Loss',
                  _netResult.abs(),
                  emphasized: true),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'These figures come directly from posted transactions and are not '
            'editable here. Correct any underlying entry (Edit / reversal) '
            'before closing.',
            style: TextStyle(fontSize: 12, color: FlowColors.medText),
          ),
        ),
      ],
    );
  }

  Widget _accountList(String title, List<TrialBalanceRow> rows,
      double Function(TrialBalanceRow) value) {
    return FlowCard(
      header: title.toUpperCase(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: rows.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('No activity',
                  style: TextStyle(fontSize: 14, color: Colors.black45)),
            )
          : Column(
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(r.name,
                              style: const TextStyle(fontSize: 14)),
                        ),
                        Text(LedgerAmountFormatter.format(value(r)),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  // ── Step 3: partner split ─────────────────────────────────────────────────

  Widget _splitStep() {
    final diff = _splitDifference;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the ${_isProfit ? 'profit' : 'loss'} share for each partner, '
          'as calculated by the CA. The two must add up to the '
          '${_isProfit ? 'Net Profit' : 'Net Loss'} of '
          '${LedgerAmountFormatter.format(_netResult.abs())}.',
          style: const TextStyle(fontSize: 13, color: FlowColors.medText),
        ),
        const SizedBox(height: 14),
        _splitField(_partnerA!.name, _ctrlA),
        const SizedBox(height: 12),
        _splitField(_partnerB!.name, _ctrlB),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _splitMatches
                ? FlowColors.green.withValues(alpha: 0.10)
                : FlowColors.orange.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: _splitMatches
                    ? FlowColors.green.withValues(alpha: 0.5)
                    : FlowColors.orange.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_splitMatches ? 'Split matches' : 'Difference',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Text(
                _splitMatches
                    ? '✓'
                    : LedgerAmountFormatter.format(diff.abs()),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color:
                        _splitMatches ? FlowColors.green : FlowColors.orange),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _splitField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [LedgerDecimalInputFormatter()],
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '₹ ',
        hintText: '0',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  // ── Step 4: confirm & post ────────────────────────────────────────────────

  Widget _confirmStep() {
    final lines = _buildLines();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Review every line of the closing entry dated '
          '${isoToDisplay(_fyLastDay(_fyStartYear))}. On confirm it posts as '
          'one balanced journal entry and FY ${_fyLabel(_fyStartYear)} is '
          'marked closed.',
          style: const TextStyle(fontSize: 13, color: FlowColors.medText),
        ),
        const SizedBox(height: 12),
        FlowCard(
          header: 'CLOSING ENTRY',
          child: Column(children: lines.map(_previewLine).toList()),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!,
                style: const TextStyle(color: FlowColors.red, fontSize: 14)),
          ),
      ],
    );
  }

  Widget _previewLine(YearEndClosingLine l) {
    final isDebit = l.debit > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(l.accountName, style: const TextStyle(fontSize: 14))),
          Text(
            '${isDebit ? 'Dr' : 'Cr'} '
            '${LedgerAmountFormatter.format(isDebit ? l.debit : l.credit)}',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDebit ? FlowColors.green : FlowColors.red),
          ),
        ],
      ),
    );
  }

  // ── Shared small rows ─────────────────────────────────────────────────────

  Widget _totalRow(String label, double value, {bool emphasized = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: emphasized ? 16 : 14,
                fontWeight: emphasized ? FontWeight.bold : FontWeight.normal,
                color: emphasized
                    ? FlowColors.goldRich
                    : FlowColors.textOnNavySmall)),
        Text(LedgerAmountFormatter.format(value),
            style: TextStyle(
                fontSize: emphasized ? 18 : 15,
                fontWeight: FontWeight.bold,
                color: emphasized
                    ? FlowColors.goldRich
                    : FlowColors.textOnNavyLarge)),
      ],
    );
  }

  Widget _summaryRow(String label, double value, {bool emphasized = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: emphasized ? 16 : 14,
                  fontWeight:
                      emphasized ? FontWeight.bold : FontWeight.w500)),
          Text(LedgerAmountFormatter.format(value),
              style: TextStyle(
                  fontSize: emphasized ? 17 : 15,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.primary)),
        ],
      ),
    );
  }
}
