import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/ledger_posting_service.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../core/utils/ledger_amount_formatter.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../admin/data/admin_repository.dart';
import '../data/chart_of_accounts_repository.dart';
import '../data/ledger_account_model.dart';

/// One-time, admin-only wizard that posts the ledger's starting position as
/// of `settings.ledger_start_date` — one MANUAL, balanced journal entry.
///
/// Every field is typed in manually (no pre-fill from pledges/bank accounts by
/// design), the account list is generated live from `chart_of_accounts`
/// (`is_active = 1`) when the wizard opens, and once posted the wizard locks
/// into a read-only summary (`settings.ledger_opening_posted`) — corrections
/// after that are reversing entries, never edits.
class OpeningBalanceWizardScreen extends StatefulWidget {
  const OpeningBalanceWizardScreen({super.key});

  @override
  State<OpeningBalanceWizardScreen> createState() =>
      _OpeningBalanceWizardScreenState();
}

class _PostedLine {
  const _PostedLine(this.name, this.debit, this.credit);
  final String name;
  final double debit;
  final double credit;
}

class _OpeningBalanceWizardScreenState
    extends State<OpeningBalanceWizardScreen> {
  final _settings = AppSettingsRepository();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String _startDate = '';
  bool _posted = false;

  // Form state (unposted).
  List<LedgerAccount> _accounts = [];
  final Map<int, TextEditingController> _ctrls = {};

  // Read-only summary (posted).
  String? _postedAt;
  List<_PostedLine> _postedLines = [];

  // Debit side: assets + expense period totals. Credit side: liabilities +
  // capital + income period totals.
  static const _debitTypes = {
    LedgerAccountType.asset,
    LedgerAccountType.expense,
  };

  static const _sections = <(String, String)>[
    (LedgerAccountType.asset, 'ASSETS'),
    (LedgerAccountType.liability, 'LIABILITIES'),
    (LedgerAccountType.capital, 'CAPITAL'),
    (LedgerAccountType.income, 'INCOME'),
    (LedgerAccountType.expense, 'EXPENSES'),
  ];

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
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    _startDate = await _settings.getString('ledger_start_date') ?? '';
    _posted = await _settings.getBool('ledger_opening_posted');

    if (_posted) {
      await _loadPostedSummary();
    } else {
      final all = await ChartOfAccountsRepository.instance.getAll();
      _accounts = all.where((a) => a.isActive).toList();
      for (final account in _accounts) {
        _ctrls[account.id!] = TextEditingController();
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPostedSummary() async {
    final db = await AppDatabase.instance.database;
    final entries = await db.query('journal_entries',
        where: "source_type = 'opening_balance'", limit: 1);
    if (entries.isEmpty) return;
    _postedAt = entries.first['created_at'] as String?;
    final rows = await db.rawQuery('''
      SELECT jl.debit, jl.credit, c.name
      FROM journal_lines jl
      JOIN chart_of_accounts c ON c.id = jl.account_id
      WHERE jl.journal_entry_id = ?
      ORDER BY jl.id ASC
    ''', [entries.first['id']]);
    _postedLines = [
      for (final r in rows)
        _PostedLine(
          r['name'] as String? ?? '',
          (r['debit'] as num?)?.toDouble() ?? 0,
          (r['credit'] as num?)?.toDouble() ?? 0,
        ),
    ];
  }

  // ─── Form values ──────────────────────────────────────────────────────────

  double _value(LedgerAccount account) {
    final text = _ctrls[account.id!]?.text.replaceAll(',', '').trim() ?? '';
    return double.tryParse(text) ?? 0;
  }

  double get _totalDebits => _accounts
      .where((a) => _debitTypes.contains(a.accountType))
      .fold(0.0, (s, a) => s + _value(a));

  double get _totalCredits => _accounts
      .where((a) => !_debitTypes.contains(a.accountType))
      .fold(0.0, (s, a) => s + _value(a));

  // Compared in whole paise — inputs allow 2 decimal places, and IEEE-754
  // doubles cannot represent most paise values exactly, so a strict ==
  // (or a sub-paise tolerance) would wrongly block genuinely balanced totals.
  bool get _isBalanced =>
      ((_totalDebits - _totalCredits) * 100).round() == 0 && _totalDebits > 0;

  static String _fmtDate(String iso) {
    final p = iso.split('T').first.split('-');
    if (p.length < 3) return iso;
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  // ─── Submit ───────────────────────────────────────────────────────────────

  Future<void> _confirmAndPost() async {
    final nonZero = _accounts.where((a) => _value(a) > 0).toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Post Opening Balance?',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('One journal entry dated ${_fmtDate(_startDate)}:',
                    style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 10),
                ...nonZero.map((a) {
                  final debit = _debitTypes.contains(a.accountType);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(a.name,
                              style: const TextStyle(fontSize: 14)),
                        ),
                        Text(
                            '${debit ? 'Dr' : 'Cr'} '
                            '${LedgerAmountFormatter.format(_value(a))}',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: debit
                                    ? FlowColors.green
                                    : FlowColors.red)),
                      ],
                    ),
                  );
                }),
                const Divider(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total (each side)',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(LedgerAmountFormatter.format(_totalDebits),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'This is a one-time action and cannot be edited afterward. '
                  'A mistake found later can only be corrected with a '
                  'reversing entry plus a new corrected entry.',
                  style: TextStyle(
                      fontSize: 13,
                      color: FlowColors.red,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: FlowColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONFIRM & POST',
                style: TextStyle(color: FlowColors.textOnNavyLarge)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final lines = <OpeningBalanceLine>[];
      final auditLines = <Map<String, dynamic>>[];
      for (final a in nonZero) {
        final debit = _debitTypes.contains(a.accountType);
        final amount = _value(a);
        lines.add(OpeningBalanceLine(
          accountId: a.id!,
          debit: debit ? amount : 0,
          credit: debit ? 0 : amount,
        ));
        auditLines.add({
          'code': a.code,
          'account': a.name,
          'type': a.accountType,
          if (debit) 'debit': amount else 'credit': amount,
        });
      }
      await LedgerPostingService.instance.postOpeningBalance(
        lines: lines,
        auditJson: jsonEncode({
          'entry_date': _startDate,
          'total_debits': _totalDebits,
          'total_credits': _totalCredits,
          'lines': auditLines,
        }),
      );

      _posted = true;
      await _loadPostedSummary();
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Opening balance posted successfully')));
    } on LedgerPostingException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to post the opening balance. Please try again.';
        _saving = false;
      });
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Opening Balance Setup'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _posted
              ? _postedView()
              : _wizardForm(),
      bottomNavigationBar: _loading || _posted ? null : _totalsBar(),
    );
  }

  // ── Posted (read-only) state ──────────────────────────────────────────────

  Widget _postedView() {
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 16, 16, 32).withNavBarInset(context),
      children: [
        FlowCard(
          borderColor: FlowColors.green,
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: FlowColors.green, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Opening balance posted on '
                      '${_postedAt != null ? _fmtDate(_postedAt!) : '—'}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('Entry dated ${_fmtDate(_startDate)}',
                        style: const TextStyle(
                            fontSize: 13, color: FlowColors.medText)),
                  ],
                ),
              ),
            ],
          ),
        ),
        FlowCard(
          header: 'POSTED ENTRY',
          child: Column(
            children: [
              ..._postedLines.map((l) {
                final isDebit = l.debit > 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(l.name,
                            style: const TextStyle(fontSize: 15)),
                      ),
                      Text(
                        '${isDebit ? 'Dr' : 'Cr'} '
                        '${LedgerAmountFormatter.format(isDebit ? l.debit : l.credit)}',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDebit
                                ? FlowColors.green
                                : FlowColors.red),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'This entry cannot be edited. If a figure is wrong, correct it '
            'with a reversing entry plus a new corrected entry.',
            style: TextStyle(fontSize: 13, color: FlowColors.medText),
          ),
        ),
      ],
    );
  }

  // ── Wizard form ───────────────────────────────────────────────────────────

  Widget _wizardForm() {
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 16, 16, 24).withNavBarInset(context),
      children: [
        FlowCard(
          child: Text(
            'Enter the business position as of ${_fmtDate(_startDate)}. '
            'All figures are typed in manually — nothing is pre-filled. '
            'The entry posts once, only when debits and credits match.',
            style: const TextStyle(fontSize: 14, color: FlowColors.medText),
          ),
        ),
        for (final (type, title) in _sections) ..._section(type, title),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(_error!,
                style: const TextStyle(color: FlowColors.red, fontSize: 14)),
          ),
      ],
    );
  }

  List<Widget> _section(String type, String title) {
    final accounts =
        _accounts.where((a) => a.accountType == type).toList();
    if (accounts.isEmpty) return const [];
    // Sections 4-5 are accumulated April–June period totals, not
    // point-in-time balances — labelled so the user cannot mistake them.
    final isPeriodTotal =
        type == LedgerAccountType.income || type == LedgerAccountType.expense;
    final subtitle = isPeriodTotal
        ? 'Total for April – June (not a balance)'
        : 'Balance as on ${_fmtDate(_startDate)}';
    final isDebitSide = _debitTypes.contains(type);

    return [
      FlowCard(
        header: '$title — ${isDebitSide ? 'DEBIT' : 'CREDIT'} SIDE',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: FlowColors.medText)),
            const SizedBox(height: 12),
            ...accounts.map(_amountField),
          ],
        ),
      ),
    ];
  }

  Widget _amountField(LedgerAccount account) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _ctrls[account.id!],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        // Ledger amounts carry paise — unlike pledge/loan fields, which stay
        // whole-number-only elsewhere in the app.
        inputFormatters: [LedgerDecimalInputFormatter()],
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: account.name,
          prefixText: '₹ ',
          hintText: '0',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setState(() {
          if (_error != null) _error = null;
        }),
      ),
    );
  }

  // ── Live totals + submit bar ──────────────────────────────────────────────

  Widget _totalsBar() {
    final diff = _totalDebits - _totalCredits;
    final balanced = _isBalanced;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 8,
                offset: Offset(0, -2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _totalCell('Total Debits', _totalDebits, FlowColors.green),
                _totalCell('Total Credits', _totalCredits, FlowColors.red),
                _totalCell(
                  'Difference',
                  diff.abs(),
                  diff.abs() < 0.005 ? FlowColors.green : FlowColors.orange,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: balanced && !_saving ? _confirmAndPost : null,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: FlowColors.goldRich))
                    : const Icon(Icons.playlist_add_check, size: 22),
                label: Text(
                  balanced
                      ? 'POST OPENING BALANCE'
                      : 'DEBITS AND CREDITS MUST MATCH',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.primary,
                  foregroundColor: FlowColors.goldRich,
                  disabledBackgroundColor: Colors.black12,
                  disabledForegroundColor: Colors.black38,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalCell(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: FlowColors.medText)),
        Text(LedgerAmountFormatter.format(value),
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
