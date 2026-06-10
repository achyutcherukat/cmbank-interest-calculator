import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/widgets/flow_widgets.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _loading = true;
  int _openCount = 0;
  double _totalPrincipal = 0;
  double _monthInterest = 0;
  int _newToday = 0;
  int _closedToday = 0;
  double _collectedToday = 0;
  List<Map<String, dynamic>> _ageing = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final db = await AppDatabase.instance.database;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final monthPrefix = today.substring(0, 7);

      final results = await Future.wait([
        // Q1 — portfolio totals
        db.rawQuery(
            "SELECT COUNT(*) as c, COALESCE(SUM(principal_amount),0) as s "
            "FROM pledges WHERE status='open'"),
        // Q2 — interest collected this calendar month
        db.rawQuery(
            "SELECT COALESCE(SUM(amount),0) as s FROM payments "
            "WHERE paid_at LIKE ?",
            ['$monthPrefix%']),
        // Q3 — new pledges created today
        db.rawQuery(
            "SELECT COUNT(*) as c FROM pledges WHERE start_date=?", [today]),
        // Q4 — pledges closed or renewed today
        db.rawQuery(
            "SELECT COUNT(*) as c FROM pledges "
            "WHERE closure_date=? AND status IN ('closed','renewed','migrated')",
            [today]),
        // Q5 — total cash collected today
        db.rawQuery(
            "SELECT COALESCE(SUM(amount),0) as s FROM payments "
            "WHERE paid_at LIKE ?",
            ['$today%']),
        // Q6 — ageing buckets (single grouped query)
        db.rawQuery("""
          SELECT
            CASE
              WHEN (julianday('now') - julianday(start_date)) <= 180 THEN '0'
              WHEN (julianday('now') - julianday(start_date)) <= 365 THEN '1'
              WHEN (julianday('now') - julianday(start_date)) <= 730 THEN '2'
              ELSE '3'
            END as bucket,
            COUNT(*) as cnt,
            COALESCE(SUM(principal_amount),0) as total
          FROM pledges
          WHERE status='open'
          GROUP BY bucket
        """),
      ]);

      if (mounted) {
        setState(() {
          final q1 = results[0].first;
          _openCount = (q1['c'] as int?) ?? 0;
          _totalPrincipal = (q1['s'] as num?)?.toDouble() ?? 0;
          _monthInterest =
              (results[1].first['s'] as num?)?.toDouble() ?? 0;
          _newToday = (results[2].first['c'] as int?) ?? 0;
          _closedToday = (results[3].first['c'] as int?) ?? 0;
          _collectedToday =
              (results[4].first['s'] as num?)?.toDouble() ?? 0;
          _ageing = results[5]
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _ageingCount(String bucket) {
    final row =
        _ageing.where((r) => r['bucket'] == bucket).firstOrNull;
    return (row?['cnt'] as int?) ?? 0;
  }

  double _ageingTotal(String bucket) {
    final row =
        _ageing.where((r) => r['bucket'] == bucket).firstOrNull;
    return (row?['total'] as num?)?.toDouble() ?? 0;
  }

  String _todayLabel() {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Admin Dashboard',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(16, 14, 16, 40),
                children: [
                  // Admin mode notice
                  const FlowNoticeBox(
                    text:
                        'Admin Mode — Business overview. Use Settings to change rates or PIN.',
                    color: FlowColors.orange,
                    backgroundColor: FlowColors.goldLight,
                    icon: Icons.admin_panel_settings_outlined,
                  ),

                  // Portfolio overview
                  FlowCard(
                    child: Column(
                      children: [
                        const FlowCardTitle('Portfolio Overview'),
                        DetailRow(
                            label: 'Total Open Pledges',
                            value: '$_openCount'),
                        DetailRow(
                            label: 'Total Outstanding',
                            value: money(_totalPrincipal)),
                        DetailRow(
                            label: 'Interest This Month',
                            value: money(_monthInterest),
                            isLast: true),
                      ],
                    ),
                  ),

                  // Today's activity
                  FlowCard(
                    backgroundColor: FlowColors.accent,
                    child: Column(
                      children: [
                        FlowCardTitle('Today — ${_todayLabel()}'),
                        DetailRow(
                            label: 'New Pledges Given',
                            value: '$_newToday'),
                        DetailRow(
                            label: 'Pledges Closed / Renewed',
                            value: '$_closedToday'),
                        DetailRow(
                            label: 'Total Collected',
                            value: money(_collectedToday),
                            isLast: true),
                      ],
                    ),
                  ),

                  // Ageing breakdown
                  const FlowSectionTitle('Open Pledge Ageing'),
                  _ageingCard('0', '0 – 6 Months',
                      FlowColors.green, FlowColors.greenLight),
                  _ageingCard('1', '6 – 12 Months',
                      FlowColors.gold, FlowColors.goldLight),
                  _ageingCard('2', '1 – 2 Years',
                      FlowColors.orange, FlowColors.orangeLight),
                  _ageingCard(
                      '3', '2+ Years', FlowColors.red, FlowColors.redLight),
                ],
              ),
            ),
    );
  }

  Widget _ageingCard(
      String bucket, String label, Color color, Color bgColor) {
    final count = _ageingCount(bucket);
    final total = _ageingTotal(bucket);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  money(total),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              const Text(
                'pledges',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
