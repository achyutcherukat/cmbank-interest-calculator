import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/database/app_database.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../core/services/backup_scheduler.dart';
import '../../../core/services/backup_status_service.dart';
import '../../../core/services/drive_service.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../backup/presentation/backup_actions.dart';
import '../data/admin_repository.dart';
import '../data/audit_log_repository.dart';
import 'initial_setup_values_screen.dart';
import 'manage_bank_accounts_screen.dart';
import '../data/item_types_repository.dart';
import '../data/purity_types_repository.dart';

// ─── Master item model ────────────────────────────────────────────────────────

class _MasterItem {
  _MasterItem({this.id, required this.name, required this.enabled});
  final int? id;
  String name;
  bool enabled;
}

// ─── Defaults ─────────────────────────────────────────────────────────────────

const _kFrequencies = ['30 mins', '1 hour', '2 hours', '3 hours', '6 hours'];
const _kFreqValues = [30, 60, 120, 180, 360];

// ─── Screen ───────────────────────────────────────────────────────────────────

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen>
    with WidgetsBindingObserver {
  final _settings = AppSettingsRepository();

  // General
  double _interestRate = 18.0;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;

  // Masters
  List<_MasterItem> _itemTypes = [];
  List<_MasterItem> _purityTypes = [];
  List<Map<String, dynamic>> _expenseCategories = [];

  // Backup
  TimeOfDay _backupStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _backupEnd = const TimeOfDay(hour: 17, minute: 30);
  int _backupFreqMins = 30;
  static const int _backupRetentionDays = 7; // fixed, not configurable
  BackupStatusSnapshot? _backupStatus;
  bool _busy = false;

  // Audit log
  int _auditLogCount = 0;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!AdminSession.isValid && mounted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => Navigator.pop(context));
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
    if (state == AppLifecycleState.resumed &&
        !AdminSession.isValid &&
        mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = await AppDatabase.instance.database;

      // Interest rate
      final rateStr = await _settings.getString('interest_rate') ??
          await _settings.getString('default_interest_rate');
      _interestRate = double.tryParse(rateStr ?? '') ?? 18.0;

      // Biometric
      final biometricEnabled = await _settings.getBool('biometric_enabled');
      final auth = LocalAuthentication();
      final canCheck = await auth.canCheckBiometrics;
      final isSupported = await auth.isDeviceSupported();
      _biometricEnabled = biometricEnabled;
      _biometricAvailable = canCheck && isSupported;

      // Item & purity types (from the lookup tables)
      _itemTypes = (await ItemTypesRepository.instance.getAllItemTypes())
          .map((t) => _MasterItem(id: t.id, name: t.name, enabled: t.isActive))
          .toList();
      _purityTypes =
          (await PurityTypesRepository.instance.getAllPurityTypes())
              .map((t) =>
                  _MasterItem(id: t.id, name: t.name, enabled: t.isActive))
              .toList();

      // Expense categories
      final cats =
          await db.query('expense_categories', orderBy: 'name ASC');
      _expenseCategories =
          cats.map((r) => Map<String, dynamic>.from(r)).toList();

      // Backup
      final bStart = await _settings.getString('backup_start_time');
      final bEnd = await _settings.getString('backup_end_time');
      final bFreq = await _settings.getString('backup_frequency');

      if (bStart != null) _backupStart = _parseTime(bStart);
      if (bEnd != null) _backupEnd = _parseTime(bEnd);
      _backupFreqMins = int.tryParse(bFreq ?? '') ?? 60;

      _backupStatus = await BackupStatusService.instance.load();

      // Audit log count
      _auditLogCount = await AuditLogRepository.instance.getCount();
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshBackupStatus() async {
    final status = await BackupStatusService.instance.load();
    if (mounted) setState(() => _backupStatus = status);
  }

  TimeOfDay _parseTime(String s) {
    final parts = s.split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      return TimeOfDay(hour: h, minute: m);
    }
    return const TimeOfDay(hour: 0, minute: 0);
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ── Save helpers ──────────────────────────────────────────────────────────────

  Future<void> _reloadItemTypes() async {
    final list = await ItemTypesRepository.instance.getAllItemTypes();
    if (mounted) {
      setState(() => _itemTypes = list
          .map((t) =>
              _MasterItem(id: t.id, name: t.name, enabled: t.isActive))
          .toList());
    }
  }

  Future<void> _reloadPurityTypes() async {
    final list = await PurityTypesRepository.instance.getAllPurityTypes();
    if (mounted) {
      setState(() => _purityTypes = list
          .map((t) =>
              _MasterItem(id: t.id, name: t.name, enabled: t.isActive))
          .toList());
    }
  }

  Future<void> _saveBiometric(bool value) async {
    await _settings.upsertMany({
      'biometric_enabled': (value: value.toString(), type: 'bool'),
    });
    setState(() => _biometricEnabled = value);
  }

  Future<void> _saveBackupSettings() async {
    await _settings.upsertMany({
      'backup_start_time':
          (value: _fmtTime(_backupStart), type: 'string'),
      'backup_end_time': (value: _fmtTime(_backupEnd), type: 'string'),
      'backup_frequency': (value: '$_backupFreqMins', type: 'int'),
      'backup_retention_days':
          (value: '$_backupRetentionDays', type: 'int'),
    });
    // Re-register the background task so the new schedule takes effect.
    try {
      await BackupScheduler.reschedule();
    } catch (_) {}
    _snack('Backup settings saved');
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : FlowColors.green,
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Settings',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
              children: [
                _sectionHeader('General', Icons.tune),
                _interestRateTile(),
                _changeCommonPinTile(),
                _changeAdminPinTile(),
                _biometricTile(),
                const SizedBox(height: 10),
                _sectionHeader('Masters', Icons.list_alt),
                _mastersTile('Item Types', _itemTypes, true),
                _mastersTile('Purity Types', _purityTypes, false),
                _expenseCategoriesTile(),
                _manageBankAccountsTile(),
                const SizedBox(height: 10),
                _sectionHeader('Backup', Icons.backup),
                _backupCard(),
                const SizedBox(height: 10),
                _sectionHeader('Audit Log', Icons.history),
                _auditLogTile(),
                const SizedBox(height: 10),
                _sectionHeader('Setup Values', Icons.history_edu_outlined),
                _setupValuesTile(),
                const SizedBox(height: 10),
                _sectionHeader('Info', Icons.info_outline),
                _infoCard(),
              ],
            ),
    );
  }

  // ── Section header ────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: FlowColors.primary),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.primary)),
        ],
      ),
    );
  }

  // ── Biometric ─────────────────────────────────────────────────────────────────

  Widget _biometricTile() {
    return FlowCard(
      padding: const EdgeInsets.all(0),
      child: SwitchListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        secondary: const Icon(Icons.fingerprint,
            color: FlowColors.primary, size: 28),
        title: const Text('Fingerprint Login',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: Text(
          _biometricAvailable
              ? 'Use fingerprint to unlock the app'
              : 'Fingerprint not available on this device',
          style:
              const TextStyle(fontSize: 14, color: FlowColors.medText),
        ),
        value: _biometricEnabled,
        onChanged: _biometricAvailable ? _saveBiometric : null,
        activeThumbColor: FlowColors.goldRich,
      ),
    );
  }

  // ── Interest Rate ─────────────────────────────────────────────────────────────

  Widget _interestRateTile() {
    return FlowCard(
      padding: const EdgeInsets.all(0),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const Icon(Icons.percent,
            color: FlowColors.primary, size: 28),
        title: const Text('Interest Rate',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${_interestRate.toStringAsFixed(0)}% per annum (new pledges only)',
            style:
                const TextStyle(fontSize: 14, color: FlowColors.medText)),
        trailing: const Icon(Icons.edit, color: FlowColors.primary),
        minVerticalPadding: 16,
        onTap: _showInterestRateDialog,
      ),
    );
  }

  void _showInterestRateDialog() {
    final ctrl = TextEditingController(
        text: _interestRate.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Interest Rate',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(
                  labelText: 'Rate (% per annum)',
                  suffixText: '%'),
            ),
            const SizedBox(height: 10),
            const FlowNoticeBox(
              text:
                  'New rate applies to new pledges only. Existing pledges keep their original rate.',
              icon: Icons.info_outline,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary),
            onPressed: () async {
              final val = double.tryParse(ctrl.text.trim());
              if (val == null || val <= 0) return;
              Navigator.pop(ctx);
              await _settings.upsertMany({
                'interest_rate':
                    (value: val.toStringAsFixed(2), type: 'string'),
              });
              setState(() => _interestRate = val);
              _snack(
                  'Interest rate updated to ${val.toStringAsFixed(0)}%');
            },
            child: const Text('Save',
                style: TextStyle(fontSize: 16, color: FlowColors.textOnNavySmall)),
          ),
        ],
      ),
    );
  }

  // ── Change Common PIN ─────────────────────────────────────────────────────────

  Widget _changeCommonPinTile() {
    return FlowCard(
      padding: const EdgeInsets.all(0),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const Icon(Icons.lock,
            color: FlowColors.primaryLight, size: 28),
        title: const Text('Change Common PIN',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: const Text('Staff login PIN',
            style: TextStyle(fontSize: 14, color: FlowColors.medText)),
        trailing: const Icon(Icons.chevron_right),
        minVerticalPadding: 16,
        onTap: () => _showChangePinDialog(isAdmin: false),
      ),
    );
  }

  // ── Change Admin PIN ──────────────────────────────────────────────────────────

  Widget _changeAdminPinTile() {
    return FlowCard(
      padding: const EdgeInsets.all(0),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const Icon(Icons.admin_panel_settings,
            color: FlowColors.orange, size: 28),
        title: const Text('Change Admin PIN',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: const Text('Admin area PIN',
            style: TextStyle(fontSize: 14, color: FlowColors.medText)),
        trailing: const Icon(Icons.chevron_right),
        minVerticalPadding: 16,
        onTap: () => _showChangePinDialog(isAdmin: true),
      ),
    );
  }

  void _showChangePinDialog({required bool isAdmin}) {
    final currentPinCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) => AlertDialog(
          title: Text(isAdmin ? 'Change Admin PIN' : 'Change Common PIN',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.primary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAdmin) ...[
                  _pinField('Current Admin PIN', currentPinCtrl),
                  const SizedBox(height: 10),
                ],
                _pinField('New PIN (6 digits)', newPinCtrl),
                const SizedBox(height: 10),
                _pinField('Confirm New PIN', confirmCtrl),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 14)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: const Text('Cancel',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.primary),
              onPressed: () async {
                final newPin = newPinCtrl.text.trim();
                final confirm = confirmCtrl.text.trim();

                if (newPin.length != 6) {
                  setDlg(() => error = 'New PIN must be 6 digits');
                  return;
                }
                if (newPin != confirm) {
                  setDlg(() => error = 'PINs do not match');
                  return;
                }

                if (isAdmin) {
                  final cur = currentPinCtrl.text.trim();
                  final storedHash =
                      await _settings.getString('admin_pin_hash');
                  if (storedHash == null ||
                      PinHasher.hash(cur) != storedHash) {
                    setDlg(
                        () => error = 'Current admin PIN is incorrect');
                    return;
                  }
                }

                final hashKey =
                    isAdmin ? 'admin_pin_hash' : 'common_pin_hash';
                await _settings.upsertMany({
                  hashKey: (value: PinHasher.hash(newPin), type: 'string'),
                });
                if (ctx2.mounted) Navigator.pop(ctx2);
                _snack(isAdmin
                    ? 'Admin PIN changed successfully'
                    : 'Common PIN changed successfully');
              },
              child: const Text('Save',
                  style: TextStyle(fontSize: 16, color: FlowColors.textOnNavySmall)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      obscureText: true,
      textAlign: TextAlign.center,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      style: const TextStyle(
          fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            fontSize: 15, letterSpacing: 0, fontWeight: FontWeight.normal),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 16),
      ),
    );
  }

  // ── Masters ───────────────────────────────────────────────────────────────────

  Widget _mastersTile(String title, List<_MasterItem> items, bool isItem) {
    Future<void> toggle(int id, bool val) async {
      if (isItem) {
        await ItemTypesRepository.instance.toggleItemType(id, val);
        await _reloadItemTypes();
      } else {
        await PurityTypesRepository.instance.togglePurityType(id, val);
        await _reloadPurityTypes();
      }
    }

    Future<void> rename(int id, String name) async {
      if (isItem) {
        await ItemTypesRepository.instance.updateItemType(id, name);
        await _reloadItemTypes();
      } else {
        await PurityTypesRepository.instance.updatePurityType(id, name);
        await _reloadPurityTypes();
      }
    }

    Future<void> add(String name) async {
      if (isItem) {
        await ItemTypesRepository.instance.addItemType(name);
        await _reloadItemTypes();
      } else {
        await PurityTypesRepository.instance.addPurityType(name);
        await _reloadPurityTypes();
      }
    }

    return FlowCard(
      padding: const EdgeInsets.all(0),
      child: ExpansionTile(
        leading: Icon(
          title == 'Item Types' ? Icons.category : Icons.grade,
          color: FlowColors.primary,
          size: 26,
        ),
        title: Text(title,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${items.where((e) => e.enabled).length} active',
            style:
                const TextStyle(fontSize: 13, color: FlowColors.medText)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          ...items.map((item) => _masterRow(
              item,
              onToggle: (val) async {
                if (item.id != null) await toggle(item.id!, val);
              },
              onEdit: () => _showEditMasterDialog(
                  item.name,
                  (newName) async {
                    if (item.id != null) await rename(item.id!, newName);
                  }))),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showAddMasterDialog((name) async {
                await add(name);
              }),
              icon: const Icon(Icons.add, size: 18),
              label: Text('Add $title',
                  style: const TextStyle(fontSize: 15)),
              style: OutlinedButton.styleFrom(
                foregroundColor: FlowColors.primary,
                side:
                    const BorderSide(color: FlowColors.primaryLight),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _masterRow(_MasterItem item,
      {required ValueChanged<bool> onToggle,
      required VoidCallback onEdit}) {
    return Row(
      children: [
        Expanded(
          child: Text(item.name,
              style: TextStyle(
                  fontSize: 17,
                  color:
                      item.enabled ? FlowColors.darkText : Colors.black38,
                  decoration: item.enabled
                      ? null
                      : TextDecoration.lineThrough)),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined,
              size: 20, color: FlowColors.primary),
          onPressed: onEdit,
          tooltip: 'Edit',
        ),
        Switch(
          value: item.enabled,
          onChanged: onToggle,
          activeThumbColor: FlowColors.primary,
        ),
      ],
    );
  }

  void _showAddMasterDialog(Future<void> Function(String) onAdd) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary),
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await onAdd(name);
            },
            child: const Text('Add',
                style: TextStyle(color: FlowColors.textOnNavyLarge)),
          ),
        ],
      ),
    );
  }

  void _showEditMasterDialog(
      String current, Future<void> Function(String) onSave) {
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Name',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary),
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await onSave(name);
            },
            child: const Text('Save',
                style: TextStyle(color: FlowColors.textOnNavyLarge)),
          ),
        ],
      ),
    );
  }

  // ── Expense Categories ────────────────────────────────────────────────────────

  Widget _expenseCategoriesTile() {
    return FlowCard(
      padding: const EdgeInsets.all(0),
      child: ExpansionTile(
        leading: const Icon(Icons.account_balance_wallet,
            color: FlowColors.primary, size: 26),
        title: const Text('Expense Categories',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${_expenseCategories.where((e) => (e['is_active'] as int?) == 1).length} active',
            style:
                const TextStyle(fontSize: 13, color: FlowColors.medText)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          ..._expenseCategories.asMap().entries.map((e) {
            final cat = e.value;
            final active = (cat['is_active'] as int?) == 1;
            return Row(
              children: [
                Expanded(
                  child: Text(cat['name'] as String? ?? '',
                      style: TextStyle(
                          fontSize: 17,
                          color: active
                              ? FlowColors.darkText
                              : Colors.black38,
                          decoration: active
                              ? null
                              : TextDecoration.lineThrough)),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 20, color: FlowColors.primary),
                  onPressed: () => _showEditCategoryDialog(
                      cat['id'] as int, cat['name'] as String? ?? ''),
                ),
                Switch(
                  value: active,
                  onChanged: (val) => _toggleCategory(
                      cat['id'] as int, val, e.key),
                  activeThumbColor: FlowColors.primary,
                ),
              ],
            );
          }),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showAddCategoryDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Category',
                  style: TextStyle(fontSize: 15)),
              style: OutlinedButton.styleFrom(
                foregroundColor: FlowColors.primary,
                side:
                    const BorderSide(color: FlowColors.primaryLight),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _manageBankAccountsTile() {
    return FlowCard(
      padding: const EdgeInsets.all(0),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const Icon(Icons.account_balance,
            color: FlowColors.primary, size: 26),
        title: const Text('Bank Accounts',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: const Text('Manage payment bank accounts',
            style: TextStyle(fontSize: 14, color: FlowColors.medText)),
        trailing: const Icon(Icons.chevron_right),
        minVerticalPadding: 16,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const ManageBankAccountsScreen()),
        ),
      ),
    );
  }

  Future<void> _toggleCategory(int id, bool active, int index) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'expense_categories',
      {
        'is_active': active ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    setState(() {
      _expenseCategories[index] = Map.from(_expenseCategories[index])
        ..['is_active'] = active ? 1 : 0;
    });
  }

  void _showAddCategoryDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Category',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary),
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final db = await AppDatabase.instance.database;
              final now = DateTime.now().toIso8601String();
              final id = await db.insert('expense_categories', {
                'name': name,
                'is_active': 1,
                'created_at': now,
                'updated_at': now,
              });
              setState(() {
                _expenseCategories.add({
                  'id': id,
                  'name': name,
                  'is_active': 1,
                });
              });
            },
            child: const Text('Add',
                style: TextStyle(color: FlowColors.textOnNavyLarge)),
          ),
        ],
      ),
    );
  }

  void _showEditCategoryDialog(int id, String current) {
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Category',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 18),
          decoration:
              const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary),
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final db = await AppDatabase.instance.database;
              await db.update(
                'expense_categories',
                {
                  'name': name,
                  'updated_at': DateTime.now().toIso8601String(),
                },
                where: 'id = ?',
                whereArgs: [id],
              );
              setState(() {
                final idx = _expenseCategories
                    .indexWhere((e) => e['id'] == id);
                if (idx >= 0) {
                  _expenseCategories[idx] =
                      Map.from(_expenseCategories[idx])..['name'] = name;
                }
              });
            },
            child: const Text('Save',
                style: TextStyle(color: FlowColors.textOnNavyLarge)),
          ),
        ],
      ),
    );
  }

  // ── Backup ────────────────────────────────────────────────────────────────────

  Widget _backupCard() {
    return Column(
      children: [
        _backupAccountCard(),
        const SizedBox(height: 10),
        _backupStatusCard(),
        const SizedBox(height: 10),
        _backupActionsCard(),
        const SizedBox(height: 10),
        _backupScheduleCard(),
      ],
    );
  }

  // Account section ─────────────────────────────────────────────────────────────

  Widget _backupAccountCard() {
    final s = _backupStatus;
    final signedIn = s?.driveAuthed ?? false;
    final email = s?.signedInEmail ?? '';
    return FlowCard(
      header: 'GOOGLE DRIVE ACCOUNT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(signedIn ? Icons.account_circle : Icons.cloud_off,
                  color: signedIn ? FlowColors.green : FlowColors.medText,
                  size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  signedIn && email.isNotEmpty ? email : 'Not signed in',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: Icon(signedIn ? Icons.logout : Icons.login),
              label: Text(signedIn ? 'SIGN OUT' : 'SIGN IN TO GOOGLE'),
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      if (signedIn) {
                        await DriveService.instance.signOut();
                      } else {
                        await DriveService.instance.signIn();
                      }
                      await _refreshBackupStatus();
                      if (mounted) setState(() => _busy = false);
                    },
            ),
          ),
        ],
      ),
    );
  }

  // Status section ──────────────────────────────────────────────────────────────

  Widget _backupStatusCard() {
    final s = _backupStatus;
    final photoLine = s == null
        ? '—'
        : '${formatBackupTime(s.lastPhotoBackup)} · ${s.pendingPhotos} pending';
    final driveStorage = (s?.driveFreeMb != null)
        ? '${(s!.driveFreeMb! / 1024).toStringAsFixed(1)} GB free of 15 GB'
        : 'Unknown';
    final deviceStorage = (s?.deviceFreeMb != null)
        ? '${s!.deviceFreeMb!.round()} MB free'
        : 'Unknown';
    return FlowCard(
      header: 'STATUS',
      child: Column(
        children: [
          _statusRow('Drive backup', formatBackupTime(s?.lastDriveBackup)),
          _statusRow('Photo sync', photoLine),
          _statusRow('Local backup', formatBackupTime(s?.lastLocalBackup)),
          _statusRow('Drive storage', driveStorage),
          _statusRow('Device storage', deviceStorage, isLast: true),
        ],
      ),
    );
  }

  Widget _statusRow(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: FlowColors.medText)),
          ),
          Expanded(
            flex: 3,
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // Actions section ─────────────────────────────────────────────────────────────

  Widget _backupActionsCard() {
    return FlowCard(
      header: 'ACTIONS',
      child: Column(
        children: [
          _fullActionButton(
            'BACKUP NOW',
            Icons.backup,
            filled: true,
            onTap: () async {
              await BackupActions.backupNow(context);
              await _refreshBackupStatus();
            },
          ),
          const SizedBox(height: 10),
          _fullActionButton(
            'RESTORE PHOTOS',
            Icons.photo_library_outlined,
            filled: false,
            onTap: () => BackupActions.restorePhotosNow(context),
          ),
          const SizedBox(height: 10),
          _fullActionButton(
            'BACKUP TO DEVICE',
            Icons.sd_storage,
            filled: true,
            onTap: () async {
              await BackupActions.backupToDevice(context);
              await _refreshBackupStatus();
            },
          ),
          const SizedBox(height: 10),
          _fullActionButton(
            'RESTORE FROM DRIVE',
            Icons.cloud_download,
            filled: false,
            onTap: () => BackupActions.restoreFromDrive(context),
          ),
          const SizedBox(height: 10),
          _fullActionButton(
            'RESTORE FROM DEVICE',
            Icons.restore_page,
            filled: false,
            onTap: () => BackupActions.restoreFromDevice(context),
          ),
        ],
      ),
    );
  }

  Widget _fullActionButton(
    String label,
    IconData icon, {
    required bool filled,
    required VoidCallback onTap,
  }) {
    final child = filled
        ? ElevatedButton.icon(
            onPressed: _busy ? null : onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: FlowColors.primary,
              foregroundColor: FlowColors.textOnNavyLarge,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: Icon(icon),
            label: Text(label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          )
        : OutlinedButton.icon(
            onPressed: _busy ? null : onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: FlowColors.primary,
              side: const BorderSide(color: FlowColors.primary),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: Icon(icon),
            label: Text(label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          );
    return SizedBox(width: double.infinity, child: child);
  }

  // Schedule section ────────────────────────────────────────────────────────────

  Widget _backupScheduleCard() {
    return FlowCard(
      header: 'AUTOMATIC BACKUP SCHEDULE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _timePickerTile('Start Time', _backupStart,
                    (t) => setState(() => _backupStart = t)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _timePickerTile('End Time', _backupEnd,
                    (t) => setState(() => _backupEnd = t)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: _backupFreqMins,
            decoration: const InputDecoration(
              labelText: 'Frequency',
              prefixIcon: Icon(Icons.timer),
            ),
            items: List.generate(
              _kFrequencies.length,
              (i) => DropdownMenuItem(
                value: _kFreqValues[i],
                child: Text(_kFrequencies[i],
                    style: const TextStyle(fontSize: 17)),
              ),
            ),
            onChanged: (v) => setState(() => _backupFreqMins = v ?? 60),
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              Icon(Icons.history, size: 18, color: FlowColors.medText),
              SizedBox(width: 8),
              Text('Retention: Last 7 days of backups kept',
                  style: TextStyle(fontSize: 14, color: FlowColors.medText)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _saveBackupSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary,
                foregroundColor: FlowColors.textOnNavyLarge,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.save),
              label: const Text('Save Schedule',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Photos are synced automatically with every backup.',
            style: TextStyle(fontSize: 13, color: FlowColors.medText),
          ),
        ],
      ),
    );
  }

  Widget _timePickerTile(
      String label, TimeOfDay time, ValueChanged<TimeOfDay> onPick) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: FlowColors.primaryLight),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time,
                size: 20, color: FlowColors.primary),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54)),
                Text(_fmtTime(time),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Audit Log ─────────────────────────────────────────────────────────────────

  Widget _auditLogTile() {
    return FlowCard(
      padding: const EdgeInsets.all(0),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const Icon(Icons.history, color: FlowColors.primary, size: 28),
        title: const Text('Clear Old Entries',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: Text('$_auditLogCount entries stored',
            style: const TextStyle(fontSize: 14, color: FlowColors.medText)),
        trailing: const Icon(Icons.delete_sweep, color: FlowColors.orange),
        minVerticalPadding: 16,
        onTap: _showPurgeDialog,
      ),
    );
  }

  void _showPurgeDialog() {
    const options = [
      (30, 'Last 30 days'),
      (90, 'Last 90 days'),
      (180, 'Last 180 days'),
      (365, 'Last 1 year'),
    ];
    int selected = 90;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) => AlertDialog(
          title: const Text('Clear Old Audit Entries',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.primary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Keep entries from the last:',
                  style: TextStyle(fontSize: 15)),
              const SizedBox(height: 12),
              RadioGroup<int>(
                groupValue: selected,
                onChanged: (v) {
                  if (v != null) setDlg(() => selected = v);
                },
                child: Column(
                  children: options
                      .map((o) => RadioListTile<int>(
                            value: o.$1,
                            title: Text(o.$2,
                                style: const TextStyle(fontSize: 16)),
                            activeColor: FlowColors.primary,
                            contentPadding: EdgeInsets.zero,
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: const Text('Cancel',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.orange),
              onPressed: () async {
                Navigator.pop(ctx2);
                await _settings.upsertMany({
                  'audit_log_retention_days':
                      (value: '$selected', type: 'int'),
                });
                final deleted =
                    await AuditLogRepository.instance.purge(selected);
                _auditLogCount =
                    await AuditLogRepository.instance.getCount();
                if (mounted) {
                  setState(() {});
                  _snack('$deleted entries deleted');
                }
              },
              child: const Text('Clear',
                  style: TextStyle(
                      fontSize: 16, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Setup Values ──────────────────────────────────────────────────────────────

  Widget _setupValuesTile() {
    return FlowCard(
      padding: const EdgeInsets.all(0),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const Icon(Icons.history_edu,
            color: FlowColors.primary, size: 28),
        title: const Text('Initial Setup Values',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: const Text(
            'Opening balances and stock from first launch',
            style: TextStyle(fontSize: 14, color: FlowColors.medText)),
        trailing: const Icon(Icons.chevron_right),
        minVerticalPadding: 16,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const InitialSetupValuesScreen()),
        ),
      ),
    );
  }

  // ── App Info ──────────────────────────────────────────────────────────────────

  Widget _infoCard() {
    return FlowCard(
      header: 'APP INFORMATION',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DetailRow(label: 'App Version', value: '1.0.0'),
          const DetailRow(label: 'Build Number', value: '1', isLast: true),
        ],
      ),
    );
  }
}
