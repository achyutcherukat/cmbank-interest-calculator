import 'package:flutter/material.dart';

import '../../../core/services/ledger_report_service.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../core/utils/ledger_amount_formatter.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../admin/data/admin_repository.dart';
import '../data/ledger_account_model.dart';
import '../ledger_print_reports.dart';
import 'general_ledger_screen.dart';
import 'ledger_report_widgets.dart';

/// Balance Sheet as of a date: Assets vs Liabilities + Capital.
///
/// There is no Retained Earnings account by design — profit reaches Partner
/// Capital only via a manual year-end closing entry. Until that entry
/// exists, the year's profit sits in income/expense balances, so the Capital
/// section includes a computed, display-only "Current Year Earnings" line
/// (ledger start date → as-of date). It is never written to the database.
class BalanceSheetScreen extends StatefulWidget {
  const BalanceSheetScreen({super.key});

  @override
  State<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends State<BalanceSheetScreen> {
  final _settings = AppSettingsRepository();

  DateTime _asOf = DateTime.now();

  bool _openingPosted = true;
  String _ledgerStartDate = '';

  List<TrialBalanceRow> _rows = [];
  double _currentYearEarnings = 0;
  bool _loading = true;

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
    _openingPosted = await _settings.getBool('ledger_opening_posted');
    _ledgerStartDate = await _settings.getString('ledger_start_date') ?? '';
    final service = LedgerReportService.instance;
    final rows = await service.getTrialBalance(_iso(_asOf));
    // Live computation, never posted: earnings from the ledger's start
    // through the as-of date — the same figure a P&L over that range shows.
    final earnings = _ledgerStartDate.isEmpty
        ? 0.0
        : await service.getEarnings(_ledgerStartDate, _iso(_asOf));
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _currentYearEarnings = earnings;
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOf,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _asOf = picked);
    _load();
  }

  // Balance-sheet display values: assets are debit-natured (value = net),
  // liabilities/capital are credit-natured (value = −net). Zero-balance
  // accounts are hidden (same pattern as the Trial Balance).
  List<TrialBalanceRow> _ofType(String type) => _rows
      .where((r) => r.accountType == type && r.net.abs() >= 0.005)
      .toList();

  double get _totalAssets => _rows
      .where((r) => r.accountType == LedgerAccountType.asset)
      .fold(0.0, (s, r) => s + r.net);

  double get _totalLiabilities => _rows
      .where((r) => r.accountType == LedgerAccountType.liability)
      .fold(0.0, (s, r) => s - r.net);

  double get _totalPostedCapital => _rows
      .where((r) => r.accountType == LedgerAccountType.capital)
      .fold(0.0, (s, r) => s - r.net);

  double get _totalLiabCapitalEarnings =>
      _totalLiabilities + _totalPostedCapital + _currentYearEarnings;

  void _openGeneralLedger(TrialBalanceRow row) {
    final start = _ledgerStartDate.isNotEmpty
        ? DateTime.tryParse(_ledgerStartDate)
        : null;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GeneralLedgerScreen(
          initialAccountId: row.accountId,
          initialFrom: start,
          initialTo: _asOf,
        ),
      ),
    );
  }

  // ─── Print / Save PDF ─────────────────────────────────────────────────────

  Future<void> _showPrintDialog() async {
    final action = await showLedgerPrintDialog(
      context: context,
      title: 'Print Balance Sheet',
      contextLine: 'As of ${isoToDisplay(_iso(_asOf))}',
    );
    if (action == null || !mounted) return;
    await _generatePdf(save: action == 'save');
  }

  Future<void> _generatePdf({required bool save}) async {
    await runLedgerPdf(
      context: context,
      build: () => LedgerPrintReports.balanceSheet(
        asOfDate: _iso(_asOf),
        ledgerStartDate: _ledgerStartDate,
      ),
      fileName: '${LedgerPrintReports.filePrefix}_BalanceSheet_AsOf_'
          '${LedgerPrintReports.fileStamp(_iso(_asOf))}.pdf',
      documentName: 'Balance Sheet as of ${isoToDisplay(_iso(_asOf))}',
      save: save,
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Paise-exact comparison (see Trial Balance) — tolerant of double
    // representation noise, strict at one paisa and above.
    final mismatch =
        ((_totalAssets - _totalLiabCapitalEarnings) * 100).round() != 0;
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Balance Sheet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print / Save PDF',
            onPressed: _loading ? null : _showPrintDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32)
                  .withNavBarInset(context),
              children: [
                if (!_openingPosted)
                  OpeningBalancePendingBanner(
                      ledgerStartDate: _ledgerStartDate),
                _dateCard(),
                const SizedBox(height: 12),
                ..._section('Assets', LedgerAccountType.asset,
                    debitNatured: true),
                ..._section('Liabilities', LedgerAccountType.liability,
                    debitNatured: false),
                ..._capitalSection(),
                _totalsCard(mismatch),
                if (mismatch)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Assets do not equal Liabilities + Capital + Earnings '
                      '— this indicates a posting bug, not a data-entry '
                      'problem. Report this.',
                      style: TextStyle(
                          fontSize: 13,
                          color: FlowColors.red,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _dateCard() {
    return FlowCard(
      child: InkWell(
        onTap: _pickDate,
        borderRadius: BorderRadius.circular(6),
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'As of date',
            border: OutlineInputBorder(),
            isDense: true,
            suffixIcon: Icon(Icons.calendar_today_outlined, size: 16),
          ),
          child: Text(isoToDisplay(_iso(_asOf)),
              style: const TextStyle(fontSize: 14)),
        ),
      ),
    );
  }

  List<Widget> _section(String title, String type,
      {required bool debitNatured}) {
    final rows = _ofType(type);
    return [
      _sectionHeader(title),
      if (rows.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Text('No balances',
              style: TextStyle(fontSize: 14, color: Colors.black45)),
        )
      else
        FlowCard(
          padding: const EdgeInsets.all(0),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                _accountRow(rows[i],
                    value: debitNatured ? rows[i].net : -rows[i].net,
                    isLast: i == rows.length - 1),
            ],
          ),
        ),
    ];
  }

  List<Widget> _capitalSection() {
    final rows = _ofType(LedgerAccountType.capital);
    return [
      _sectionHeader('Capital'),
      FlowCard(
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            for (final row in rows)
              _accountRow(row, value: -row.net, isLast: false),
            _earningsRow(),
          ],
        ),
      ),
    ];
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 4),
      child: Text(title.toUpperCase(),
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
              letterSpacing: 0.5)),
    );
  }

  Widget _accountRow(TrialBalanceRow row,
      {required double value, required bool isLast}) {
    return InkWell(
      onTap: () => _openGeneralLedger(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: Color(0x14000000), width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(row.code,
                      style: const TextStyle(
                          fontSize: 11, color: FlowColors.medText)),
                ],
              ),
            ),
            Text(LedgerAmountFormatter.format(value),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: value < 0
                        ? FlowColors.red
                        : FlowColors.darkText)),
          ],
        ),
      ),
    );
  }

  /// Computed, display-only line — not a real account, so not tappable.
  Widget _earningsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: FlowColors.accent,
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(12)),
        border: const Border(
            top: BorderSide(color: Color(0x14000000), width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Current Year Earnings',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic)),
                Text(
                  'Unposted — will transfer to Partner Capital at '
                  'year-end close. Computed live '
                  '(${isoToDisplay(_ledgerStartDate)} – '
                  '${isoToDisplay(_iso(_asOf))}).',
                  style: const TextStyle(
                      fontSize: 11, color: FlowColors.medText),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(LedgerAmountFormatter.format(_currentYearEarnings),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  color: _currentYearEarnings < 0
                      ? FlowColors.red
                      : FlowColors.primary)),
        ],
      ),
    );
  }

  Widget _totalsCard(bool mismatch) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: mismatch ? FlowColors.red : FlowColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _totalRow(
              'Total Assets', LedgerAmountFormatter.format(_totalAssets)),
          const SizedBox(height: 6),
          _totalRow('Total Liabilities',
              LedgerAmountFormatter.format(_totalLiabilities)),
          const SizedBox(height: 6),
          _totalRow('Total Capital (posted)',
              LedgerAmountFormatter.format(_totalPostedCapital)),
          const SizedBox(height: 6),
          _totalRow('Current Year Earnings',
              LedgerAmountFormatter.format(_currentYearEarnings)),
          const Divider(color: Colors.white24, height: 18),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                  mismatch
                      ? 'ASSETS ≠ LIABILITIES + CAPITAL!'
                      : 'ASSETS = LIABILITIES + CAPITAL',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                      color: FlowColors.textOnNavyLarge)),
              Text(
                '${LedgerAmountFormatter.format(_totalAssets)} vs '
                '${LedgerAmountFormatter.format(_totalLiabCapitalEarnings)}',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.goldRich),
              ),
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
