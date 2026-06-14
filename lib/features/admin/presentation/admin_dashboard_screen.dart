import 'package:flutter/material.dart';

import '../../../features/pledges/presentation/open_pledge_screen.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../data/admin_repository.dart';
import 'ageing_drill_down_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with WidgetsBindingObserver {
  AdminOverview? _overview;
  TodaySummary? _today;
  List<AgeingBucket> _ageing = [];
  InterestSummary? _interest;
  BusinessHealth? _health;
  bool _loading = true;

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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        AdminRepository.instance.getOverview(),
        AdminRepository.instance.getTodaySummary(),
        AdminRepository.instance.getAgeingBuckets(),
        AdminRepository.instance.getInterestSummary(),
        AdminRepository.instance.getBusinessHealth(),
      ]);
      if (mounted) {
        setState(() {
          _overview = results[0] as AdminOverview;
          _today = results[1] as TodaySummary;
          _ageing = results[2] as List<AgeingBucket>;
          _interest = results[3] as InterestSummary;
          _health = results[4] as BusinessHealth;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Dashboard',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                children: [
                  _overviewGrid(),
                  _todayCard(),
                  _ageingSection(),
                  _interestCard(),
                  _healthSection(),
                ],
              ),
            ),
    );
  }

  // ── Overview 2×2 grid ────────────────────────────────────────────────────────

  Widget _overviewGrid() {
    final ov = _overview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowSectionTitle('Overview'),
        Row(
          children: [
            Expanded(
                child: _overviewTile(
                    icon: Icons.inventory_2,
                    label: 'Open Pledges',
                    value: '${ov?.openPledges ?? 0}',
                    color: FlowColors.primary)),
            const SizedBox(width: 12),
            Expanded(
                child: _overviewTile(
                    icon: Icons.currency_rupee,
                    label: 'Outstanding',
                    value: money(ov?.totalOutstanding ?? 0),
                    color: FlowColors.orange)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _overviewTile(
                    icon: Icons.balance,
                    label: 'Gold Held',
                    value:
                        '${(ov?.totalGoldGrams ?? 0).toStringAsFixed(2)} g',
                    color: const Color(0xFF827717))),
            const SizedBox(width: 12),
            Expanded(
                child: _overviewTile(
                    icon: Icons.people,
                    label: 'Active Customers',
                    value: '${ov?.totalCustomers ?? 0}',
                    color: FlowColors.primaryLight)),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _overviewTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(80), width: 1.5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ],
      ),
    );
  }

  // ── Today's Summary ──────────────────────────────────────────────────────────

  Widget _todayCard() {
    final t = _today;
    final now = DateTime.now();
    final dateLabel =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final net = t?.netCashMovement ?? 0;
    final netColor = net >= 0 ? FlowColors.green : FlowColors.red;
    final netStr = '${net >= 0 ? '+' : ''}${money(net)}';

    return FlowCard(
      backgroundColor: FlowColors.accent,
      header: "TODAY — $dateLabel",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('New Pledges',
              '${t?.newPledgesCount ?? 0}  (${money(t?.newPledgesAmount ?? 0)})'),
          _row('Closed Pledges',
              '${t?.closedPledgesCount ?? 0}  (${money(t?.closedPledgesAmount ?? 0)})'),
          _row('Interest Collected', money(t?.interestCollected ?? 0)),
          _row('Net Cash Movement', netStr, valueColor: netColor,
              isLast: true),
        ],
      ),
    );
  }

  // ── Ageing ───────────────────────────────────────────────────────────────────

  Widget _ageingSection() {
    const colors = [
      FlowColors.green,
      FlowColors.gold,
      FlowColors.orange,
      FlowColors.red,
    ];
    const bgs = [
      FlowColors.greenLight,
      FlowColors.goldLight,
      FlowColors.orangeLight,
      FlowColors.redLight,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowSectionTitle('Pledge Ageing'),
        ..._ageing.asMap().entries.map((e) {
          final i = e.key;
          final b = e.value;
          return _ageingCard(
            bucket: b,
            color: colors[i],
            bgColor: bgs[i],
          );
        }),
      ],
    );
  }

  Widget _ageingCard({
    required AgeingBucket bucket,
    required Color color,
    required Color bgColor,
  }) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AgeingDrillDownScreen(
              bucket: bucket.bucket, label: bucket.label),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 8,
                offset: Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bucket.label.toUpperCase(),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  Text(money(bucket.totalAmount),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${bucket.count}',
                    style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: color)),
                Text('pledges',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black45)),
              ],
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }

  // ── Interest Summary ─────────────────────────────────────────────────────────

  Widget _interestCard() {
    final s = _interest;
    final now = DateTime.now();
    final fyStart = now.month >= 4 ? now.year : now.year - 1;

    return FlowCard(
      header: 'INTEREST SUMMARY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('This Month', money(s?.thisMonth ?? 0)),
          _row('Last Month', money(s?.lastMonth ?? 0)),
          _row('FY $fyStart–${(fyStart + 1).toString().substring(2)}',
              money(s?.thisYear ?? 0),
              isLast: true),
        ],
      ),
    );
  }

  // ── Business Health ──────────────────────────────────────────────────────────

  Widget _healthSection() {
    final h = _health;
    if (h == null) return const SizedBox.shrink();

    final backupBad = h.daysSinceBackup > 1;
    final backupLabel = h.lastBackupAt == null
        ? 'Never'
        : isoToDisplay(h.lastBackupAt!.substring(0, 10));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowSectionTitle('Attention Required'),

        // Backup alert
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: backupBad ? FlowColors.redLight : FlowColors.greenLight,
            border: Border.all(
                color: backupBad ? FlowColors.red : FlowColors.green,
                width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                backupBad ? Icons.cloud_off : Icons.cloud_done,
                color: backupBad ? FlowColors.red : FlowColors.green,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      backupBad
                          ? 'Last backup: $backupLabel — ${h.daysSinceBackup} day(s) ago'
                          : 'Last backup: $backupLabel',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: backupBad
                              ? FlowColors.red
                              : FlowColors.green),
                    ),
                    if (backupBad)
                      const Text('Backup overdue — please backup now',
                          style:
                              TextStyle(fontSize: 13, color: FlowColors.red)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Top 5 largest
        if (h.topLargest.isNotEmpty) ...[
          _subTitle('Top 5 Largest Outstanding'),
          FlowCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: h.topLargest.asMap().entries.map((e) {
                final p = e.value;
                final isLast = e.key == h.topLargest.length - 1;
                return _healthPledgeRow(p, isLast: isLast);
              }).toList(),
            ),
          ),
        ],

        // Top 5 oldest
        if (h.topOldest.isNotEmpty) ...[
          _subTitle('Top 5 Oldest Unredeemed'),
          FlowCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: h.topOldest.asMap().entries.map((e) {
                final p = e.value;
                final isLast = e.key == h.topOldest.length - 1;
                return _healthPledgeRow(p, isLast: isLast);
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _healthPledgeRow(Map<String, dynamic> p, {bool isLast = false}) {
    final days = (p['days_old'] as int?) ?? 0;
    final months = days ~/ 30;
    final ageStr = months > 0 ? '$months mo' : '$days d';
    final name = p['customer_name'] as String?;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PledgeDetailScreen(pledgeId: (p['id'] as int?) ?? 0),
        ),
      ),
      child: Container(
        padding: EdgeInsets.only(
            bottom: isLast ? 0 : 10, top: 4),
        margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: Color(0xFFEEEEEE))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${p['pledge_no']}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: FlowColors.darkText)),
                  if (name != null && name.isNotEmpty)
                    Text(name,
                        style: const TextStyle(
                            fontSize: 13, color: FlowColors.medText)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(money((p['principal_amount'] as num?)?.toDouble() ?? 0),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: FlowColors.primary)),
                Text(ageStr,
                    style: const TextStyle(
                        fontSize: 13, color: FlowColors.orange)),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Colors.black38, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Widget _row(String label, String value,
      {Color? valueColor, bool isLast = false}) {
    return DetailRow(
      label: label,
      value: value,
      valueColor: valueColor ?? FlowColors.primary,
      isLast: isLast,
    );
  }

  Widget _subTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: FlowColors.medText)),
    );
  }
}
