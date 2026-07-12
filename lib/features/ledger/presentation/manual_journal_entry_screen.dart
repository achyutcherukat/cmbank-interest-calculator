import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/services/ledger_posting_service.dart';
import '../../../core/utils/ledger_amount_formatter.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../admin/data/admin_repository.dart';
import '../data/chart_of_accounts_repository.dart';
import '../data/ledger_account_model.dart';

/// General-purpose manual journal entry (admin-only): post to ANY active
/// ledger account when no app flow covers it — standalone-asset purchases,
/// the eventual year-end profit transfer, CA-provided depreciation, etc.
///
/// Deliberately independent of Cash Book day-locking: these entries have no
/// `payments` counterpart and never touch daily_balance/daily_stock, so lock
/// state is irrelevant. Mistakes are corrected by reversing the posted entry
/// from its Entry Detail view, not by editing.
class ManualJournalEntryScreen extends StatefulWidget {
  const ManualJournalEntryScreen({super.key});

  @override
  State<ManualJournalEntryScreen> createState() =>
      _ManualJournalEntryScreenState();
}

class _EntryLine {
  _EntryLine();
  int? accountId;
  bool isDebit = true;
  final amountCtrl = TextEditingController();

  void dispose() => amountCtrl.dispose();
}

class _ManualJournalEntryScreenState extends State<ManualJournalEntryScreen> {
  List<LedgerAccount> _accounts = [];
  DateTime _date = DateTime.now();
  final _narrationCtrl = TextEditingController();
  final List<_EntryLine> _lines = [_EntryLine(), _EntryLine()];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
    _narrationCtrl.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final all = await ChartOfAccountsRepository.instance.getAll();
    if (!mounted) return;
    setState(() {
      _accounts = all.where((a) => a.isActive).toList();
      _loading = false;
    });
  }

  // ─── Totals ───────────────────────────────────────────────────────────────

  double _lineAmount(_EntryLine line) =>
      double.tryParse(line.amountCtrl.text.replaceAll(',', '').trim()) ?? 0;

  double get _totalDebits => _lines
      .where((l) => l.isDebit)
      .fold(0.0, (s, l) => s + _lineAmount(l));

  double get _totalCredits => _lines
      .where((l) => !l.isDebit)
      .fold(0.0, (s, l) => s + _lineAmount(l));

  // Paise-exact comparison, per the ledger's decimal-handling convention.
  bool get _isBalanced =>
      ((_totalDebits - _totalCredits) * 100).round() == 0 &&
      _totalDebits > 0;

  // ─── Save ─────────────────────────────────────────────────────────────────

  Future<void> _confirmAndSave() async {
    final narration = _narrationCtrl.text.trim();
    if (narration.isEmpty) {
      setState(() => _error = 'Narration is required.');
      return;
    }
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].accountId == null) {
        setState(() => _error = 'Line ${i + 1}: select an account.');
        return;
      }
      if (_lineAmount(_lines[i]) <= 0) {
        setState(() => _error = 'Line ${i + 1}: enter an amount above zero.');
        return;
      }
    }

    String accountName(int id) =>
        _accounts.firstWhere((a) => a.id == id).name;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Post Journal Entry?',
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
                Text('Dated ${isoToDisplay(_iso(_date))} — "$narration"',
                    style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 10),
                ..._lines.map((l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(accountName(l.accountId!),
                                style: const TextStyle(fontSize: 14)),
                          ),
                          Text(
                            '${l.isDebit ? 'Dr' : 'Cr'} '
                            '${LedgerAmountFormatter.format(_lineAmount(l))}',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: l.isDebit
                                    ? FlowColors.green
                                    : FlowColors.red),
                          ),
                        ],
                      ),
                    )),
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
                const SizedBox(height: 10),
                const Text(
                  'A posted entry cannot be edited — a mistake is corrected '
                  'by reversing it from the entry\'s detail view.',
                  style: TextStyle(
                      fontSize: 13,
                      color: FlowColors.medText,
                      fontWeight: FontWeight.w500),
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
            style:
                ElevatedButton.styleFrom(backgroundColor: FlowColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('POST ENTRY',
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
      final lines = <ManualJournalLine>[];
      final auditLines = <Map<String, dynamic>>[];
      for (final l in _lines) {
        final amount = _lineAmount(l);
        lines.add(ManualJournalLine(
          accountId: l.accountId!,
          debit: l.isDebit ? amount : 0,
          credit: l.isDebit ? 0 : amount,
        ));
        auditLines.add({
          'account': accountName(l.accountId!),
          if (l.isDebit) 'debit': amount else 'credit': amount,
        });
      }
      await LedgerPostingService.instance.postManualEntry(
        entryDate: _iso(_date),
        narration: narration,
        lines: lines,
        auditJson: jsonEncode({
          'entry_date': _iso(_date),
          'narration': narration,
          'total': _totalDebits,
          'lines': auditLines,
        }),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Journal entry posted')));
      Navigator.pop(context, true);
    } on LedgerPostingException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to post the entry. Please try again.';
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
        title: const Text('Manual Journal Entry'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24)
                  .withNavBarInset(context),
              children: [
                FlowCard(
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked == null || !mounted) return;
                          setState(() => _date = picked);
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Entry Date',
                            border: OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: Icon(Icons.calendar_today_outlined,
                                size: 16),
                          ),
                          child: Text(isoToDisplay(_iso(_date)),
                              style: const TextStyle(fontSize: 14)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _narrationCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Narration *',
                          hintText: 'What is this entry for?',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < _lines.length; i++) _lineCard(i),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _lines.add(_EntryLine())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('ADD LINE'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FlowColors.primary,
                    side: const BorderSide(color: FlowColors.primaryLight),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: FlowColors.red, fontSize: 14)),
                  ),
              ],
            ),
      bottomNavigationBar: _loading ? null : _totalsBar(),
    );
  }

  Widget _lineCard(int index) {
    final line = _lines[index];
    return FlowCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _accountDropdown(line)),
              if (_lines.length > 2)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: FlowColors.red),
                  tooltip: 'Remove line',
                  onPressed: () => setState(() {
                    _lines.removeAt(index).dispose();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _drCrToggle(line),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: line.amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [LedgerDecimalInputFormatter()],
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹) *',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {
                    if (_error != null) _error = null;
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _drCrToggle(_EntryLine line) {
    return ToggleButtons(
      isSelected: [line.isDebit, !line.isDebit],
      onPressed: (i) => setState(() => line.isDebit = i == 0),
      borderRadius: BorderRadius.circular(8),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
      selectedColor: Colors.white,
      fillColor: line.isDebit ? FlowColors.green : FlowColors.red,
      color: FlowColors.medText,
      children: const [
        Text('Dr', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('Cr', style: TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _accountDropdown(_EntryLine line) {
    final items = <DropdownMenuItem<int>>[];
    for (final type in LedgerAccountType.all) {
      final group = _accounts.where((a) => a.accountType == type).toList();
      if (group.isEmpty) continue;
      items.add(DropdownMenuItem<int>(
        enabled: false,
        child: Text(
          LedgerAccountType.label(type).toUpperCase(),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: FlowColors.medText,
              letterSpacing: 0.5),
        ),
      ));
      items.addAll(group.map((a) => DropdownMenuItem<int>(
            value: a.id,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text('${a.code}  ${a.name}',
                  overflow: TextOverflow.ellipsis),
            ),
          )));
    }
    return DropdownButtonFormField<int>(
      initialValue: line.accountId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Account *',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: items,
      selectedItemBuilder: (context) => [
        for (final item in items)
          Align(
            alignment: Alignment.centerLeft,
            child: item.value == null
                ? const SizedBox.shrink()
                : Text(
                    _accounts.firstWhere((a) => a.id == item.value).name,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
      ],
      onChanged: (v) => setState(() {
        line.accountId = v;
        if (_error != null) _error = null;
      }),
    );
  }

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
                _totalCell('Total Debit', _totalDebits, FlowColors.green),
                _totalCell('Total Credit', _totalCredits, FlowColors.red),
                _totalCell(
                  'Difference',
                  diff.abs(),
                  (diff * 100).round() == 0
                      ? FlowColors.green
                      : FlowColors.orange,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: balanced && !_saving ? _confirmAndSave : null,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: FlowColors.goldRich))
                    : const Icon(Icons.playlist_add_check, size: 22),
                label: Text(
                  balanced
                      ? 'POST JOURNAL ENTRY'
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
