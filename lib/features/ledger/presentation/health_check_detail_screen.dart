import 'package:flutter/material.dart';

import '../../../core/services/ledger_health_check_service.dart';
import '../../../core/services/ledger_posting_service.dart';
import '../../../core/utils/ledger_amount_formatter.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../admin/data/admin_repository.dart';
import '../../pledges/presentation/open_pledge_screen.dart';

/// Detail view for the Trial Balance health check (Prompt 10): the specific
/// Cash/Bank mismatches (Check A) and the transactions missing from the ledger
/// (Check B), with a one-tap, idempotent re-post remedy for Check B.
///
/// Admin-gated like the rest of the Ledger section.
class HealthCheckDetailScreen extends StatefulWidget {
  const HealthCheckDetailScreen({super.key, required this.result});

  final HealthCheckResult result;

  @override
  State<HealthCheckDetailScreen> createState() =>
      _HealthCheckDetailScreenState();
}

class _HealthCheckDetailScreenState extends State<HealthCheckDetailScreen> {
  late HealthCheckResult _result = widget.result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!AdminSession.isValid && mounted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => Navigator.pop(context));
    }
  }

  Future<void> _refresh() async {
    final refreshed = await LedgerHealthCheckService.instance.run();
    if (!mounted) return;
    setState(() => _result = refreshed);
  }

  // ─── Re-run posting for the affected dates (Check B remedy) ─────────────────

  Future<void> _rerunPosting() async {
    final dates = _result.affectedDates;
    if (dates.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-run Posting?'),
        content: Text(
          'This will re-post journal entries for ${dates.length} '
          'affected ${dates.length == 1 ? 'date' : 'dates'}. It only fills in '
          'entries that are genuinely missing — nothing already posted is '
          'duplicated or changed.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: FlowColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RE-RUN',
                style: TextStyle(color: FlowColors.textOnNavyLarge)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      for (final date in dates) {
        await LedgerPostingService.instance.postForDate(date);
      }
      final refreshed = await LedgerHealthCheckService.instance.run();
      if (!mounted) return;
      setState(() {
        _result = refreshed;
        _busy = false;
      });
      messenger.showSnackBar(SnackBar(
        content: Text(refreshed.missingPostings.isEmpty
            ? 'Posting complete — no missing entries remain.'
            : '${refreshed.missingPostings.length} record(s) still appear '
                'missing. Investigate manually.'),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not re-run posting. Please try again.')));
    }
  }

  void _openRecord(MissingPosting m) {
    if (m.pledgeId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => m.pledgeClosed
            ? ClosedPledgeDetailScreen(pledgeId: m.pledgeId!)
            : PledgeDetailScreen(pledgeId: m.pledgeId!, hideActions: true),
      ),
    ).then((_) => _refresh());
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cashBank = _result.cashBankMismatches;
    final missing = _result.missingPostings;
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Health Check'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32)
                .withNavBarInset(context),
            children: [
              if (!_result.hasIssues)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(
                    child: Text('All checks pass — nothing to review.',
                        style:
                            TextStyle(fontSize: 16, color: Colors.black45)),
                  ),
                ),
              if (cashBank.isNotEmpty) ...[
                _sectionTitle('Cash / Bank vs Cash Book'),
                _cashBankCard(cashBank),
              ],
              if (missing.isNotEmpty) ...[
                _sectionTitle('Missing from the Ledger'),
                _missingCard(missing),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlowColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _busy ? null : _rerunPosting,
                    icon: const Icon(Icons.refresh,
                        color: FlowColors.textOnNavyLarge),
                    label: const Text('Re-run Posting for Affected Dates',
                        style: TextStyle(
                            color: FlowColors.textOnNavyLarge,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
      child: Text(title.toUpperCase(),
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
              letterSpacing: 0.5)),
    );
  }

  // ─── Check A card ────────────────────────────────────────────────────────────

  Widget _cashBankCard(List<CashBankMismatch> rows) {
    return FlowCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const Border(
                        bottom:
                            BorderSide(color: Color(0x14000000), width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(rows[i].accountName,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        'Diff ${LedgerAmountFormatter.format(rows[i].difference)}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: FlowColors.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _kv('Ledger',
                      LedgerAmountFormatter.format(rows[i].ledgerBalance)),
                  _kv('Cash Book',
                      LedgerAmountFormatter.format(rows[i].cashBookBalance)),
                  _kv('As of', isoToDisplay(rows[i].asOfDate)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: FlowColors.medText)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  color: FlowColors.darkText,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ─── Check B card ────────────────────────────────────────────────────────────

  Widget _missingCard(List<MissingPosting> rows) {
    return FlowCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            InkWell(
              onTap: rows[i].pledgeId == null ? null : () => _openRecord(rows[i]),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: i == rows.length - 1
                      ? null
                      : const Border(
                          bottom:
                              BorderSide(color: Color(0x14000000), width: 1)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rows[i].typeLabel,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            [
                              isoToDisplay(rows[i].date),
                              if (rows[i].pledgeNo != null)
                                'Pledge #${rows[i].pledgeNo}',
                            ].join('  •  '),
                            style: const TextStyle(
                                fontSize: 12, color: FlowColors.medText),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(LedgerAmountFormatter.format(rows[i].amount),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        if (rows[i].pledgeId != null)
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.chevron_right,
                                size: 18, color: FlowColors.medText),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
