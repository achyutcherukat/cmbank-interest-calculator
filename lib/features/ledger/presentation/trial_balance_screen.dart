import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/ledger_health_check_service.dart';
import '../../../core/services/ledger_report_service.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../core/utils/ledger_amount_formatter.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../admin/data/admin_repository.dart';
import '../data/ledger_account_model.dart';
import '../ledger_print_reports.dart';
import 'general_ledger_screen.dart';
import 'health_check_detail_screen.dart';
import 'ledger_report_widgets.dart';

/// Trial Balance: every active account's net balance as of a date, grouped
/// by account type, with each balance shown in the column matching its
/// actual sign (an overdrawn asset shows under Credit — the report reflects
/// reality, not natural-side assumptions). Totals must always be equal; a
/// mismatch is surfaced loudly because it means a posting-engine bug.
class TrialBalanceScreen extends StatefulWidget {
  const TrialBalanceScreen({super.key});

  @override
  State<TrialBalanceScreen> createState() => _TrialBalanceScreenState();
}

class _TrialBalanceScreenState extends State<TrialBalanceScreen> {
  final _settings = AppSettingsRepository();

  DateTime _asOf = DateTime.now();
  bool _showZero = false;

  bool _openingPosted = true;
  String _ledgerStartDate = '';

  List<TrialBalanceRow> _rows = [];
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
    _openingPosted = await _settings.getBool('ledger_opening_posted');
    _ledgerStartDate = await _settings.getString('ledger_start_date') ?? '';
    await _loadReport();
    // Silent background integrity checks (Prompt 10) — run once per open,
    // never block the report from rendering, only surface if something's off.
    unawaited(_runHealthCheck());
  }

  Future<void> _runHealthCheck() async {
    final HealthCheckResult result;
    try {
      result = await LedgerHealthCheckService.instance.run();
    } catch (_) {
      return; // a diagnostic must never break the screen
    }
    if (!mounted) return;
    if (result.hasIssues) {
      _showHealthCheckDialog(result);
    } else {
      _showAllClearDialog();
    }
  }

  /// Positive confirmation shown when both checks pass — deliberately lighter
  /// than the warning popup (green check, single OK), so an infrequent opener
  /// sees the check ran rather than being left to wonder.
  void _showAllClearDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: FlowColors.green, size: 26),
            SizedBox(width: 10),
            Text('Health Check'),
          ],
        ),
        content: const Text(
          'All accounts match the Cash Book, and no missing entries were '
          'found.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(color: FlowColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showHealthCheckDialog(HealthCheckResult result) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ledger Health Check'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in result.cashBankMismatches)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  "Cash Book and Ledger don't match: ${m.accountName} "
                  'differs by ${LedgerAmountFormatter.format(m.difference.abs())} '
                  'as of ${isoToDisplay(m.asOfDate)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            if (result.missingPostings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${result.missingPostings.length} transaction(s) appear to '
                  'be missing from the ledger.',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: FlowColors.primary),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HealthCheckDetailScreen(result: result),
                ),
              );
            },
            child: const Text('View Details',
                style: TextStyle(color: FlowColors.textOnNavyLarge)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final rows =
        await LedgerReportService.instance.getTrialBalance(_iso(_asOf));
    if (!mounted) return;
    setState(() {
      _rows = rows;
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
    _loadReport();
  }

  List<TrialBalanceRow> get _visibleRows => _showZero
      ? _rows
      : _rows.where((r) => r.net.abs() >= 0.005).toList();

  double get _totalDebits => _visibleRows
      .where((r) => r.net > 0)
      .fold(0.0, (s, r) => s + r.net);

  double get _totalCredits => _visibleRows
      .where((r) => r.net < 0)
      .fold(0.0, (s, r) => s - r.net);

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
      title: 'Print Trial Balance',
      contextLine: 'As of ${isoToDisplay(_iso(_asOf))}',
    );
    if (action == null || !mounted) return;
    await _generatePdf(save: action == 'save');
  }

  Future<void> _generatePdf({required bool save}) async {
    await runLedgerPdf(
      context: context,
      build: () => LedgerPrintReports.trialBalance(
        asOfDate: _iso(_asOf),
        includeZero: _showZero,
      ),
      fileName: '${LedgerPrintReports.filePrefix}_TrialBalance_AsOf_'
          '${LedgerPrintReports.fileStamp(_iso(_asOf))}.pdf',
      documentName: 'Trial Balance as of ${isoToDisplay(_iso(_asOf))}',
      save: save,
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Paise-exact comparison — double representation error is orders of
    // magnitude below half a paisa, so rounding removes it without masking
    // a genuine (engine-bug) imbalance.
    final mismatch = ((_totalDebits - _totalCredits) * 100).round() != 0;
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Trial Balance'),
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
                _controlsCard(),
                const SizedBox(height: 12),
                if (_visibleRows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 50),
                    child: Center(
                      child: Text('No account activity yet',
                          style: TextStyle(
                              fontSize: 16, color: Colors.black45)),
                    ),
                  )
                else ...[
                  _columnHeader(),
                  for (final type in LedgerAccountType.all)
                    ..._typeSection(type),
                  _totalsRow(mismatch),
                  if (mismatch)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Debits and credits do not match — this indicates a '
                        'posting bug, not a data-entry problem. Report this.',
                        style: TextStyle(
                            fontSize: 13,
                            color: FlowColors.red,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _controlsCard() {
    return FlowCard(
      child: Column(
        children: [
          InkWell(
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Show zero-balance accounts',
                style: TextStyle(fontSize: 14)),
            value: _showZero,
            activeThumbColor: FlowColors.primary,
            onChanged: (v) => setState(() => _showZero = v),
          ),
        ],
      ),
    );
  }

  Widget _columnHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      child: Row(
        children: [
          const Expanded(
            child: Text('ACCOUNT',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: FlowColors.medText,
                    letterSpacing: 0.5)),
          ),
          SizedBox(
            width: 95,
            child: Text('DEBIT',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: FlowColors.green.withValues(alpha: 0.8),
                    letterSpacing: 0.5)),
          ),
          SizedBox(
            width: 95,
            child: Text('CREDIT',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: FlowColors.red.withValues(alpha: 0.8),
                    letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }

  List<Widget> _typeSection(String type) {
    final rows =
        _visibleRows.where((r) => r.accountType == type).toList();
    if (rows.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 4),
        child: Text(
          switch (type) {
            LedgerAccountType.asset => 'Assets',
            LedgerAccountType.liability => 'Liabilities',
            LedgerAccountType.capital => 'Capital',
            LedgerAccountType.income => 'Income',
            LedgerAccountType.expense => 'Expenses',
            _ => type,
          },
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
              letterSpacing: 0.5),
        ),
      ),
      FlowCard(
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              _accountRow(rows[i], isLast: i == rows.length - 1),
          ],
        ),
      ),
    ];
  }

  Widget _accountRow(TrialBalanceRow row, {required bool isLast}) {
    final isDebit = row.net > 0;
    final isZero = row.net.abs() < 0.005;
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
            SizedBox(
              width: 95,
              child: Text(
                !isZero && isDebit
                    ? LedgerAmountFormatter.format(row.net)
                    : '',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: FlowColors.green),
              ),
            ),
            SizedBox(
              width: 95,
              child: Text(
                !isZero && !isDebit
                    ? LedgerAmountFormatter.format(-row.net)
                    : '',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: FlowColors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalsRow(bool mismatch) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: mismatch ? FlowColors.red : FlowColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(mismatch ? 'TOTALS — MISMATCH!' : 'TOTALS',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.textOnNavyLarge,
                    letterSpacing: 0.5)),
          ),
          SizedBox(
            width: 95,
            child: Text(LedgerAmountFormatter.format(_totalDebits),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.goldRich)),
          ),
          SizedBox(
            width: 95,
            child: Text(LedgerAmountFormatter.format(_totalCredits),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.goldRich)),
          ),
        ],
      ),
    );
  }
}
