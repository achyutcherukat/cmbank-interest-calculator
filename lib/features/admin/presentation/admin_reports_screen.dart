import 'package:flutter/material.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/report_period_selector.dart';
import '../data/admin_repository.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with WidgetsBindingObserver {
  // Period selection (shared ReportPeriod component)
  ReportPeriod _selected = ReportPeriod.q1;
  DateTime? _customFrom;
  DateTime? _customTo;

  ReportData? _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!AdminSession.isValid && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pop(context));
      return;
    }
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !AdminSession.isValid && mounted) {
      Navigator.pop(context);
    }
  }

  // ── Period helpers ────────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (_selected == ReportPeriod.custom &&
        (_customFrom == null || _customTo == null)) {
      return;
    }
    setState(() => _loading = true);
    try {
      final range = reportPeriodRange(_selected, DateTime.now(),
          customFrom: _customFrom, customTo: _customTo);
      final data =
          await AdminRepository.instance.getReportData(range.from, range.to);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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

  String _periodLabel() {
    final now = DateTime.now();
    final range = reportPeriodRange(_selected, now,
        customFrom: _customFrom, customTo: _customTo);
    return '${isoToDisplay(range.from)} – ${isoToDisplay(range.to)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Reports',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
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
                : _data == null
                    ? Center(
                        child: Text(
                          _selected == ReportPeriod.custom
                              ? 'Select a date range to view report'
                              : 'No data',
                          style: const TextStyle(
                              fontSize: 17, color: Colors.black45),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40)
                              .withNavBarInset(context),
                          children: [
                            _periodChip(),
                            _pledgeSummaryCard(),
                            _goldSummaryCard(),
                            _financialCard(),
                            _expensesCard(),
                            _exportCard(),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _periodChip() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: FlowColors.accent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FlowColors.primaryLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.date_range,
              size: 16, color: FlowColors.primary),
          const SizedBox(width: 8),
          Text(_periodLabel(),
              style: const TextStyle(
                  fontSize: 14,
                  color: FlowColors.primary,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Pledge Summary ────────────────────────────────────────────────────────────

  String _ordinalDate(String isoDate) {
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return isoDate;
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final d = dt.day;
    final suffix = (d >= 11 && d <= 13)
        ? 'th'
        : ['th', 'st', 'nd', 'rd', 'th'][d % 10 > 3 ? 0 : d % 10];
    return '$d$suffix ${months[dt.month - 1]} ${dt.year}';
  }

  Widget _pledgeSummaryCard() {
    final d = _data!;
    final maxText = d.maxDayDisbursedDate.isEmpty
        ? '—'
        : '${money(d.maxDayDisbursedAmount)} on ${_ordinalDate(d.maxDayDisbursedDate)}';
    return FlowCard(
      header: 'PLEDGE SUMMARY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _reportRow('Pledge Count', '${d.pledgeCount}'),
          _reportRow('Total Amount Disbursed', money(d.totalDisbursedPledges)),
          _reportRow('Pledges Redeemed', '${d.redeemedCount}'),
          _reportRow('Total Amount Redeemed', money(d.totalAmountRedeemed)),
          _reportRow('Max Disbursed in a Day', maxText, isLast: true),
        ],
      ),
    );
  }

  // ── Gold Summary ──────────────────────────────────────────────────────────────

  Widget _goldSummaryCard() {
    final d = _data!;
    final stockText = d.goldStock == null
        ? '—'
        : '${d.goldStock!.toStringAsFixed(2)} g';
    final stockLabel = d.goldStockDate.isEmpty
        ? 'Closing Stock'
        : 'Closing Stock on ${_ordinalDate(d.goldStockDate)}';
    return FlowCard(
      header: 'GOLD SUMMARY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _reportRow('Received', '${d.goldReceived.toStringAsFixed(2)} g'),
          _reportRow('Released', '${d.goldReleased.toStringAsFixed(2)} g'),
          _reportRow(stockLabel, stockText, isLast: true),
        ],
      ),
    );
  }

  // ── Financial Summary ─────────────────────────────────────────────────────────

  Widget _financialCard() {
    final d = _data!;
    return FlowCard(
      header: 'FINANCIAL SUMMARY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _reportRow('Total Disbursed', money(d.totalDisbursedPledges),
              valueColor: FlowColors.red),
          _reportRow('Total Redeemed', money(d.totalAmountRedeemed),
              valueColor: FlowColors.green),
          _reportRow('Interest Earned', money(d.totalInterest), isLast: true),
        ],
      ),
    );
  }

  // ── Expenses ──────────────────────────────────────────────────────────────────

  Widget _expensesCard() {
    final d = _data!;
    return FlowCard(
      header: 'EXPENSES',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...d.expenseBreakdown.map((r) => _reportRow(
                r['name'] as String? ?? 'Uncategorised',
                money((r['s'] as num?)?.toDouble() ?? 0),
              )),
          _reportRow('Total Expenses', money(d.totalExpenses),
              valueColor: FlowColors.orange, isLast: true),
        ],
      ),
    );
  }

  // ── Export (UI only) ──────────────────────────────────────────────────────────

  Widget _exportCard() {
    return FlowCard(
      header: 'EXPORT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _exportBtn(
                    icon: Icons.picture_as_pdf,
                    label: 'EXPORT PDF',
                    color: FlowColors.red),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _exportBtn(
                    icon: Icons.table_chart,
                    label: 'EXPORT EXCEL',
                    color: FlowColors.green),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _exportBtn(
      {required IconData icon,
      required String label,
      required Color color}) {
    return Tooltip(
      message: 'Coming Soon',
      child: OutlinedButton.icon(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Export coming soon'),
              duration: Duration(seconds: 2)),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Widget _reportRow(String label, String value,
      {Color? valueColor, bool isLast = false}) {
    return DetailRow(
      label: label,
      value: value,
      valueColor: valueColor ?? FlowColors.primary,
      isLast: isLast,
    );
  }
}
