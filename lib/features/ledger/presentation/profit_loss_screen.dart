import 'package:flutter/material.dart';

import '../../../core/services/ledger_report_service.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../core/utils/ledger_amount_formatter.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/report_period_selector.dart';
import '../../admin/data/admin_repository.dart';
import '../ledger_print_reports.dart';
import 'general_ledger_screen.dart';
import 'ledger_report_widgets.dart';

/// Profit & Loss: income and expense account movements for a period, with
/// Net Profit / Net Loss. Period selection shares the Admin Reports
/// component so quarter and FY boundaries stay consistent app-wide.
///
/// No virtual-line handling is needed: income/expense accounts never receive
/// virtual lines (only Cash and Gold Loan Receivable do), so every figure is
/// real. Interest recognised at capitalisation posts to Interest Collected
/// like real interest, so it is naturally included — no separate breakout.
class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  final _settings = AppSettingsRepository();

  ReportPeriod _selected = ReportPeriod.q2;
  DateTime? _customFrom;
  DateTime? _customTo;

  bool _openingPosted = true;
  String _ledgerStartDate = '';

  List<TrialBalanceRow> _income = [];
  List<TrialBalanceRow> _expenses = [];
  bool _showZero = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (!AdminSession.isValid && mounted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => Navigator.pop(context));
      return;
    }
    // Default to the quarter containing today.
    final now = DateTime.now();
    _selected = switch (now.month) {
      >= 4 && <= 6 => ReportPeriod.q1,
      >= 7 && <= 9 => ReportPeriod.q2,
      >= 10 && <= 12 => ReportPeriod.q3,
      _ => ReportPeriod.q4,
    };
    _load();
  }

  ({String from, String to}) get _range => reportPeriodRange(
      _selected, DateTime.now(),
      customFrom: _customFrom, customTo: _customTo);

  Future<void> _load() async {
    if (_selected == ReportPeriod.custom &&
        (_customFrom == null || _customTo == null)) {
      return;
    }
    setState(() => _loading = true);
    _openingPosted = await _settings.getBool('ledger_opening_posted');
    _ledgerStartDate = await _settings.getString('ledger_start_date') ?? '';
    final range = _range;
    final service = LedgerReportService.instance;
    final income =
        await service.getTypeMovements('income', range.from, range.to);
    final expenses =
        await service.getTypeMovements('expense', range.from, range.to);
    if (!mounted) return;
    setState(() {
      _income = income;
      _expenses = expenses;
      _loading = false;
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final from = await showDatePicker(
      context: context,
      initialDate: _customFrom ?? DateTime(now.year, 4, 1),
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'From Date',
    );
    if (from == null || !mounted) return;

    final to = await showDatePicker(
      context: context,
      initialDate: _customTo ?? now,
      firstDate: from,
      lastDate: now,
      helpText: 'To Date',
    );
    if (to == null || !mounted) return;

    setState(() {
      _customFrom = from;
      _customTo = to;
    });
    _load();
  }

  // Income accounts are credit-natured: period figure = credits − debits
  // = −net. Expense figure = net (debits − credits).
  double _incomeValue(TrialBalanceRow r) => -r.net;
  double _expenseValue(TrialBalanceRow r) => r.net;

  List<TrialBalanceRow> _visible(List<TrialBalanceRow> rows) =>
      _showZero ? rows : rows.where((r) => r.net.abs() >= 0.005).toList();

  double get _totalIncome =>
      _income.fold(0.0, (s, r) => s + _incomeValue(r));
  double get _totalExpenses =>
      _expenses.fold(0.0, (s, r) => s + _expenseValue(r));
  double get _netProfit => _totalIncome - _totalExpenses;

  void _openGeneralLedger(TrialBalanceRow row) {
    final range = _range;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GeneralLedgerScreen(
          initialAccountId: row.accountId,
          initialFrom: DateTime.tryParse(range.from),
          initialTo: DateTime.tryParse(range.to),
        ),
      ),
    );
  }

  // ─── Print / Save PDF ─────────────────────────────────────────────────────

  Future<void> _showPrintDialog() async {
    final range = _range;
    final action = await showLedgerPrintDialog(
      context: context,
      title: 'Print Profit & Loss',
      contextLine:
          '${isoToDisplay(range.from)} to ${isoToDisplay(range.to)}',
    );
    if (action == null || !mounted) return;
    await _generatePdf(save: action == 'save');
  }

  Future<void> _generatePdf({required bool save}) async {
    final range = _range;
    await runLedgerPdf(
      context: context,
      build: () => LedgerPrintReports.profitLoss(
        fromDate: range.from,
        toDate: range.to,
        includeZero: _showZero,
      ),
      fileName: '${LedgerPrintReports.filePrefix}_ProfitLoss_'
          '${LedgerPrintReports.fileStamp(range.from)}_to_'
          '${LedgerPrintReports.fileStamp(range.to)}.pdf',
      documentName: 'Profit & Loss ${isoToDisplay(range.from)} to '
          '${isoToDisplay(range.to)}',
      save: save,
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Profit & Loss'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print / Save PDF',
            onPressed: _loading ? null : _showPrintDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          ReportPeriodBar(
            selected: _selected,
            onSelect: (p) async {
              if (p == ReportPeriod.custom) {
                setState(() => _selected = ReportPeriod.custom);
                await _pickCustomRange();
              } else {
                setState(() => _selected = p);
                _load();
              }
            },
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32)
                        .withNavBarInset(context),
                    children: [
                      if (!_openingPosted)
                        OpeningBalancePendingBanner(
                            ledgerStartDate: _ledgerStartDate),
                      _periodChip(),
                      _zeroToggle(),
                      ..._section('Income', _visible(_income),
                          _incomeValue, FlowColors.green),
                      ..._section('Expenses', _visible(_expenses),
                          _expenseValue, FlowColors.red),
                      _totalsCard(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _periodChip() {
    final range = _range;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: FlowColors.accent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range, size: 18, color: FlowColors.primary),
          const SizedBox(width: 8),
          Text(
            '${isoToDisplay(range.from)} – ${isoToDisplay(range.to)}',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: FlowColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _zeroToggle() {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      title: const Text('Show zero-balance accounts',
          style: TextStyle(fontSize: 14)),
      value: _showZero,
      activeThumbColor: FlowColors.primary,
      onChanged: (v) => setState(() => _showZero = v),
    );
  }

  List<Widget> _section(String title, List<TrialBalanceRow> rows,
      double Function(TrialBalanceRow) value, Color color) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 4),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
                letterSpacing: 0.5)),
      ),
      if (rows.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Text('No activity in this period',
              style: TextStyle(fontSize: 14, color: Colors.black45)),
        )
      else
        FlowCard(
          padding: const EdgeInsets.all(0),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                InkWell(
                  onTap: () => _openGeneralLedger(rows[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      border: i == rows.length - 1
                          ? null
                          : const Border(
                              bottom: BorderSide(
                                  color: Color(0x14000000), width: 1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(rows[i].name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              Text(rows[i].code,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: FlowColors.medText)),
                            ],
                          ),
                        ),
                        Text(LedgerAmountFormatter.format(value(rows[i])),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: color)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _totalsCard() {
    final isProfit = _netProfit >= 0;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: FlowColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _totalRow(
              'Total Income', LedgerAmountFormatter.format(_totalIncome)),
          const SizedBox(height: 6),
          _totalRow('Total Expenses',
              LedgerAmountFormatter.format(_totalExpenses)),
          const Divider(color: Colors.white24, height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isProfit ? 'NET PROFIT' : 'NET LOSS',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: isProfit
                          ? const Color(0xFF81C784)
                          : const Color(0xFFEF9A9A))),
              Text(LedgerAmountFormatter.format(_netProfit.abs()),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isProfit
                          ? const Color(0xFF81C784)
                          : const Color(0xFFEF9A9A))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14, color: FlowColors.textOnNavySmall)),
        Text(value,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: FlowColors.textOnNavyLarge)),
      ],
    );
  }
}
