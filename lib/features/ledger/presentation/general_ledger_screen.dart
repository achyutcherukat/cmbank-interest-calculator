import 'package:flutter/material.dart';

import '../../../core/services/ledger_report_service.dart';
import '../../../core/services/print_service.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../core/utils/ledger_amount_formatter.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../admin/data/admin_repository.dart';
import '../data/chart_of_accounts_repository.dart';
import '../data/ledger_account_model.dart';
import '../ledger_print_reports.dart';
import 'day_gl_detail_screen.dart';
import 'journal_entry_detail_screen.dart';
import 'ledger_report_widgets.dart';

/// General Ledger: per-account transaction listing with a date range,
/// opening/closing balance rows and a running balance column.
///
/// The "show virtual entries" toggle affects display only — virtual pairs
/// net to zero within an entry, so the running balance closes correctly
/// whether they are shown or hidden. Reversed entries are always included in
/// the list AND the sums (they cancel against their reversal); they are just
/// tagged visually.
class GeneralLedgerScreen extends StatefulWidget {
  const GeneralLedgerScreen({
    super.key,
    this.initialAccountId,
    this.initialFrom,
    this.initialTo,
  });

  final int? initialAccountId;
  final DateTime? initialFrom;
  final DateTime? initialTo;

  @override
  State<GeneralLedgerScreen> createState() => _GeneralLedgerScreenState();
}

class _GeneralLedgerScreenState extends State<GeneralLedgerScreen> {
  final _settings = AppSettingsRepository();

  List<LedgerAccount> _accounts = [];
  int? _accountId;
  late DateTime _from;
  late DateTime _to;
  bool _showVirtual = false;

  bool _openingPosted = true;
  String _ledgerStartDate = '';

  List<GeneralLedgerLine> _lines = [];
  double _openingBalance = 0;
  double _closingBalance = 0;
  bool _loading = true;

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _display(DateTime d) => isoToDisplay(_iso(d));

  LedgerAccount? get _selectedAccount {
    if (_accountId == null) return null;
    for (final a in _accounts) {
      if (a.id == _accountId) return a;
    }
    return null;
  }

  bool get _isGroupedAccount =>
      LedgerReportService.groupedViewCodes.contains(_selectedAccount?.code);

  @override
  void initState() {
    super.initState();
    if (!AdminSession.isValid && mounted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => Navigator.pop(context));
      return;
    }
    final now = DateTime.now();
    _from = widget.initialFrom ?? DateTime(now.year, now.month, 1);
    _to = widget.initialTo ?? now;
    _load();
  }

  Future<void> _load() async {
    final all = await ChartOfAccountsRepository.instance.getAll();
    _accounts = all.where((a) => a.isActive).toList();
    _accountId = widget.initialAccountId ??
        (_accounts.isNotEmpty ? _accounts.first.id : null);
    _openingPosted = await _settings.getBool('ledger_opening_posted');
    _ledgerStartDate = await _settings.getString('ledger_start_date') ?? '';
    await _loadReport();
  }

  Future<void> _loadReport() async {
    final accountId = _accountId;
    if (accountId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final service = LedgerReportService.instance;
    final dayBeforeFrom = _iso(_from.subtract(const Duration(days: 1)));
    final opening = await service.getAccountBalance(accountId, dayBeforeFrom);
    final lines = await service.getAccountLines(
      accountId,
      _iso(_from),
      _iso(_to),
      includeVirtual: _showVirtual,
    );
    final closing = await service.getAccountBalance(accountId, _iso(_to));
    if (!mounted) return;
    setState(() {
      _openingBalance = opening;
      _lines = lines;
      _closingBalance = closing;
      _loading = false;
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
    _loadReport();
  }

  // ─── Print / Save PDF ─────────────────────────────────────────────────────

  /// Options dialog before generating: scope (this account / all accounts),
  /// include-virtual (defaults to the on-screen toggle but independent of
  /// it — useful for auditing renewal gross legs even while the screen hides
  /// them), and an editable date range defaulting to the screen's filters.
  Future<void> _showPrintDialog() async {
    var allAccounts = false;
    var includeVirtual = _showVirtual;
    var from = _from;
    var to = _to;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) {
          Future<void> pickDate({required bool isFrom}) async {
            final picked = await showDatePicker(
              context: ctx2,
              initialDate: isFrom ? from : to,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              helpText: isFrom ? 'From Date' : 'To Date',
            );
            if (picked == null) return;
            setDlg(() {
              if (isFrom) {
                from = picked;
                if (to.isBefore(from)) to = from;
              } else {
                to = picked;
                if (from.isAfter(to)) from = to;
              }
            });
          }

          Widget dateField(String label, DateTime value,
              {required bool isFrom}) {
            return Expanded(
              child: InkWell(
                onTap: () => pickDate(isFrom: isFrom),
                borderRadius: BorderRadius.circular(6),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: Text(_display(value),
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            );
          }

          return AlertDialog(
            title: const Text('Print General Ledger',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.primary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioGroup<bool>(
                  groupValue: allAccounts,
                  onChanged: (v) =>
                      setDlg(() => allAccounts = v ?? false),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('This Account Only',
                            style: TextStyle(fontSize: 14)),
                        value: false,
                        activeColor: FlowColors.primary,
                      ),
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('All Accounts',
                            style: TextStyle(fontSize: 14)),
                        subtitle: Text(
                            'Every active account, grouped by type',
                            style: TextStyle(fontSize: 12)),
                        value: true,
                        activeColor: FlowColors.primary,
                      ),
                    ],
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Include virtual entries',
                      style: TextStyle(fontSize: 14)),
                  value: includeVirtual,
                  activeColor: FlowColors.primary,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) =>
                      setDlg(() => includeVirtual = v ?? false),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    dateField('From', from, isFrom: true),
                    const SizedBox(width: 10),
                    dateField('To', to, isFrom: false),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx2),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx2, 'save'),
                child: const Text('SAVE PDF',
                    style: TextStyle(color: FlowColors.primary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: FlowColors.primary),
                onPressed: () => Navigator.pop(ctx2, 'print'),
                child: const Text('PRINT',
                    style: TextStyle(color: FlowColors.textOnNavyLarge)),
              ),
            ],
          );
        },
      ),
    );
    if (action == null || !mounted) return;

    await _generatePdf(
      save: action == 'save',
      allAccounts: allAccounts,
      includeVirtual: includeVirtual,
      from: from,
      to: to,
    );
  }

  Future<void> _generatePdf({
    required bool save,
    required bool allAccounts,
    required bool includeVirtual,
    required DateTime from,
    required DateTime to,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final doc = await LedgerPrintReports.generalLedger(
        accountId: allAccounts ? null : _accountId,
        fromDate: _iso(from),
        toDate: _iso(to),
        includeVirtual: includeVirtual,
      );
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading

      final scopeTag = allAccounts
          ? 'AllAccounts'
          : _accounts.firstWhere((a) => a.id == _accountId).code;
      final stamp = '${LedgerPrintReports.fileStamp(_iso(from))}_to_'
          '${LedgerPrintReports.fileStamp(_iso(to))}';

      if (save) {
        await PrintService.saveAsPdf(
          pdf: doc,
          fileName: '${LedgerPrintReports.filePrefix}_GeneralLedger_'
              '${scopeTag}_$stamp.pdf',
          context: context,
        );
      } else {
        await PrintService.printDocument(
          pdf: doc,
          documentName:
              'General Ledger ${_display(from)} to ${_display(to)}',
        );
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not generate the PDF. Please try again.')));
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
        title: const Text('General Ledger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print / Save PDF',
            onPressed:
                _loading || _accountId == null ? null : _showPrintDialog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          if (!_openingPosted)
            OpeningBalancePendingBanner(ledgerStartDate: _ledgerStartDate),
          _controlsCard(),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_accountId == null)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(
                  child: Text('No ledger accounts found.',
                      style:
                          TextStyle(fontSize: 16, color: Colors.black45))),
            )
          else
            _reportCard(),
        ],
      ),
    );
  }

  Widget _controlsCard() {
    return FlowCard(
      child: Column(
        children: [
          _accountDropdown(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _dateField('From', _from, isFrom: true)),
              const SizedBox(width: 10),
              Expanded(child: _dateField('To', _to, isFrom: false)),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Show virtual entries',
                style: TextStyle(fontSize: 14)),
            subtitle: const Text(
                'Non-cash renewal legs (display only — balances are '
                'unaffected)',
                style: TextStyle(fontSize: 12, color: FlowColors.medText)),
            value: _showVirtual,
            activeThumbColor: FlowColors.primary,
            onChanged: (v) {
              setState(() => _showVirtual = v);
              _loadReport();
            },
          ),
        ],
      ),
    );
  }

  Widget _accountDropdown() {
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
      initialValue: _accountId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Account',
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
                    _accounts
                        .firstWhere((a) => a.id == item.value)
                        .name,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => _accountId = v);
        _loadReport();
      },
    );
  }

  Widget _dateField(String label, DateTime value, {required bool isFrom}) {
    return InkWell(
      onTap: () => _pickDate(isFrom: isFrom),
      borderRadius: BorderRadius.circular(6),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
        ),
        child: Text(_display(value), style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  // ─── Report body ──────────────────────────────────────────────────────────

  Widget _reportCard() {
    if (_lines.isEmpty &&
        _openingBalance.abs() < 0.005 &&
        _closingBalance.abs() < 0.005) {
      return const Padding(
        padding: EdgeInsets.only(top: 50),
        child: Center(
          child: Text('No transactions in this period',
              style: TextStyle(fontSize: 16, color: Colors.black45)),
        ),
      );
    }

    final lineRows = <Widget>[];
    if (_isGroupedAccount) {
      final groups = LedgerReportService.groupByDay(_lines, _openingBalance);
      for (final group in groups) {
        lineRows.add(_groupedRow(group));
      }
    } else {
      var running = _openingBalance;
      for (final line in _lines) {
        running += line.debit - line.credit;
        lineRows.add(_lineRow(line, running));
      }
    }

    return FlowCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          _balanceRow('Opening Balance', _display(_from), _openingBalance),
          if (_lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No transactions in this period',
                  style: TextStyle(fontSize: 15, color: Colors.black45)),
            )
          else
            ...lineRows,
          _balanceRow('Closing Balance', _display(_to), _closingBalance,
              emphasized: true),
        ],
      ),
    );
  }

  Widget _balanceRow(String label, String date, double balance,
      {bool emphasized = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: emphasized ? FlowColors.primary : FlowColors.accent,
        borderRadius: BorderRadius.vertical(
          top: label == 'Opening Balance'
              ? const Radius.circular(12)
              : Radius.zero,
          bottom: emphasized ? const Radius.circular(12) : Radius.zero,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: emphasized
                            ? FlowColors.textOnNavyLarge
                            : FlowColors.primary)),
                Text(date,
                    style: TextStyle(
                        fontSize: 12,
                        color: emphasized
                            ? FlowColors.textOnNavySmall
                            : FlowColors.medText)),
              ],
            ),
          ),
          Text(drCr(balance),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: emphasized
                      ? FlowColors.goldRich
                      : FlowColors.primary)),
        ],
      ),
    );
  }

  Widget _groupedRow(DayGroupedLine group) {
    final isCredit = group.isCredit;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DayGlDetailScreen(
            accountName: _selectedAccount?.name ?? '',
            date: group.date,
            isCredit: group.isCredit,
            priorBalance: group.priorBalance,
            lines: group.lines,
          ),
        ),
      ).then((_) => _loadReport()),
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
                  Text(isoToDisplay(group.date),
                      style: const TextStyle(
                          fontSize: 12, color: FlowColors.medText)),
                  const SizedBox(height: 2),
                  Text(group.narration,
                      style: const TextStyle(
                          fontSize: 14,
                          color: FlowColors.darkText,
                          fontWeight: FontWeight.w500)),
                  Text(
                      '${group.count} '
                      '${group.count == 1 ? 'entry' : 'entries'}'
                      '  —  tap to expand',
                      style: const TextStyle(
                          fontSize: 12, color: FlowColors.medText)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isCredit
                      ? 'Cr ${LedgerAmountFormatter.format(group.totalCredit)}'
                      : 'Dr ${LedgerAmountFormatter.format(group.totalDebit)}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isCredit ? FlowColors.red : FlowColors.green),
                ),
                Text('Bal ${drCr(group.runningBalance)}',
                    style: const TextStyle(
                        fontSize: 12, color: FlowColors.medText)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineRow(GeneralLedgerLine line, double runningBalance) {
    final isDebit = line.debit > 0;
    // Tap-through to the full entry (all accounts it touched) — also where
    // an entry can be reversed, so reload on return.
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JournalEntryDetailScreen(entryId: line.entryId),
        ),
      ).then((_) => _loadReport()),
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
                Row(
                  children: [
                    Text(isoToDisplay(line.entryDate),
                        style: const TextStyle(
                            fontSize: 12, color: FlowColors.medText)),
                    if (line.isReversed) ...[
                      const SizedBox(width: 6),
                      _tag('REVERSED', FlowColors.red),
                    ],
                    if (line.isVirtual) ...[
                      const SizedBox(width: 6),
                      _tag('VIRTUAL', FlowColors.medText),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(line.narration,
                    style: TextStyle(
                        fontSize: 14,
                        color: line.isReversed
                            ? Colors.black38
                            : FlowColors.darkText,
                        decoration: line.isReversed
                            ? TextDecoration.lineThrough
                            : null)),
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
