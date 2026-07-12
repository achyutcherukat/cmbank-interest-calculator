import 'package:flutter/material.dart';

import '../../../core/services/ledger_posting_service.dart';
import '../../../core/services/ledger_report_service.dart';
import '../../../core/utils/ledger_amount_formatter.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../admin/data/admin_repository.dart';

/// Full detail of one journal entry — narration, date, and EVERY line across
/// all accounts it touched (not just the account the General Ledger was
/// filtered to) — plus the sanctioned correction path: "Reverse This Entry".
///
/// Reversal posts a new MANUAL entry dated today with every line's
/// debit/credit flipped and marks the original reversed. Both entries stay
/// visible in the ledger afterwards — that is the audit trail, not clutter.
/// A reversal entry can itself be reversed later (no special restriction).
class JournalEntryDetailScreen extends StatefulWidget {
  const JournalEntryDetailScreen({super.key, required this.entryId});

  final int entryId;

  @override
  State<JournalEntryDetailScreen> createState() =>
      _JournalEntryDetailScreenState();
}

class _JournalEntryDetailScreenState extends State<JournalEntryDetailScreen> {
  JournalEntryHeader? _entry;
  List<JournalEntryDetailLine> _lines = [];
  bool _loading = true;
  bool _reversing = false;

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

  Future<void> _load() async {
    final service = LedgerReportService.instance;
    final entry = await service.getEntryHeader(widget.entryId);
    final lines = await service.getEntryLines(widget.entryId);
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _lines = lines;
      _loading = false;
    });
  }

  // ─── Reverse ──────────────────────────────────────────────────────────────

  Future<void> _confirmAndReverse() async {
    final entry = _entry;
    if (entry == null || entry.isReversed) return;

    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) => AlertDialog(
          title: const Text('Reverse This Entry?',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.red)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new entry dated today will post the exact opposite of '
                'every line in "${entry.narration}". Both entries remain '
                'visible in the ledger as the audit trail.',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Reason for reversal *',
                  hintText: 'e.g. "Wrong account selected"',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                onChanged: (_) => setDlg(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: FlowColors.red),
              onPressed: reasonCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx2, true),
              child: const Text('REVERSE ENTRY',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    final reason = reasonCtrl.text.trim();
    if (confirmed != true || !mounted) return;

    setState(() => _reversing = true);
    try {
      await LedgerPostingService.instance
          .reverseEntry(entry.id, reason);
      await _load();
      if (!mounted) return;
      setState(() => _reversing = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry reversed')));
    } on LedgerPostingException catch (e) {
      if (!mounted) return;
      setState(() => _reversing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _reversing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to reverse the entry. Please try again.')));
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
        title: Text('Journal Entry #${widget.entryId}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entry == null
              ? const Center(
                  child: Text('Entry not found.',
                      style:
                          TextStyle(fontSize: 16, color: Colors.black45)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 32)
                      .withNavBarInset(context),
                  children: [
                    if (_entry!.isReversed) _reversedBanner(),
                    _headerCard(),
                    _linesCard(),
                    if (!_entry!.isReversed) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed:
                              _reversing ? null : _confirmAndReverse,
                          icon: _reversing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: FlowColors.red))
                              : const Icon(Icons.undo, size: 20),
                          label: const Text('REVERSE THIS ENTRY',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: FlowColors.red,
                            side: BorderSide(
                                color:
                                    FlowColors.red.withValues(alpha: 0.6)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _reversedBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FlowColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FlowColors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.undo, color: FlowColors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This entry has been reversed'
              '${_entry!.reversedByEntryId != null ? ' by entry #${_entry!.reversedByEntryId}' : ''}.',
              style: const TextStyle(
                  fontSize: 13,
                  color: FlowColors.red,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard() {
    final entry = _entry!;
    return FlowCard(
      header: 'ENTRY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.narration,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(
            children: [
              _chip(isoToDisplay(entry.entryDate), Icons.event),
              const SizedBox(width: 8),
              _chip(entry.entryType, Icons.settings_suggest),
              const SizedBox(width: 8),
              _chip(entry.sourceType, Icons.link),
            ],
          ),
          const SizedBox(height: 8),
          Text('Recorded ${isoToDisplay(entry.createdAt)}',
              style: const TextStyle(
                  fontSize: 12, color: FlowColors.medText)),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FlowColors.accent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: FlowColors.primary),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: FlowColors.primary)),
        ],
      ),
    );
  }

  Widget _linesCard() {
    final drTotal = _lines.fold(0.0, (s, l) => s + l.debit);
    final crTotal = _lines.fold(0.0, (s, l) => s + l.credit);
    return FlowCard(
      header: 'LINES — ALL ACCOUNTS',
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          for (final line in _lines)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                    bottom:
                        BorderSide(color: Color(0x14000000), width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(line.accountName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (line.isVirtual) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: FlowColors.medText
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                      color: FlowColors.medText
                                          .withValues(alpha: 0.4)),
                                ),
                                child: const Text('VIRTUAL',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: FlowColors.medText)),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          line.accountCode +
                              (line.pledgeNo != null
                                  ? '  ·  Pledge #${line.pledgeNo}'
                                  : ''),
                          style: const TextStyle(
                              fontSize: 11, color: FlowColors.medText),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    line.debit > 0
                        ? 'Dr ${LedgerAmountFormatter.format(line.debit)}'
                        : 'Cr ${LedgerAmountFormatter.format(line.credit)}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: line.debit > 0
                            ? FlowColors.green
                            : FlowColors.red),
                  ),
                ],
              ),
            ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: FlowColors.accent,
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Totals',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: FlowColors.primary)),
                Text(
                  'Dr ${LedgerAmountFormatter.format(drTotal)}   '
                  'Cr ${LedgerAmountFormatter.format(crTotal)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
