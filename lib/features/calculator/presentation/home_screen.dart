import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_branding.dart';
import '../../../app/theme.dart';
import '../../../core/services/backup_status_service.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../core/services/photo_backup_service.dart';
import '../../accounts/data/daily_balance_repository.dart';
import '../../accounts/presentation/daily_accounts_screen.dart';
import '../../gold_stock/data/gold_rates_repository.dart';
import '../../customers/presentation/customer_list_screen.dart';
import '../../gold_stock/presentation/gold_stock_screen.dart';
import '../../pledges/presentation/closed_pledges_screen.dart';
import '../../pledges/presentation/load_existing_pledge_screen.dart';
import '../../pledges/presentation/new_pledge_screen.dart';
import '../../pledges/presentation/open_pledge_screen.dart';
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  double  _goldRate   = 0;
  double  _pledgeRate = 0;
  double  _todayCash  = 0;
  double  _todayUpi   = 0;

  BackupStatusSnapshot? _status;
  bool _lowStorageDismissed = false;
  bool _driveLowDismissed   = false;

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
    if (PhotoBackupService.instance.needsRestore) {
      PhotoBackupService.instance.needsRestore = false;
      final result = await PhotoBackupService.instance.restoreMissingPhotos();
      if (mounted && result.failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: CMBColors.warningOrange,
          content: Text(
            'Photo restore: ${result.restored}/${result.found} downloaded. '
            '${result.failed} failed — tap "Restore Photos" in Admin Settings to retry.',
          ),
          duration: const Duration(seconds: 6),
        ));
      } else if (mounted && result.restored > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: CMBColors.navy,
          content: Text(
            '${result.restored} photo${result.restored == 1 ? '' : 's'} restored successfully.',
          ),
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  // ─── Data loaders ──────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final rates = await GoldRatesRepository.instance.getCurrentRates();
    if (mounted) {
      setState(() {
        _goldRate   = rates?.goldRate ?? 0;
        _pledgeRate = rates?.pledgeRate ?? 0;
      });
    }
  }

  Future<void> _loadTodayAccounts() async {
    final today = _isoDate(DateTime.now());
    final totals =
        await DailyBalanceRepository.instance.calculateTotalsForDate(today);
    if (mounted) {
      setState(() {
        _todayCash = totals.closingCash;
        _todayUpi  = totals.closingUpi;
      });
    }
  }

  Future<void> _loadBackupStatus() async {
    final status = await BackupStatusService.instance.load();
    if (mounted) setState(() => _status = status);
  }

  // ─── Rate edit bottom sheet ───────────────────────────────────────────────

  void _showRateSheet(String title, double current, String settingsKey) {
    final ctrl = TextEditingController(
        text: current > 0 ? formatIndian(current.round().toString()) : '');
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
                IndianNumberFormatter(),
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
                      final isGold = settingsKey == 'gold_rate';
                      // Append a new gold_rates row (rates are never updated
                      // in place); keep the other rate at its current value.
                      await GoldRatesRepository.instance.saveRates(
                        goldRate: isGold ? val : _goldRate,
                        pledgeRate: isGold ? _pledgeRate : val,
                      );
                      if (mounted) {
                        setState(() {
                          if (isGold) {
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
        toolbarHeight: 90,
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
        title: Image.asset(
          AppBranding.logoAsset,
          height: 72,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.shield, color: _gold, size: 72),
        ),
        actions: const [
          SizedBox(width: 56),
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
          // Warning banners (above rates card)
          ..._buildWarningBanners(),
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
                      title: 'New Loan',
                      subtitle: 'Create a new gold loan',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NewPledgeScreen()),
                      ).then((_) => _loadTodayAccounts()),
                    ),
                    const SizedBox(height: 13),
                    _actionCard(
                      iconData: Icons.search,
                      iconColor: const Color(0xFF2E7D32),
                      iconBg: const Color(0xFFEDF7ED),
                      borderAccent: const Color(0xFF2E7D32),
                      title: 'Active Loans',
                      subtitle: 'Search and manage active pledges',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const OpenPledgeScreen()),
                      ).then((_) => _loadTodayAccounts()),
                    ),
                    const SizedBox(height: 13),
                    _actionCard(
                      iconData: Icons.calculate_outlined,
                      iconColor: _navy,
                      iconBg: const Color(0xFFEEF0F8),
                      borderAccent: _navy,
                      title: 'Interest Calculator',
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
          _photoRestoreBanner(),
        ],
      ),
    );
  }

  // ─── Photo restore banner (Part 5B) ───────────────────────────────────────

  Widget _photoRestoreBanner() {
    return ValueListenableBuilder<PhotoRestoreProgress?>(
      valueListenable: PhotoBackupService.instance.restoreProgress,
      builder: (context, progress, child) {
        if (progress == null) return const SizedBox.shrink();
        final label = progress.total > 0
            ? 'Restoring photos… ${progress.done} of ${progress.total} complete'
            : 'Restoring photos in background…';
        return Container(
          width: double.infinity,
          color: _navy,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _gold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: CMBColors.textOnNavySmall, fontSize: 12.5)),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Warning banners ──────────────────────────────────────────────────────

  List<Widget> _buildWarningBanners() {
    final s = _status;
    if (s == null) return const [];
    final banners = <Widget>[];

    // Device storage: critical (red, non-dismissable) overrides low (yellow).
    if (s.deviceStorageCritical) {
      banners.add(_warningBanner(
        message:
            '⚠ Critical: Very low storage. App may stop working correctly.',
        color: CMBColors.warningRed,
        onDismiss: null,
      ));
    } else if (s.deviceStorageLow && !_lowStorageDismissed) {
      final mb = s.deviceFreeMb?.round() ?? 0;
      banners.add(_warningBanner(
        message:
            '⚠ Low storage: $mb MB remaining. Free up space to prevent issues.',
        color: CMBColors.ageingYellow,
        onDismiss: () => setState(() => _lowStorageDismissed = true),
      ));
    }

    // Drive storage low (orange, dismissable).
    if (s.driveStorageLow && !_driveLowDismissed) {
      banners.add(_warningBanner(
        message:
            '⚠ Google Drive storage low. Backups may fail soon. Free up Drive space.',
        color: CMBColors.warningOrange,
        onDismiss: () => setState(() => _driveLowDismissed = true),
      ));
    }

    return banners;
  }

  Widget _warningBanner({
    required String message,
    required Color color,
    VoidCallback? onDismiss,
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
          if (onDismiss != null)
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
          child: GestureDetector(
            onTap: onEdit,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 12, color: _tSec)),
                const SizedBox(height: 2),
                Text(
                  value > 0 ? '${money(value)}/g' : 'Not set',
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

    void openCashBook() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DailyAccountsScreen()),
        ).then((_) => _loadTodayAccounts());

    return Container(
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
                child: GestureDetector(
                  onTap: openCashBook,
                  child: _accountCol(
                    icon: Icons.account_balance_wallet,
                    label: 'Cash',
                    value: _todayCash,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: openCashBook,
                  child: _accountCol(
                    icon: Icons.account_balance,
                    label: 'Bank',
                    value: _todayUpi,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: openCashBook,
            child: Center(
              child: Text(
                '→ Tap to open cash book',
                style: TextStyle(
                    fontSize: 12,
                    color: _gold.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
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
            money(value),
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
    final s = _status;

    // Row 1 — database backup.
    Color dbDot;
    Color dbColor;
    String dbLabel;
    if (s == null) {
      dbDot = Colors.grey;
      dbColor = _tSec;
      dbLabel = 'Backup status…';
    } else if (s.lastBackupFailed) {
      dbDot = Colors.red;
      dbColor = Colors.red;
      dbLabel = s.lastDriveBackupFailedAt != null
          ? 'Last backup failed ${_hm(s.lastDriveBackupFailedAt!)}'
          : 'Last backup failed';
    } else if (s.lastDriveBackup != null) {
      dbDot = Colors.green;
      dbColor = const Color(0xFF388E3C);
      dbLabel = 'Last backup: ${formatBackupTime(s.lastDriveBackup)}';
    } else {
      dbDot = Colors.red;
      dbColor = Colors.red;
      dbLabel = 'Never backed up';
    }

    // Row 2 — photo sync.
    Color photoDot;
    Color photoColor;
    String photoLabel;
    IconData photoIcon;
    if (s == null || s.totalPhotos == 0) {
      photoDot = Colors.grey;
      photoColor = _tSec;
      photoLabel = 'No photos to sync';
      photoIcon = Icons.cloud_off;
    } else if (s.pendingPhotos > 0) {
      photoDot = CMBColors.warningOrange;
      photoColor = CMBColors.warningOrange;
      photoLabel = '${s.pendingPhotos} photos pending sync';
      photoIcon = Icons.cloud_upload;
    } else {
      photoDot = Colors.green;
      photoColor = const Color(0xFF388E3C);
      photoLabel = 'Photos synced ${formatBackupDate(s.lastPhotoBackup)}';
      photoIcon = Icons.cloud_done;
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminScreen()),
      ).then((_) => _loadBackupStatus()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gdBorder, width: 1),
        ),
        child: Column(
          children: [
            _backupRow(Icons.backup, dbDot, dbColor, dbLabel),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: Color(0xFFE0E0E0)),
            ),
            _backupRow(photoIcon, photoDot, photoColor, photoLabel),
          ],
        ),
      ),
    );
  }

  Widget _backupRow(IconData icon, Color dot, Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  color: color,
                  fontWeight: FontWeight.w500)),
        ),
        const Icon(Icons.chevron_right, color: _tSec, size: 16),
      ],
    );
  }

  String _hm(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
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
            child: Center(
              child: Image.asset(
                AppBranding.logoAsset,
                height: 80,
                width: 80,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.shield, color: _gold, size: 80),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _drawerItem(Icons.upload_file, 'Add Existing Loan',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const LoadExistingPledgeScreen()))),
                _drawerItem(Icons.archive, 'Closed Loans',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const ClosedPledgesScreen()))),
                _drawerItem(
                    Icons.account_balance_wallet,
                    'Cash Book',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const DailyAccountsScreen()))),
                _drawerItem(Icons.balance, 'Stock Register',
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
                _drawerItem(Icons.admin_panel_settings, 'Admin',
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AdminScreen()))),
                const Divider(height: 24),
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

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _isoDate(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-'
    '${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';
