import 'package:flutter/material.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../../admin/data/admin_repository.dart';
import '../data/chart_of_accounts_repository.dart';
import '../data/ledger_account_model.dart';

/// Admin-only screen (reached via PIN-gated Admin Settings) to add, rename,
/// disable or delete ledger accounts in the chart of accounts.
///
/// System accounts (Cash, Gold Loan Receivable, Interest Collected, Partner
/// Capital, and accounts linked to bank accounts / expense categories) can be
/// renamed but never deleted or disabled here — the auto-posting engine
/// depends on their continued existence.
class AddLedgerAccountScreen extends StatefulWidget {
  const AddLedgerAccountScreen({super.key});

  @override
  State<AddLedgerAccountScreen> createState() => _AddLedgerAccountScreenState();
}

class _AddLedgerAccountScreenState extends State<AddLedgerAccountScreen> {
  final _nameCtrl = TextEditingController();
  String _accountType = LedgerAccountType.asset;
  String? _formError;
  bool _saving = false;

  List<LedgerAccount> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (!AdminSession.isValid && mounted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => Navigator.pop(context));
      return;
    }
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final accounts = await ChartOfAccountsRepository.instance.getAll();
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _loading = false;
      });
    }
  }

  // ─── Add ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _formError = 'Enter an account name.');
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    final created = await ChartOfAccountsRepository.instance.insertStandalone(
      name: name,
      accountType: _accountType,
    );
    _nameCtrl.clear();
    await _load();
    if (!mounted) return;
    setState(() => _saving = false);
    if (created != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Account "${created.name}" added '
              '(code ${created.code})')));
    }
  }

  // ─── Rename ─────────────────────────────────────────────────────────────

  void _showRenameDialog(LedgerAccount account) {
    final ctrl = TextEditingController(text: account.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Account',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(labelText: 'Account name'),
            ),
            if (account.isSystem) ...[
              const SizedBox(height: 10),
              const Text(
                'System account — only the name can be changed.',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: FlowColors.primary),
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await ChartOfAccountsRepository.instance
                  .rename(account.id!, name);
              _load();
            },
            child: const Text('Save',
                style: TextStyle(color: FlowColors.textOnNavyLarge)),
          ),
        ],
      ),
    );
  }

  // ─── Disable / enable ───────────────────────────────────────────────────

  Future<void> _toggleActive(LedgerAccount account, bool active) async {
    await ChartOfAccountsRepository.instance
        .setActive(account.id!, active: active);
    _load();
  }

  // ─── Delete ─────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(LedgerAccount account) async {
    final activity = await ChartOfAccountsRepository.instance
        .journalLineCount(account.id!);
    if (!mounted) return;

    if (activity > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot Delete',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.red)),
          content: Text(
              'This account has transaction history and cannot be deleted — '
              'disable it instead.\n\n"${account.name}" is referenced by '
              '$activity journal ${activity == 1 ? 'line' : 'lines'}.',
              style: const TextStyle(fontSize: 15)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.grey))),
            if (account.isActive)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: FlowColors.primary),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _toggleActive(account, false);
                },
                child: const Text('Disable Instead',
                    style: TextStyle(color: FlowColors.textOnNavyLarge)),
              ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.red)),
        content: Text(
            'Delete "${account.name}" (code ${account.code})? '
            'This cannot be undone.',
            style: const TextStyle(fontSize: 15)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: FlowColors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final result =
                  await ChartOfAccountsRepository.instance.delete(account.id!);
              await _load();
              if (!mounted) return;
              final message = switch (result) {
                LedgerAccountDeleteResult.deleted => 'Account deleted',
                LedgerAccountDeleteResult.blockedSystem =>
                  'System accounts cannot be deleted',
                LedgerAccountDeleteResult.blockedHasActivity =>
                  'This account has transaction history and cannot be '
                      'deleted — disable it instead',
              };
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(message)));
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Ledger Accounts'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _addForm(),
                const SizedBox(height: 16),
                const Text('ALL ACCOUNTS',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: FlowColors.medText,
                        letterSpacing: 0.5)),
                const SizedBox(height: 8),
                ..._accounts.map(_accountRow),
              ],
            ),
    );
  }

  Widget _addForm() {
    return FlowCard(
      header: 'ADD LEDGER ACCOUNT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_formError != null) setState(() => _formError = null);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _accountType,
            decoration: const InputDecoration(
              labelText: 'Account Type',
              border: OutlineInputBorder(),
            ),
            items: LedgerAccountType.all
                .map((t) => DropdownMenuItem(
                    value: t, child: Text(LedgerAccountType.label(t))))
                .toList(),
            onChanged: (v) =>
                setState(() => _accountType = v ?? LedgerAccountType.asset),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 8),
            Text(_formError!,
                style: const TextStyle(color: FlowColors.red, fontSize: 14)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: FlowColors.goldRich))
                  : const Icon(Icons.add, size: 20),
              label: const Text('ADD ACCOUNT',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary,
                foregroundColor: FlowColors.goldRich,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountRow(LedgerAccount account) {
    return FlowCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(account.code,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: FlowColors.medText)),
                    const SizedBox(width: 8),
                    if (account.isSystem) _badge('SYSTEM', FlowColors.primary),
                    if (!account.isActive) ...[
                      const SizedBox(width: 4),
                      _badge('INACTIVE', FlowColors.red),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(account.name,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: account.isActive
                            ? FlowColors.darkText
                            : Colors.black38,
                        decoration: account.isActive
                            ? null
                            : TextDecoration.lineThrough)),
                Text(LedgerAccountType.label(account.accountType),
                    style: const TextStyle(
                        fontSize: 12, color: FlowColors.medText)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 20, color: FlowColors.primary),
            tooltip: 'Rename',
            onPressed: () => _showRenameDialog(account),
          ),
          if (!account.isSystem) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: FlowColors.red),
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(account),
            ),
            Switch(
              value: account.isActive,
              onChanged: (v) => _toggleActive(account, v),
              activeThumbColor: FlowColors.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5)),
    );
  }
}
