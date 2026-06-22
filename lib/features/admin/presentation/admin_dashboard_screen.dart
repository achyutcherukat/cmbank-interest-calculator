import 'package:flutter/material.dart';

import '../../../features/pledges/presentation/open_pledge_screen.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../data/admin_repository.dart';
import 'activity_drill_down_screen.dart';
import 'ageing_drill_down_screen.dart';
import 'gold_account_balance_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with WidgetsBindingObserver {
  AdminOverview? _overview;
  TodayActivity? _today;
  List<AgeingBucket> _ageing = [];
  GoldAccountSummary? _gold;
  BusinessHealth? _health;
  bool _loading = true;
  DateTime _activityDate = DateTime.now();
  DateTime _firstPledgeDate = DateTime(2000);

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
        AdminRepository.instance.getTodayActivity(),
        AdminRepository.instance.getAgeingBuckets(),
        AdminRepository.instance.getGoldAccountSummary(),
        AdminRepository.instance.getBusinessHealth(),
        AdminRepository.instance.getFirstPledgeDate(),
      ]);
      if (mounted) {
        setState(() {
          _overview = results[0] as AdminOverview;
          _today = results[1] as TodayActivity;
          _ageing = results[2] as List<AgeingBucket>;
          _gold = results[3] as GoldAccountSummary;
          _health = results[4] as BusinessHealth;
          _firstPledgeDate = results[5] as DateTime;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadActivity() async {
    final result = await AdminRepository.instance
        .getTodayActivity(date: _activityDate);
    if (mounted) setState(() => _today = result);
  }

  Future<void> _pickActivityDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _activityDate,
      firstDate: _firstPledgeDate,
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _activityDate = picked);
    _loadActivity();
  }

  Widget _activityDateHeader() {
    final today = DateTime.now();
    final isToday = _activityDate.year == today.year &&
        _activityDate.month == today.month &&
        _activityDate.day == today.day;
    final isFirst = !_activityDate.isAfter(_firstPledgeDate);

    final label = isToday
        ? "TODAY'S ACTIVITY"
        : "${_activityDate.day.toString().padLeft(2, '0')}/"
              "${_activityDate.month.toString().padLeft(2, '0')}/"
              "${_activityDate.year}  ACTIVITY";

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: FlowColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.chevron_left,
              color: isFirst ? Colors.transparent : FlowColors.goldRich,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: isFirst
                ? null
                : () {
                    setState(() {
                      _activityDate =
                          _activityDate.subtract(const Duration(days: 1));
                    });
                    _loadActivity();
                  },
          ),
          Expanded(
            child: GestureDetector(
              onTap: _pickActivityDate,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: FlowColors.goldRich,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: isToday ? Colors.transparent : FlowColors.goldRich,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: isToday
                ? null
                : () {
                    setState(() {
                      _activityDate =
                          _activityDate.add(const Duration(days: 1));
                    });
                    _loadActivity();
                  },
          ),
        ],
      ),
    );
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
                  _todayActivitySection(),
                  _goldAccountSection(),
                  _ageingSection(),
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
        _navyHeader('OVERVIEW'),
        _migrationBanner(),
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

  // ── Migration banner ─────────────────────────────────────────────────────────

  Widget _migrationBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10, bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.white, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Data migration in progress',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                SizedBox(height: 4),
                Text(
                  'Dashboard figures reflect only records entered so far. Values will be fully accurate once all physical records have been migrated to this system.',
                  style: TextStyle(fontSize: 13, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Today's Activity (Change 2) ──────────────────────────────────────────────

  Widget _todayActivitySection() {
    final t = _today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _activityDateHeader(),
        Row(
          children: [
            Expanded(
              child: _activityTile(
                icon: Icons.volunteer_activism,
                label: 'New Loans',
                count: '${t?.newCount ?? 0}',
                amount: money(t?.newAmount ?? 0),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ActivityDrillDownScreen(
                      type: ActivityDrillType.newLoans,
                      date: _activityDate,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _activityTile(
                icon: Icons.task_alt,
                label: 'Closed Loans',
                count: '${t?.closedCount ?? 0}',
                amount: money(t?.closedAmount ?? 0),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ActivityDrillDownScreen(
                      type: ActivityDrillType.closedLoans,
                      date: _activityDate,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _activityTile(
                icon: Icons.currency_rupee,
                label: 'Interest Collected',
                count: money(t?.interestCollected ?? 0),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ActivityDrillDownScreen(
                      type: ActivityDrillType.interestCollected,
                      date: _activityDate,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _activityTile(
                icon: Icons.groups,
                label: 'Customers Today',
                count: '${t?.activeCustomers ?? 0}',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ActivityDrillDownScreen(
                      type: ActivityDrillType.customers,
                      date: _activityDate,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  /// White card, navy border (40% opacity), large navy count, gold amount,
  /// gold icon top-right.
  Widget _activityTile({
    required IconData icon,
    required String label,
    required String count,
    String? amount,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FlowColors.primary.withAlpha(102), width: 0.8),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(count,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: FlowColors.primary)),
              ),
              Icon(icon, color: FlowColors.goldRich, size: 26),
            ],
          ),
          if (amount != null) ...[
            const SizedBox(height: 2),
            Text(amount,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: FlowColors.goldRich)),
          ],
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(fontSize: 15, color: FlowColors.medText)),
        ],
      ),
    ),
    );
  }

  // ── Gold Account Balance (Change 4) ──────────────────────────────────────────

  Widget _goldAccountSection() {
    final g = _gold;
    final current = g?.currentBalance ?? 0;
    final yesterday = g?.yesterdayBalance ?? 0;
    final now = DateTime.now();
    final dateLabel =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    IconData trendIcon;
    Color trendColor;
    if (current > yesterday) {
      trendIcon = Icons.arrow_upward;
      trendColor = FlowColors.green;
    } else if (current < yesterday) {
      trendIcon = Icons.arrow_downward;
      trendColor = FlowColors.red;
    } else {
      trendIcon = Icons.remove;
      trendColor = Colors.black38;
    }
    final diff = (current - yesterday).abs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _navyHeader('GOLD ACCOUNT BALANCE'),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const GoldAccountBalanceScreen()),
          ),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: FlowColors.primary.withAlpha(102), width: 0.8),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 6,
                    offset: Offset(0, 2))
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Current Balance',
                          style: TextStyle(
                              fontSize: 15, color: FlowColors.medText)),
                      const SizedBox(height: 4),
                      Text(money(current),
                          style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: FlowColors.primary)),
                      const SizedBox(height: 4),
                      Text('as of $dateLabel',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(trendIcon, color: trendColor, size: 28),
                    if (diff > 0)
                      Text(money(diff),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: trendColor)),
                    const SizedBox(height: 6),
                    const Icon(Icons.chevron_right,
                        color: Colors.black38, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _navyHeader(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FlowColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: FlowColors.goldRich)),
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
        _navyHeader('PLEDGE AGEING'),
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

  // ── Business Health ──────────────────────────────────────────────────────────

  Widget _healthSection() {
    final h = _health;
    if (h == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _navyHeader('ATTENTION REQUIRED'),

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
    final ageStr = formatPledgeAge(days);
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
