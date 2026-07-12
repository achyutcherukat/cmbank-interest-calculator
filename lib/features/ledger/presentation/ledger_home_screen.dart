import 'package:flutter/material.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../../admin/data/admin_repository.dart';
import 'balance_sheet_screen.dart';
import 'day_book_screen.dart';
import 'general_ledger_screen.dart';
import 'manual_journal_entry_screen.dart';
import 'profit_loss_screen.dart';
import 'trial_balance_screen.dart';
import 'year_end_closing_screen.dart';

/// Ledger section of the Admin Area. Lists the ledger reports — P&L and
/// Balance Sheet join this list in a later prompt, so options stay a plain
/// data list rather than a fixed two-item layout.
class LedgerHomeScreen extends StatefulWidget {
  const LedgerHomeScreen({super.key});

  @override
  State<LedgerHomeScreen> createState() => _LedgerHomeScreenState();
}

class _LedgerHomeScreenState extends State<LedgerHomeScreen> {
  @override
  void initState() {
    super.initState();
    if (!AdminSession.isValid && mounted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => Navigator.pop(context));
    }
  }

  static final _options = <({
    IconData icon,
    String label,
    String subtitle,
    Widget Function() builder,
  })>[
    (
      icon: Icons.menu_book,
      label: 'General Ledger',
      subtitle: 'Per-account transaction listing with running balance',
      builder: () => const GeneralLedgerScreen(),
    ),
    (
      icon: Icons.balance,
      label: 'Trial Balance',
      subtitle: 'All-account balance summary as of a date',
      builder: () => const TrialBalanceScreen(),
    ),
    (
      icon: Icons.today,
      label: 'Day Book',
      subtitle: 'All ledger entries posted on one date',
      builder: () => const DayBookScreen(),
    ),
    (
      icon: Icons.trending_up,
      label: 'Profit & Loss',
      subtitle: 'Income and expenses for a period',
      builder: () => const ProfitLossScreen(),
    ),
    (
      icon: Icons.account_balance,
      label: 'Balance Sheet',
      subtitle: 'Assets vs liabilities & capital as of a date',
      builder: () => const BalanceSheetScreen(),
    ),
    (
      icon: Icons.edit_note,
      label: 'Manual Journal Entry',
      subtitle: 'Post a non-routine entry to any account',
      builder: () => const ManualJournalEntryScreen(),
    ),
    (
      icon: Icons.event_available,
      label: 'Year-End Closing',
      subtitle: 'Close a financial year to Partner Capital',
      builder: () => const YearEndClosingScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Ledger',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 20, 16, 40).withNavBarInset(context),
        children: [
          for (final option in _options) ...[
            FlowCard(
              padding: const EdgeInsets.all(0),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 8),
                leading:
                    Icon(option.icon, color: FlowColors.primary, size: 28),
                title: Text(option.label,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                subtitle: Text(option.subtitle,
                    style: const TextStyle(
                        fontSize: 13, color: FlowColors.medText)),
                trailing: const Icon(Icons.chevron_right),
                minVerticalPadding: 14,
                onTap: () {
                  if (!AdminSession.isValid) {
                    Navigator.pop(context);
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => option.builder()),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
