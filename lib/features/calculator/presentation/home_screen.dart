import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../accounts/presentation/daily_accounts_screen.dart';
import '../../customers/presentation/customer_list_screen.dart';
import '../../gold_stock/presentation/gold_stock_screen.dart';
import '../../pledges/presentation/closed_pledges_screen.dart';
import '../../pledges/presentation/load_existing_pledge_screen.dart';
import '../../pledges/presentation/new_pledge_screen.dart';
import '../../pledges/presentation/open_pledge_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../admin/presentation/admin_screen.dart';
import 'calculator_screen.dart';

// ─── Brand colours ────────────────────────────────────────────────────────────
const _navy     = CMBColors.navy;
const _gold     = CMBColors.goldRich;
const _bg       = CMBColors.pageBackground;
const _tPrimary = CMBColors.textOnLight;
const _tSec     = Color(0xFF999999);
const _gdBorder = CMBColors.dividerOnCard;
const _gdBg8    = Color(0x14D4A843);   // gold 8% tint — no CMBColors equivalent

// ─── HomeScreen ───────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onLock});
  final VoidCallback? onLock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _settings    = AppSettingsRepository();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  double  _goldRate   = 0;
  double  _pledgeRate = 0;
  double  _todayCash  = 0;
  double  _todayUpi   = 0;
  String? _lastBackupAt;

  bool _showLowStorageWarning = false;
  bool _showDriveLowWarning   = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadSettings(),
      _loadTodayAccounts(),
      _loadBackupStatus(),
    ]);
  }

  // ─── Data loaders ──────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final gr = await _settings.getString('gold_rate');
    final pr = await _settings.getString('default_pledge_rate');
    if (mounted) {
      setState(() {
        _goldRate   = double.tryParse(gr ?? '') ?? 0;
        _pledgeRate = double.tryParse(pr ?? '') ?? 0;
      });
    }
  }

  Future<void> _loadTodayAccounts() async {
    final db        = await AppDatabase.instance.database;
    final now       = DateTime.now();
    final today     = _isoDate(now);
    final yesterday = _isoDate(now.subtract(const Duration(days: 1)));

    double q(List<Map<String, dynamic>> r) => (r.first['s'] as num).toDouble();

    // Opening: yesterday's closing from daily_balance, else rebuild
    final prev = await db.query('daily_balance',
        where: 'business_date = ?', whereArgs: [yesterday], limit: 1);

    double opCash, opUpi;
    if (prev.isNotEmpty) {
      opCash = (prev.first['closing_cash'] as num).toDouble();
      opUpi  = (prev.first['closing_upi']  as num).toDouble();
    } else {
      opCash = double.tryParse(
              await _settings.getString('opening_cash') ?? '') ?? 0;
      opUpi  = double.tryParse(
              await _settings.getString('opening_upi') ?? '') ?? 0;

      final ci = await db.rawQuery(
          'SELECT COALESCE(SUM(cash_amount),0) AS s FROM payments WHERE paid_at < ?',
          [today]);
      final ui = await db.rawQuery(
          'SELECT COALESCE(SUM(upi_amount),0) AS s FROM payments WHERE paid_at < ?',
          [today]);
      final co = await db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
          "WHERE type IN ('loan_disbursed','expense') AND mode='cash' AND transaction_date < ?",
          [today]);
      final uo = await db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
          "WHERE type IN ('loan_disbursed','expense') AND mode='upi' AND transaction_date < ?",
          [today]);
      final ca = await db.rawQuery(
          "SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE -amount END),0) AS s "
          "FROM transactions WHERE type='adjustment' AND mode='cash' AND transaction_date < ?",
          [today]);
      final ua = await db.rawQuery(
          "SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE -amount END),0) AS s "
          "FROM transactions WHERE type='adjustment' AND mode='upi' AND transaction_date < ?",
          [today]);

      opCash += q(ci) - q(co) + q(ca);
      opUpi  += q(ui) - q(uo) + q(ua);
    }

    // Today's movements
    final cashIn = await db.rawQuery("""
      SELECT COALESCE(SUM(
        CASE WHEN p.cash_amount IS NOT NULL AND (p.cash_amount > 0 OR p.upi_amount > 0)
             THEN p.cash_amount
             WHEN t.mode='cash' THEN t.amount ELSE 0 END
      ), 0) AS s
      FROM transactions t LEFT JOIN payments p ON p.id = t.payment_id
      WHERE t.type='payment_received' AND t.transaction_date=?""", [today]);

    final upiIn = await db.rawQuery("""
      SELECT COALESCE(SUM(
        CASE WHEN p.cash_amount IS NOT NULL AND (p.cash_amount > 0 OR p.upi_amount > 0)
             THEN p.upi_amount
             WHEN t.mode='upi' THEN t.amount ELSE 0 END
      ), 0) AS s
      FROM transactions t LEFT JOIN payments p ON p.id = t.payment_id
      WHERE t.type='payment_received' AND t.transaction_date=?""", [today]);

    final cashOut = await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
        "WHERE type IN ('loan_disbursed','expense') AND mode='cash' AND transaction_date=?",
        [today]);
    final upiOut = await db.rawQuery(
        "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
        "WHERE type IN ('loan_disbursed','expense') AND mode='upi' AND transaction_date=?",
        [today]);
    final adjCash = await db.rawQuery(
        "SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE -amount END),0) AS s "
        "FROM transactions WHERE type='adjustment' AND mode='cash' AND transaction_date=?",
        [today]);
    final adjUpi = await db.rawQuery(
        "SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE -amount END),0) AS s "
        "FROM transactions WHERE type='adjustment' AND mode='upi' AND transaction_date=?",
        [today]);

    if (mounted) {
      setState(() {
        _todayCash = opCash + q(cashIn) - q(cashOut) + q(adjCash);
        _todayUpi  = opUpi  + q(upiIn)  - q(upiOut)  + q(adjUpi);
      });
    }
  }

  Future<void> _loadBackupStatus() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('backup_log',
        where: 'status = ?',
        whereArgs: ['success'],
        orderBy: 'created_at DESC',
        limit: 1);
    if (mounted) {
      setState(() => _lastBackupAt =
          rows.isNotEmpty ? rows.first['created_at'] as String? : null);
    }
  }

  // ─── Rate edit bottom sheet ───────────────────────────────────────────────

  void _showRateSheet(String title, double current, String settingsKey) {
    final ctrl = TextEditingController(
        text: current > 0 ? _fmtIndianStr(current.round()) : '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 300),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 22),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _navy)),
            const SizedBox(height: 18),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d,]')),
                _IndianNumberFormatter(),
              ],
              style: const TextStyle(
                  fontSize: 20, color: _navy, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: const TextStyle(
                    fontSize: 20,
                    color: _navy,
                    fontWeight: FontWeight.w600),
                labelText: 'Amount',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _gold, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _tSec,
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(color: Color(0xFFCCCCCC)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('CANCEL',
                        style: TextStyle(
                            fontSize: 16, letterSpacing: 0.5)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final raw = ctrl.text.replaceAll(',', '');
                      final val = double.tryParse(raw);
                      if (val == null || val <= 0) return;
                      Navigator.of(ctx).pop();
                      await _settings.upsertMany({
                        settingsKey: (
                          value: val.toStringAsFixed(2),
                          type: 'double'
                        ),
                      });
                      if (mounted) {
                        setState(() {
                          if (settingsKey == 'gold_rate') {
                            _goldRate = val;
                          } else {
                            _pledgeRate = val;
                          }
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('UPDATE',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bg,
      drawer: _buildDrawer(),
      appBar: AppBar(
        toolbarHeight: 76,
        automaticallyImplyLeading: false,
        backgroundColor: _navy,
        elevation: 0,
        leadingWidth: 56,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: _gold, size: 28),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          tooltip: 'Menu',
        ),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/cmb_logo.png',
              height: 52,
              width: 52,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.shield, color: _gold, size: 52),
            ),
            const SizedBox(width: 10),
            const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'CM Bank',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                    height: 1.1,
                  ),
                ),
                
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline, color: _gold, size: 26),
            onPressed: widget.onLock,
            tooltip: 'Lock app',
          ),
          IconButton(
            icon:
                const Icon(Icons.settings_outlined, color: _gold, size: 26),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Gold gradient divider below app bar
          Container(
            height: 1.5,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, _gold, Colors.transparent],
              ),
            ),
          ),
          // Warning banners
          if (_showLowStorageWarning)
            _warningBanner(
              message:
                  '⚠ Low storage: Free up space on your device.',
              color: CMBColors.warningRed,
              onDismiss: () =>
                  setState(() => _showLowStorageWarning = false),
            ),
          if (_showDriveLowWarning)
            _warningBanner(
              message: '⚠ Google Drive storage low',
              color: CMBColors.warningOrange,
              onDismiss: () =>
                  setState(() => _showDriveLowWarning = false),
            ),
          // Main scrollable content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAll,
              color: _gold,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                child: Column(
                  children: [
                    _ratesCard(),
                    const SizedBox(height: 13),
                    _actionCard(
                      iconData: Icons.add_circle_outline,
                      iconColor: _gold,
                      iconBg: const Color(0xFFFDF5E0),
                      borderAccent: _gold,
                      title: 'New pledge',
                      subtitle: 'Create a new gold loan',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NewPledgeScreen()),
                      ),
                    ),
                    const SizedBox(height: 13),
                    _actionCard(
                      iconData: Icons.search,
                      iconColor: const Color(0xFF2E7D32),
                      iconBg: const Color(0xFFEDF7ED),
                      borderAccent: const Color(0xFF2E7D32),
                      title: 'Open pledge',
                      subtitle: 'Search and manage active pledges',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const OpenPledgeScreen()),
                      ),
                    ),
                    const SizedBox(height: 13),
                    _actionCard(
                      iconData: Icons.calculate_outlined,
                      iconColor: _navy,
                      iconBg: const Color(0xFFEEF0F8),
                      borderAccent: _navy,
                      title: 'Interest calculator',
                      subtitle: 'Calculate and save interest',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CalculatorScreen()),
                      ),
                    ),
                    const SizedBox(height: 13),
                    _accountsCard(),
                    const SizedBox(height: 13),
                    _backupBar(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Warning banner ───────────────────────────────────────────────────────

  Widget _warningBanner({
    required String message,
    required Color color,
    required VoidCallback onDismiss,
  }) {
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Rates card ──────────────────────────────────────────────────────────

  Widget _ratesCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gdBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("TODAY'S RATES",
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _gold,
                  letterSpacing: 1.2)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _rateCol(
                  iconData: Icons.monetization_on,
                  label: 'Gold rate',
                  value: _goldRate,
                  onEdit: () => _showRateSheet(
                      'Edit Gold Rate', _goldRate, 'gold_rate'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  width: 1,
                  height: 52,
                  color: const Color(0x40D4A843),
                ),
              ),
              Expanded(
                child: _rateCol(
                  iconData: Icons.account_balance,
                  label: 'Pledge rate',
                  value: _pledgeRate,
                  onEdit: () => _showRateSheet('Edit Pledge Rate',
                      _pledgeRate, 'default_pledge_rate'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rateCol({
    required IconData iconData,
    required String label,
    required double value,
    required VoidCallback onEdit,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _navy,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(iconData, color: _gold, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 12, color: _tSec)),
              const SizedBox(height: 2),
              Text(
                value > 0 ? '${_fmtRupee(value)}/g' : 'Not set',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: value > 0 ? _tPrimary : Colors.black38,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: onEdit,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.edit, color: _gold, size: 18),
          ),
        ),
      ],
    );
  }

  // ─── Action card ─────────────────────────────────────────────────────────

  Widget _actionCard({
    required IconData iconData,
    required Color iconColor,
    required Color iconBg,
    required Color borderAccent,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _gdBorder, width: 1.2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
                border: Border(
                    left: BorderSide(color: borderAccent, width: 4)),
              ),
              child: Icon(iconData, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _tPrimary)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: _tSec)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _gold, size: 22),
          ],
        ),
      ),
    );
  }

  // ─── Today's Accounts card ───────────────────────────────────────────────

  Widget _accountsCard() {
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year}';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DailyAccountsScreen()),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _navy,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CMBColors.borderOnNavy, width: 0.5),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text("TODAY'S ACCOUNTS",
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _gold,
                        letterSpacing: 1.2)),
                const Spacer(),
                Text(dateStr,
                    style: const TextStyle(
                        fontSize: 11, color: CMBColors.textOnNavyMuted)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _accountCol(
                    icon: Icons.account_balance_wallet,
                    label: 'Cash',
                    value: _todayCash,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _accountCol(
                    icon: Icons.phone_android,
                    label: 'UPI',
                    value: _todayUpi,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                '→ Tap to open daily accounts',
                style: TextStyle(
                    fontSize: 12,
                    color: _gold.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountCol({
    required IconData icon,
    required String label,
    required double value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _gdBg8,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CMBColors.borderOnNavy, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _gold, size: 16),
              const SizedBox(width: 5),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: CMBColors.textOnNavySmall)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _fmtRupee(value),
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: CMBColors.textOnNavyLarge,
                height: 1.0),
          ),
        ],
      ),
    );
  }

  // ─── Backup status bar ───────────────────────────────────────────────────

  Widget _backupBar() {
    final overdue = _lastBackupAt == null ||
        DateTime.now()
                .difference(
                    DateTime.tryParse(_lastBackupAt!) ?? DateTime(2000))
                .inHours >
            24;
    final dbDot   = overdue ? Colors.red : Colors.green;
    final dbColor = overdue ? Colors.red : const Color(0xFF388E3C);
    final dbLabel = _lastBackupAt != null
        ? 'Last backup: ${_fmtBackupTime(_lastBackupAt!)}'
        : 'Never backed up';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminScreen()),
      ),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gdBorder, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: dbDot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(dbLabel,
                        style: TextStyle(
                            fontSize: 11,
                            color: dbColor,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 18,
              color: const Color(0xFFE0E0E0),
              margin: const EdgeInsets.symmetric(horizontal: 10),
            ),
            const Row(
              children: [
                Icon(Icons.cloud_done, color: Colors.green, size: 14),
                SizedBox(width: 5),
                Text('Photos synced',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Drawer ──────────────────────────────────────────────────────────────

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          Container(
            color: _navy,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 20),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/cmb_logo.png',
                  height: 52,
                  width: 52,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.shield, color: _gold, size: 52),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CM Bank',
                        style: TextStyle(
                            color: _gold,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                    Text('Gold Loan Management',
                        style: TextStyle(
                            color: CMBColors.textOnNavyMuted, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _drawerItem(Icons.upload_file, 'Load Existing Pledge',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const LoadExistingPledgeScreen()))),
                _drawerItem(Icons.archive, 'Closed Pledges',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const ClosedPledgesScreen()))),
                _drawerItem(
                    Icons.account_balance_wallet,
                    'Daily Accounts',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const DailyAccountsScreen()))),
                _drawerItem(Icons.balance, 'Gold Stock Register',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const GoldStockScreen()))),
                _drawerItem(Icons.people, 'Customers',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const CustomerListScreen()))),
                _drawerItem(Icons.admin_panel_settings, 'Admin Area',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AdminScreen()))),
                const Divider(height: 24),
                _drawerItem(Icons.settings, 'Settings',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()))),
                ListTile(
                  leading: const Icon(Icons.lock, color: Colors.red),
                  title: const Text('Lock App',
                      style: TextStyle(
                          fontSize: 18, color: Colors.red)),
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
      leading: Icon(icon, color: _gold),
      title: Text(label,
          style: const TextStyle(fontSize: 18, color: _tPrimary)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}

// ─── Indian number text formatter ─────────────────────────────────────────────

class _IndianNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(',', '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final n = int.tryParse(digits);
    if (n == null) return oldValue;
    final formatted = _fmtIndianStr(n);
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _isoDate(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-'
    '${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';

String _fmtIndianStr(int n) {
  if (n == 0) return '0';
  final s = n.toString();
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  final rest  = s.substring(0, s.length - 3);
  final buf   = StringBuffer();
  for (int i = 0; i < rest.length; i++) {
    if (i > 0 && (rest.length - i) % 2 == 0) buf.write(',');
    buf.write(rest[i]);
  }
  return '$buf,$last3';
}

String _fmtRupee(double amount) => '₹${_fmtIndianStr(amount.round().abs())}';

String _fmtBackupTime(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    final d  = '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    return '$d ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}
