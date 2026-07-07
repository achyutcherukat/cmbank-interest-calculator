import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/shared_split_payment_widget.dart';
import '../../admin/data/audit_log_repository.dart';
import '../../ledger/data/chart_of_accounts_repository.dart';
import '../../ledger/data/ledger_account_model.dart';
import '../../pledges/data/payment_model.dart';
import '../../pledges/data/payments_repository.dart';
import '../data/bank_account_model.dart';
import '../data/bank_account_repository.dart';

/// Cash Book entry point for partner money movement: Drawings and TDS
/// Payment (partner money going out) and Capital Contribution (coming in).
///
/// All three save as one `payments` row with `payment_type = 'CAPITAL'` and
/// the movement kind in `sub_category`. Partners are the system capital
/// accounts in `chart_of_accounts`, selected live and referenced solely by id
/// (`payments.ledger_account_id`). No ledger posting happens here; the rows
/// post at Day End & Close like everything else.
class PartnerTransactionScreen extends StatefulWidget {
  const PartnerTransactionScreen({super.key, required this.date});
  final DateTime date;

  @override
  State<PartnerTransactionScreen> createState() =>
      _PartnerTransactionScreenState();
}

class _PartnerTransactionScreenState extends State<PartnerTransactionScreen> {
  static const _modeDrawings = 'drawings';
  static const _modeContribution = 'contribution';
  static const _modeTds = 'tds';

  String _mode = _modeDrawings;
  List<LedgerAccount> _partners = [];
  int? _selectedPartnerId;
  List<BankAccount> _bankAccounts = [];

  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  // Recreated when the mode flips so the split widget resets for the new
  // money direction.
  GlobalKey<SharedSplitPaymentWidgetState> _payKey = GlobalKey();
  double _total = 0;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isMoneyIn => _mode == _modeContribution;

  String get _subCategory => switch (_mode) {
        _modeDrawings => PaymentSubCategory.drawings,
        _modeTds => PaymentSubCategory.tdsPayment,
        _ => PaymentSubCategory.capitalContribution,
      };

  String get _dateStr {
    final d = widget.date;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _fmtDate(DateTime d) =>
      '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final accounts = await ChartOfAccountsRepository.instance.getAll();
    final partners = accounts
        .where((a) =>
            a.accountType == LedgerAccountType.capital && a.isSystem)
        .toList();
    final banks = await BankAccountRepository.instance.getActive();
    if (!mounted) return;
    setState(() {
      _partners = partners;
      _selectedPartnerId = partners.isNotEmpty ? partners.first.id : null;
      _bankAccounts = banks;
      _loading = false;
    });
  }

  void _setMode(String mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _payKey = GlobalKey();
      if (_error != null) _error = null;
    });
  }

  // ─── Save ───────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final amt =
        double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    final partner = _partners
        .where((p) => p.id == _selectedPartnerId)
        .toList();
    if (partner.isEmpty) {
      setState(() => _error = 'Select a partner.');
      return;
    }
    final payState = _payKey.currentState;
    final payErr = payState?.validate();
    if (payErr != null) {
      setState(() => _error = payErr);
      return;
    }
    final cashAmt = payState?.cashAmount ?? amt;
    final bankAmt = payState?.bankAmount ?? 0;
    final bankAccId = payState?.bankAccountId;
    final note = _noteCtrl.text.trim();

    setState(() => _saving = true);
    try {
      await PaymentsRepository.instance.createCapital(
        amt,
        cashAmt,
        bankAmt,
        _subCategory,
        _dateStr,
        ledgerAccountId: partner.first.id!,
        bankAccountId: bankAccId,
        notes: note.isEmpty ? null : note,
      );
      await AuditLogRepository.instance.log(
        actionCategory: AuditCategory.dayManagement,
        action: switch (_mode) {
          _modeDrawings => 'DRAWINGS_ADDED',
          _modeTds => 'TDS_PAYMENT_ADDED',
          _ => 'CAPITAL_CONTRIBUTION_ADDED',
        },
        entityType: 'payments',
        entityId: _dateStr,
        reason: partner.first.name,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to save. Please try again.';
        _saving = false;
      });
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CMBColors.pageBackground,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Partner Transaction',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: CMBColors.textOnNavyLarge)),
            Text(
              _fmtDate(widget.date),
              style: const TextStyle(
                  fontSize: 13,
                  color: CMBColors.textOnNavyMuted,
                  fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _partners.isEmpty
              ? const Center(
                  child: Text('No partner capital accounts found.',
                      style: TextStyle(fontSize: 16, color: Colors.black45)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _modeTile(
                          _modeDrawings,
                          'Drawings — partner takes money out',
                          Icons.north_east),
                      const SizedBox(height: 10),
                      _modeTile(
                          _modeContribution,
                          'Capital Contribution — partner puts money in',
                          Icons.south_west),
                      const SizedBox(height: 10),
                      _modeTile(
                          _modeTds,
                          'TDS Payment — paid on partner\'s behalf',
                          Icons.receipt_long),
                      const SizedBox(height: 24),
                      FlowCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _partnerDropdown(),
                            const SizedBox(height: 16),
                            _amountField(),
                            const SizedBox(height: 16),
                            SharedSplitPaymentWidget(
                              key: _payKey,
                              total: _total,
                              totalLabel: switch (_mode) {
                                _modeDrawings => 'Drawings Amount',
                                _modeTds => 'TDS Amount',
                                _ => 'Contribution Amount',
                              },
                              bankAccounts: _bankAccounts,
                              isMoneyIn: _isMoneyIn,
                              showTotalBanner: false,
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _noteCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Note (optional)',
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        Text(_error!,
                            style: const TextStyle(
                                color: CMBColors.warningRed, fontSize: 14)),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: CMBColors.goldRich))
                              : Text(switch (_mode) {
                                  _modeDrawings => 'SAVE DRAWINGS',
                                  _modeTds => 'SAVE TDS PAYMENT',
                                  _ => 'SAVE CONTRIBUTION',
                                }),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _modeTile(String value, String label, IconData icon) {
    final selected = _mode == value;
    return GestureDetector(
      onTap: () => _setMode(value),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? CMBColors.navy : Colors.white,
          border: Border.all(
            color: selected ? CMBColors.borderOnNavy : CMBColors.borderOnLight,
            width: selected ? 2.0 : 1.5,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20,
                color: selected ? CMBColors.goldRich : CMBColors.navy),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? CMBColors.goldRich : CMBColors.navy,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  color: CMBColors.goldRich, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _partnerDropdown() {
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Partner'),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedPartnerId,
          isDense: true,
          isExpanded: true,
          items: _partners
              .map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Row(children: [
                      const Icon(Icons.person,
                          size: 18, color: CMBColors.navy),
                      const SizedBox(width: 8),
                      Expanded(
                          child:
                              Text(p.name, overflow: TextOverflow.ellipsis)),
                    ]),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedPartnerId = v),
        ),
      ),
    );
  }

  Widget _amountField() => TextField(
        controller: _amountCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [IndianNumberFormatter()],
        decoration: const InputDecoration(
            labelText: 'Amount (₹) *', prefixText: '₹ '),
        onChanged: (v) {
          final parsed = double.tryParse(v.replaceAll(',', '')) ?? 0;
          setState(() {
            _total = parsed;
            if (_error != null) _error = null;
          });
        },
      );
}
