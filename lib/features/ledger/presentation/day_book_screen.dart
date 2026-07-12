import 'package:flutter/material.dart';

import '../../../core/services/ledger_report_service.dart';
import '../../../core/utils/ledger_amount_formatter.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../admin/data/admin_repository.dart';
import '../data/ledger_account_model.dart';
import 'general_ledger_screen.dart';

/// Day Book: every ledger entry posted on one specific date, per account,
/// with Total Debit / Total Credit for the day. Structural copy of Trial
/// Balance — same table/section layout — but scoped to a single date's
/// activity instead of a cumulative "as of" balance, and only accounts with
/// at least one entry that day appear (see [LedgerReportService.getDayBook]).
/// Totals must always be equal; a mismatch is surfaced loudly because it
/// means a posting-engine bug, not a data-entry problem.
class DayBookScreen extends StatefulWidget {
  const DayBookScreen({super.key});

  @override
  State<DayBookScreen> createState() => _DayBookScreenState();
}

class _DayBookScreenState extends State<DayBookScreen> {
  DateTime _date = DateTime.now();

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
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final rows = await LedgerReportService.instance.getDayBook(_iso(_date));
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _changeDate(int days) {
    setState(() => _date = _date.add(Duration(days: days)));
    _loadReport();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
    _loadReport();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
  }

  double get _totalDebits =>
      _rows.where((r) => r.net > 0).fold(0.0, (s, r) => s + r.net);

  double get _totalCredits =>
      _rows.where((r) => r.net < 0).fold(0.0, (s, r) => s - r.net);

  void _openGeneralLedger(TrialBalanceRow row) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GeneralLedgerScreen(
          initialAccountId: row.accountId,
          initialFrom: _date,
          initialTo: _date,
        ),
      ),
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
        title: const Text('Day Book'),
      ),
      body: Column(
        children: [
          _buildDateNav(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 32)
                        .withNavBarInset(context),
                    children: [
                      if (_rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 50),
                          child: Center(
                            child: Text('No entries posted on this date',
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
          ),
        ],
      ),
    );
  }

  // ─── Date Navigator ───────────────────────────────────────────────────────

  Widget _buildDateNav() {
    final label = 'Day Book for ${isoToDisplay(_iso(_date))}';
    return Container(
      color: FlowColors.accent,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left,
                size: 32, color: FlowColors.primary),
            onPressed: () => _changeDate(-1),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.primary)),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right,
                size: 32,
                color: _isToday ? Colors.black26 : FlowColors.primary),
            onPressed: _isToday ? null : () => _changeDate(1),
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
    final rows = _rows.where((r) => r.accountType == type).toList();
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
