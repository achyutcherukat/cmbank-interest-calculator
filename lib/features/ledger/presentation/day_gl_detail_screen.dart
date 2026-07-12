import 'package:flutter/material.dart';

import '../../../core/services/ledger_report_service.dart';
import '../../../core/utils/ledger_amount_formatter.dart';
import '../../../shared/widgets/flow_widgets.dart';
import 'journal_entry_detail_screen.dart';
import 'ledger_report_widgets.dart';

/// Drill-down level 1 for the grouped daily General Ledger view.
/// Shows all individual journal lines for one account on one date and
/// direction (Dr or Cr). Tapping any line opens [JournalEntryDetailScreen].
class DayGlDetailScreen extends StatelessWidget {
  const DayGlDetailScreen({
    required this.accountName,
    required this.date,
    required this.isCredit,
    required this.priorBalance,
    required this.lines,
    super.key,
  });

  final String accountName;
  final String date;
  final bool isCredit;
  final double priorBalance;
  final List<GeneralLedgerLine> lines;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(accountName,
                style: const TextStyle(fontSize: 16)),
            Text(
              '${isoToDisplay(date)}  —  ${isCredit ? 'Cr' : 'Dr'} entries',
              style: const TextStyle(
                  fontSize: 12, color: FlowColors.textOnNavySmall),
            ),
          ],
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    var running = priorBalance;
    final rows = <Widget>[];
    for (final line in lines) {
      running += line.debit - line.credit;
      rows.add(_lineRow(context, line, running));
    }
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(16, 14, 16, 32).withNavBarInset(context),
      children: [
        FlowCard(
          padding: const EdgeInsets.all(0),
          child: Column(children: rows),
        ),
      ],
    );
  }

  Widget _lineRow(
      BuildContext context, GeneralLedgerLine line, double runningBalance) {
    final isDebit = line.debit > 0.005;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JournalEntryDetailScreen(entryId: line.entryId),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
              bottom: BorderSide(color: Color(0x14000000), width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (line.isReversed || line.isVirtual)
                    Row(children: [
                      if (line.isReversed) ...[
                        _tag('REVERSED', FlowColors.red),
                        const SizedBox(width: 6),
                      ],
                      if (line.isVirtual)
                        _tag('VIRTUAL', FlowColors.medText),
                      const SizedBox(height: 4),
                    ]),
                  Text(
                    line.narration,
                    style: TextStyle(
                        fontSize: 14,
                        color: line.isReversed
                            ? Colors.black38
                            : FlowColors.darkText,
                        decoration: line.isReversed
                            ? TextDecoration.lineThrough
                            : null),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isDebit
                      ? 'Dr ${LedgerAmountFormatter.format(line.debit)}'
                      : 'Cr ${LedgerAmountFormatter.format(line.credit)}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDebit ? FlowColors.green : FlowColors.red),
                ),
                Text('Bal ${drCr(runningBalance)}',
                    style: const TextStyle(
                        fontSize: 12, color: FlowColors.medText)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
