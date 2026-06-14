import 'package:flutter/material.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../data/admin_repository.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with WidgetsBindingObserver {
  // Period selection
  _Period _selected = _Period.q1;
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

  static ({String from, String to}) _periodRange(_Period p, DateTime now,
      {DateTime? customFrom, DateTime? customTo}) {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    // Indian FY: April of fyStartYear to March of fyStartYear+1
    final fyStartYear = now.month >= 4 ? now.year : now.year - 1;

    switch (p) {
      case _Period.q1: // Apr–Jun
        return (
          from: fmt(DateTime(fyStartYear, 4, 1)),
          to: fmt(DateTime(fyStartYear, 6, 30)),
        );
      case _Period.q2: // Jul–Sep
        return (
          from: fmt(DateTime(fyStartYear, 7, 1)),
          to: fmt(DateTime(fyStartYear, 9, 30)),
        );
      case _Period.q3: // Oct–Dec
        return (
          from: fmt(DateTime(fyStartYear, 10, 1)),
          to: fmt(DateTime(fyStartYear, 12, 31)),
        );
      case _Period.q4: // Jan–Mar
        return (
          from: fmt(DateTime(fyStartYear + 1, 1, 1)),
          to: fmt(DateTime(fyStartYear + 1, 3, 31)),
        );
      case _Period.yearly:
        return (
          from: fmt(DateTime(fyStartYear, 4, 1)),
          to: fmt(DateTime(fyStartYear + 1, 3, 31)),
        );
      case _Period.custom:
        final f = customFrom ?? DateTime(now.year, 4, 1);
        final t = customTo ?? now;
        return (from: fmt(f), to: fmt(t));
    }
  }

  Future<void> _load() async {
    if (_selected == _Period.custom &&
        (_customFrom == null || _customTo == null)) {
      return;
    }
    setState(() => _loading = true);
    try {
      final range = _periodRange(_selected, DateTime.now(),
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
    final range = _periodRange(_selected, now,
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
          _periodBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _data == null
                    ? Center(
                        child: Text(
                          _selected == _Period.custom
                              ? 'Select a date range to view report'
                              : 'No data',
                          style: const TextStyle(
                              fontSize: 17, color: Colors.black45),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding:
                              const EdgeInsets.fromLTRB(16, 12, 16, 40),
                          children: [
                            _periodChip(),
                            _pledgeSummaryCard(),
                            _goldSummaryCard(),
                            _financialCard(),
                            _exportCard(),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ── Period selector ───────────────────────────────────────────────────────────

  Widget _periodBar() {
    final periods = [
      (_Period.q1, 'Q1'),
      (_Period.q2, 'Q2'),
      (_Period.q3, 'Q3'),
      (_Period.q4, 'Q4'),
      (_Period.yearly, 'Yearly'),
      (_Period.custom, 'Custom'),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: periods.map((pair) {
            final active = _selected == pair.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () async {
                  if (pair.$1 == _Period.custom) {
                    setState(() => _selected = _Period.custom);
                    await _pickCustomRange();
                  } else {
                    setState(() => _selected = pair.$1);
                    _load();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        active ? FlowColors.primary : FlowColors.bg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: active
                            ? FlowColors.primary
                            : FlowColors.primaryLight),
                  ),
                  child: Text(
                    pair.$2,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: active ? Colors.white : FlowColors.primary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
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

  Widget _pledgeSummaryCard() {
    final d = _data!;
    return FlowCard(
      header: 'PLEDGE SUMMARY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _reportRow('New Pledges',
              '${d.newPledgesCount}  (${money(d.newPledgesAmount)})'),
          _reportRow('Redeemed / Closed',
              '${d.closedCount}  (${money(d.closedAmount)})'),
          _reportRow('Renewed',
              '${d.renewedCount}  (${money(d.renewedAmount)})'),
          _reportRow('Auctioned', '0  (—)'),
          _reportRow('Closing Open',
              '${d.closingOpenCount}  (${money(d.closingOpenAmount)})',
              isLast: true),
        ],
      ),
    );
  }

  // ── Gold Summary ──────────────────────────────────────────────────────────────

  Widget _goldSummaryCard() {
    final d = _data!;
    return FlowCard(
      header: 'GOLD SUMMARY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _reportRow('Received', '${d.goldReceived.toStringAsFixed(2)} g'),
          _reportRow('Released', '${d.goldReleased.toStringAsFixed(2)} g'),
          _reportRow('Auctioned', '0.00 g'),
          _reportRow('Closing Stock', '${d.goldStock.toStringAsFixed(2)} g',
              isLast: d.purityBreakdown.isEmpty),
          if (d.purityBreakdown.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('BY PURITY',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black45,
                    letterSpacing: 0.8)),
            const SizedBox(height: 6),
            ...d.purityBreakdown.asMap().entries.map((e) {
              final r = e.value;
              final isLast = e.key == d.purityBreakdown.length - 1;
              final grams =
                  (r['g'] as num?)?.toDouble() ?? 0;
              final count = (r['c'] as int?) ?? 0;
              return _reportRow(
                r['purity'] as String? ?? '—',
                '${grams.toStringAsFixed(2)} g  ($count pledges)',
                isLast: isLast,
              );
            }),
          ],
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
          _reportRow('Total Disbursed', money(d.totalDisbursed),
              valueColor: FlowColors.red),
          _reportRow('Total Collected', money(d.totalCollected),
              valueColor: FlowColors.green),
          _reportRow('Interest Earned', money(d.totalInterest)),
          _reportRow('Total Expenses', money(d.totalExpenses),
              valueColor: FlowColors.orange,
              isLast: d.expenseBreakdown.isEmpty),
          if (d.expenseBreakdown.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('EXPENSES BY CATEGORY',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black45,
                    letterSpacing: 0.8)),
            const SizedBox(height: 6),
            ...d.expenseBreakdown.asMap().entries.map((e) {
              final r = e.value;
              final isLast = e.key == d.expenseBreakdown.length - 1;
              return _reportRow(
                r['name'] as String? ?? 'Uncategorised',
                money((r['s'] as num?)?.toDouble() ?? 0),
                isLast: isLast && d.netPosition == 0,
              );
            }),
          ],
          const SizedBox(height: 10),
          const Divider(color: Color(0xFFEEEEEE)),
          const SizedBox(height: 10),
          _reportRow(
            'Net Position',
            money(d.netPosition),
            valueColor:
                d.netPosition >= 0 ? FlowColors.green : FlowColors.red,
            isLast: true,
          ),
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

enum _Period { q1, q2, q3, q4, yearly, custom }
