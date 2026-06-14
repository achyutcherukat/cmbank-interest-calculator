import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../data/admin_repository.dart';

// ─── Master item model ────────────────────────────────────────────────────────

class _MasterItem {
  _MasterItem({required this.name, required this.enabled});
  String name;
  bool enabled;

  Map<String, dynamic> toJson() => {'name': name, 'enabled': enabled};
  factory _MasterItem.fromJson(Map<String, dynamic> j) =>
      _MasterItem(name: j['name'] as String, enabled: j['enabled'] as bool);
}

// ─── Defaults ─────────────────────────────────────────────────────────────────

const _kDefaultItemTypes = [
  'Gold Ring', 'Bangles', 'Necklace', 'Earrings',
  'Chain', 'Bracelet', 'Gold Coins', 'Other',
];
const _kDefaultPurityTypes = ['24K', '22K', '18K', 'Other'];
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

  // Masters
  List<_MasterItem> _itemTypes = [];
  List<_MasterItem> _purityTypes = [];
  List<Map<String, dynamic>> _expenseCategories = [];

  // Backup
  TimeOfDay _backupStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _backupEnd = const TimeOfDay(hour: 6, minute: 0);
  int _backupFreqMins = 60;
  int _backupRetentionDays = 30;

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
      final rateStr = await _settings.getString('default_interest_rate');
      _interestRate = double.tryParse(rateStr ?? '') ?? 18.0;

      // Item types
      final itemJson = await _settings.getString('admin_item_types');
      if (itemJson != null && itemJson.isNotEmpty) {
        _itemTypes = (jsonDecode(itemJson) as List)
            .map((j) => _MasterItem.fromJson(j as Map<String, dynamic>))
            .toList();
      } else {
        _itemTypes = _kDefaultItemTypes
            .map((n) => _MasterItem(name: n, enabled: true))
            .toList();
      }

      // Purity types
      final purityJson = await _settings.getString('admin_purity_types');
      if (purityJson != null && purityJson.isNotEmpty) {
        _purityTypes = (jsonDecode(purityJson) as List)
            .map((j) => _MasterItem.fromJson(j as Map<String, dynamic>))
            .toList();
      } else {
        _purityTypes = _kDefaultPurityTypes
            .map((n) => _MasterItem(name: n, enabled: true))
            .toList();
      }

      // Expense categories
      final cats =
          await db.query('expense_categories', orderBy: 'name ASC');
      _expenseCategories =
          cats.map((r) => Map<String, dynamic>.from(r)).toList();

      // Backup
      final bStart = await _settings.getString('backup_start_time');
      final bEnd = await _settings.getString('backup_end_time');
      final bFreq = await _settings.getString('backup_frequency_mins');
      final bRetain = await _settings.getString('backup_retention_days');

      if (bStart != null) _backupStart = _parseTime(bStart);
      if (bEnd != null) _backupEnd = _parseTime(bEnd);
      _backupFreqMins = int.tryParse(bFreq ?? '') ?? 60;
      _backupRetentionDays = int.tryParse(bRetain ?? '') ?? 30;
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
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

  Future<void> _saveItemTypes() async {
    final json = jsonEncode(_itemTypes.map((e) => e.toJson()).toList());
    await _settings.upsertMany(
        {'admin_item_types': (value: json, type: 'json')});
  }

  Future<void> _savePurityTypes() async {
    final json = jsonEncode(_purityTypes.map((e) => e.toJson()).toList());
    await _settings.upsertMany(
        {'admin_purity_types': (value: json, type: 'json')});
  }

  Future<void> _saveBackupSettings() async {
    await _settings.upsertMany({
      'backup_start_time':
          (value: _fmtTime(_backupStart), type: 'string'),
      'backup_end_time': (value: _fmtTime(_backupEnd), type: 'string'),
      'backup_frequency_mins':
          (value: '$_backupFreqMins', type: 'int'),
      'backup_retention_days':
          (value: '$_backupRetentionDays', type: 'int'),
    });
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
                const SizedBox(height: 10),
                _sectionHeader('Masters', Icons.list_alt),
                _mastersTile('Item Types', _itemTypes, _saveItemTypes),
                _mastersTile('Purity Types', _purityTypes, _savePurityTypes),
                _expenseCategoriesTile(),
                const SizedBox(height: 10),
                _sectionHeader('Backup', Icons.backup),
                _backupCard(),
                const SizedBox(height: 10),
                _sectionHeader('Day Management', Icons.calendar_today),
                _dayManagementCard(),
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
                'default_interest_rate':
                    (value: val.toStringAsFixed(2), type: 'double'),
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

  Widget _mastersTile(String title, List<_MasterItem> items,
      Future<void> Function() onSave) {
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
          ...items.asMap().entries.map((e) => _masterRow(
              e.value,
              onToggle: (val) async {
                setState(() => items[e.key].enabled = val);
                await onSave();
              },
              onEdit: () => _showEditMasterDialog(
                  items[e.key].name,
                  (newName) async {
                    setState(() => items[e.key].name = newName);
                    await onSave();
                  }))),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showAddMasterDialog((name) async {
                setState(() =>
                    items.add(_MasterItem(name: name, enabled: true)));
                await onSave();
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
    return FlowCard(
      header: 'BACKUP SCHEDULE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Schedule
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
          // Frequency
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
            onChanged: (v) =>
                setState(() => _backupFreqMins = v ?? 60),
          ),
          const SizedBox(height: 14),
          // Retention
          TextField(
            controller: TextEditingController(
                text: '$_backupRetentionDays'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Keep backups for (days)',
              prefixIcon: Icon(Icons.history),
            ),
            onChanged: (v) =>
                setState(() => _backupRetentionDays = int.tryParse(v) ?? 30),
          ),
          const SizedBox(height: 16),
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
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.backup,
                  label: 'BACKUP NOW',
                  color: FlowColors.primary,
                  onTap: () => _snack('Backup feature coming soon'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionBtn(
                  icon: Icons.restore,
                  label: 'RESTORE',
                  color: FlowColors.orange,
                  onTap: () => _snack('Restore feature coming soon'),
                ),
              ),
            ],
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

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  // ── Day Management ────────────────────────────────────────────────────────────

  Widget _dayManagementCard() {
    return FlowCard(
      header: 'UNLOCK LOCKED DAY',
      child: _DayUnlockWidget(onDone: () => _snack('Day unlocked')),
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

// ─── Day Unlock Widget ────────────────────────────────────────────────────────

class _DayUnlockWidget extends StatefulWidget {
  const _DayUnlockWidget({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_DayUnlockWidget> createState() => _DayUnlockWidgetState();
}

class _DayUnlockWidgetState extends State<_DayUnlockWidget> {
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _dayBalance;
  bool _checking = false;
  bool _unlocking = false;
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkDay() async {
    setState(() => _checking = true);
    final fmt =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final bal = await AdminRepository.instance.getDayBalance(fmt);
    if (mounted) {
      setState(() {
        _dayBalance = bal;
        _checking = false;
      });
    }
  }

  Future<void> _unlock() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a reason'),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _unlocking = true);
    final fmt =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    await AdminRepository.instance.unlockDay(fmt, reason);
    if (mounted) {
      setState(() {
        _unlocking = false;
        _dayBalance = null;
        _reasonCtrl.clear();
      });
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = (_dayBalance?['is_locked'] as int?) == 1;
    final dateLabel =
        '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date selector
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (picked != null) {
              setState(() => _selectedDate = picked);
              await _checkDay();
            }
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: FlowColors.primaryLight),
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today,
                    color: FlowColors.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(dateLabel,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.black45),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (_checking)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator()))
        else if (_dayBalance == null)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _checkDay,
              icon: const Icon(Icons.search),
              label: const Text('Check Day Status',
                  style: TextStyle(fontSize: 16)),
              style: OutlinedButton.styleFrom(
                foregroundColor: FlowColors.primary,
                side:
                    const BorderSide(color: FlowColors.primaryLight),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          )
        else ...[
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isLocked ? FlowColors.redLight : FlowColors.greenLight,
              border: Border.all(
                  color: isLocked ? FlowColors.red : FlowColors.green),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isLocked ? Icons.lock : Icons.lock_open,
                  color: isLocked ? FlowColors.red : FlowColors.green,
                ),
                const SizedBox(width: 10),
                Text(
                  isLocked ? 'This day is LOCKED' : 'This day is not locked',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color:
                          isLocked ? FlowColors.red : FlowColors.green),
                ),
              ],
            ),
          ),
          if (isLocked) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(
                labelText: 'Reason for unlocking (required)',
                prefixIcon: Icon(Icons.edit_note),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _unlocking ? null : _unlock,
                style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: _unlocking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.lock_open),
                label: Text(
                    _unlocking ? 'Unlocking...' : 'UNLOCK DAY',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
