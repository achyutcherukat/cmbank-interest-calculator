import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/gold_rate_service.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../accounts/presentation/daily_accounts_screen.dart';
import '../../pledges/presentation/closed_pledges_screen.dart';
import '../../pledges/presentation/new_pledge_screen.dart';
import '../../pledges/presentation/open_pledge_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../admin/presentation/admin_screen.dart';
import 'calculator_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onLock});

  final VoidCallback? onLock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _settingsRepository = AppSettingsRepository();

  int _openPledgeCount = 0;
  double _todayCollections = 0.0;
  Map<String, dynamic>? _goldRates;
  bool _loadingRates = true;
  bool _fetchingLive = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadGoldRates(), _loadSummary()]);
  }

  Future<void> _loadGoldRates() async {
    try {
      final db = await AppDatabase.instance.database;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final rows = await db.query(
        'gold_rates',
        where: 'rate_date = ?',
        whereArgs: [today],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (mounted) {
        setState(() {
          _goldRates = rows.isNotEmpty ? rows.first : null;
          _loadingRates = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRates = false);
    }
  }

  Future<void> _loadSummary() async {
    try {
      final db = await AppDatabase.instance.database;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      final countResult = await db.rawQuery(
          "SELECT COUNT(*) as c FROM pledges WHERE status = 'open'");
      final payResult = await db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) as s FROM payments WHERE paid_at LIKE ?",
          ['$today%']);

      if (mounted) {
        setState(() {
          _openPledgeCount = (countResult.first['c'] as int?) ?? 0;
          _todayCollections =
              (payResult.first['s'] as num?)?.toDouble() ?? 0.0;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchLiveRates() async {
    setState(() => _fetchingLive = true);
    try {
      final result = await GoldRateService.fetchLiveRates();
      final db = await AppDatabase.instance.database;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      // Reuse existing pledge_rate for today if already set, else default 75% of 22K
      double pledgeRate = result.rate22k * 0.75;
      final existing = await db.query(
        'gold_rates',
        where: 'rate_date = ?',
        whereArgs: [today],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final pr = (existing.first['pledge_rate'] as num?)?.toDouble() ?? 0;
        if (pr > 0) pledgeRate = pr;
      }

      await db.insert('gold_rates', {
        'rate_date': today,
        'rate_24k': result.rate24k,
        'rate_22k': result.rate22k,
        'pledge_rate': pledgeRate,
        'source': 'api',
        'is_manual': 0,
        'created_by': null,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _loadGoldRates();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Live gold rates updated. Verify pledge rate.'),
            backgroundColor: FlowColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not fetch live rates: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingLive = false);
    }
  }

  void _showGoldRateDialog() {
    final rate22kCtrl = TextEditingController(
        text: _goldRates != null
            ? (_goldRates!['rate_22k'] as double).toStringAsFixed(0)
            : '');
    final rate24kCtrl = TextEditingController(
        text: _goldRates != null
            ? (_goldRates!['rate_24k'] as double).toStringAsFixed(0)
            : '');
    final pledgeRateCtrl = TextEditingController(
        text: _goldRates != null
            ? (_goldRates!['pledge_rate'] as double).toStringAsFixed(0)
            : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Today's Gold Rates",
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _rateField(rate22kCtrl, '22K Rate (₹/gram)'),
            const SizedBox(height: 12),
            _rateField(rate24kCtrl, '24K Rate (₹/gram)'),
            const SizedBox(height: 12),
            _rateField(pledgeRateCtrl, 'Pledge Rate (₹/gram)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(fontSize: 17, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final r22 = double.tryParse(rate22kCtrl.text.trim());
              final r24 = double.tryParse(rate24kCtrl.text.trim());
              final rp = double.tryParse(pledgeRateCtrl.text.trim());
              if (r22 == null || r24 == null || rp == null) return;
              final db = await AppDatabase.instance.database;
              final today =
                  DateTime.now().toIso8601String().substring(0, 10);
              await db.insert('gold_rates', {
                'rate_date': today,
                'rate_22k': r22,
                'rate_24k': r24,
                'pledge_rate': rp,
                'source': 'manual',
                'is_manual': 1,
                'created_by': null,
                'created_at': DateTime.now().toIso8601String(),
              });
              await _settingsRepository.upsertMany({
                'default_pledge_rate':
                    (value: rp.toStringAsFixed(2), type: 'double'),
              });
              _loadGoldRates();
            },
            child: const Text('Save',
                style: TextStyle(fontSize: 17, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _rateField(TextEditingController ctrl, String label) => TextField(
        controller: ctrl,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
        ],
        style: const TextStyle(fontSize: 20),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 17),
          prefixText: '₹ ',
        ),
      );

  void _showComingSoon(String module) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$module coming soon.'),
        backgroundColor: FlowColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        iconTheme: const IconThemeData(color: Colors.white, size: 30),
        title: const Text('CM Bank',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: Colors.white, size: 28),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
          children: [
            _goldRateCard(),
            _pledgeRateCard(),
            const SizedBox(height: 6),
            _bigButton(
              icon: Icons.add_box_outlined,
              label: 'NEW PLEDGE',
              subtitle: 'Create a new gold loan',
              color: FlowColors.primary,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NewPledgeScreen()),
                );
                _loadSummary();
              },
            ),
            const SizedBox(height: 12),
            _bigButton(
              icon: Icons.search,
              label: 'OPEN PLEDGE',
              subtitle: 'Search & manage active pledges',
              color: FlowColors.primaryLight,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const OpenPledgeScreen()),
                );
                _loadSummary();
              },
            ),
            const SizedBox(height: 12),
            _bigButton(
              icon: Icons.calculate_outlined,
              label: 'INTEREST CALCULATOR',
              subtitle: 'Calculate & close pledge',
              color: const Color(0xFF283593),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CalculatorScreen()),
              ),
            ),
            const SizedBox(height: 18),
            _summaryChips(),
          ],
        ),
      ),
    );
  }

  // ─── Gold Rate Card ─────────────────────────────────────────────────────────

  Widget _sourceChip(String source) {
    final isApi = source == 'api';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isApi ? FlowColors.greenLight : FlowColors.goldLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isApi ? 'LIVE' : 'MANUAL',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: isApi ? FlowColors.green : FlowColors.gold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _goldRateCard() {
    if (_loadingRates) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: FlowColors.goldLight,
          border: Border.all(color: FlowColors.gold, width: 1.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))
          ],
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: FlowColors.orange),
          ),
        ),
      );
    }

    final has = _goldRates != null;
    final r22 = has ? (_goldRates!['rate_22k'] as double) : 0.0;
    final r24 = has ? (_goldRates!['rate_24k'] as double) : 0.0;

    return GestureDetector(
      onTap: _showGoldRateDialog,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: has ? FlowColors.goldLight : FlowColors.orangeLight,
          border: Border.all(
              color: has ? FlowColors.gold : FlowColors.orange, width: 1.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  has ? Icons.trending_up : Icons.warning_amber_outlined,
                  color: FlowColors.orange,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    has ? 'GOLD RATES TODAY' : 'GOLD RATES NOT SET TODAY',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: FlowColors.orange,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (has)
                  _sourceChip(_goldRates!['source'] as String? ?? 'manual'),
                const SizedBox(width: 4),
                _fetchingLive
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: FlowColors.orange),
                      )
                    : IconButton(
                        icon: const Icon(Icons.refresh,
                            color: FlowColors.orange, size: 22),
                        tooltip: 'Fetch live rate',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _fetchLiveRates,
                      ),
              ],
            ),
            if (has) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('24 Karat',
                            style: TextStyle(
                                fontSize: 13,
                                color: FlowColors.medText)),
                        Text(
                          '₹${r24.toStringAsFixed(0)}/g',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: FlowColors.darkText),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1, height: 36, color: const Color(0xFFF0C030)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('22 Karat',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: FlowColors.medText)),
                          Text(
                            '₹${r22.toStringAsFixed(0)}/g',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: FlowColors.darkText),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Pledge Rate Card ───────────────────────────────────────────────────────

  Widget _pledgeRateCard() {
    final has = _goldRates != null;
    final rp = has ? (_goldRates!['pledge_rate'] as double) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: FlowColors.primaryLight, width: 1.5),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.monetization_on_outlined,
              color: FlowColors.primary, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "TODAY'S PLEDGE RATE",
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.black45,
                      letterSpacing: 1.0),
                ),
                Text(
                  has ? '₹${rp.toStringAsFixed(0)}/g' : 'Not set today',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: has ? FlowColors.primary : Colors.black38),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _showGoldRateDialog,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit', style: TextStyle(fontSize: 15)),
            style: TextButton.styleFrom(
              foregroundColor: FlowColors.primary,
              backgroundColor: FlowColors.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Big Action Button ──────────────────────────────────────────────────────

  Widget _bigButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 76,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerLeft,
          elevation: 2,
        ),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 14),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Colors.white70)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Summary Chips ──────────────────────────────────────────────────────────

  Widget _summaryChips() {
    return Row(
      children: [
        Expanded(
          child: _summaryChip(
            icon: Icons.folder_open_outlined,
            label: '$_openPledgeCount Open Pledges',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _summaryChip(
            icon: Icons.payments_outlined,
            label: '${money(_todayCollections)} Today',
          ),
        ),
      ],
    );
  }

  Widget _summaryChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: FlowColors.primaryLight, width: 1.2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 1))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: FlowColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: FlowColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Drawer ─────────────────────────────────────────────────────────────────

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          Container(
            color: FlowColors.primary,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('CM Bank',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Gold Loan Management',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _drawerItem(Icons.file_open_outlined, 'Load Existing Pledge',
                    () => _showComingSoon('Load Existing Pledge')),
                _drawerItem(Icons.folder_outlined, 'Closed Pledges', () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ClosedPledgesScreen()),
                  );
                }),
                _drawerItem(
                    Icons.account_balance_wallet_outlined, 'Daily Accounts',
                    () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DailyAccountsScreen()),
                  );
                }),
                _drawerItem(
                    Icons.admin_panel_settings_outlined, 'Admin Area',
                    () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const AdminScreen()));
                    }),
                const Divider(height: 24),
                _drawerItem(Icons.settings_outlined, 'Settings', () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SettingsScreen()),
                  );
                }),
                ListTile(
                  leading:
                      const Icon(Icons.lock_outline, color: Colors.red),
                  title: const Text('Lock App',
                      style: TextStyle(fontSize: 18, color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onLock?.call();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem(
      IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: FlowColors.primary),
      title: Text(label, style: const TextStyle(fontSize: 18)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}
