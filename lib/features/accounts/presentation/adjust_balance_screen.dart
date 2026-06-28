import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../accounts/data/bank_account_model.dart';
import '../../accounts/data/bank_account_repository.dart';
import '../../admin/data/audit_log_repository.dart';
import '../../pledges/data/payment_model.dart';
import '../../pledges/data/payments_repository.dart';

class AdjustBalanceScreen extends StatefulWidget {
  final DateTime date;
  const AdjustBalanceScreen({super.key, required this.date});

  @override
  State<AdjustBalanceScreen> createState() => _AdjustBalanceScreenState();
}

class _AdjustBalanceScreenState extends State<AdjustBalanceScreen> {
  List<BankAccount> _bankAccounts = [];
  bool _loading = true;

  String _mode = 'add_cash';
  int? _selectedBankAccountId;
  String _fromId = 'cash';
  String? _toId;

  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    final accounts = await BankAccountRepository.instance.getActive();
    if (!mounted) return;
    setState(() {
      _bankAccounts = accounts;
      _loading = false;
      if (accounts.isNotEmpty) {
        final def = accounts.cast<BankAccount?>()
            .firstWhere((a) => a?.isDefault == true, orElse: () => null);
        _selectedBankAccountId = (def ?? accounts.first).id;
      }
    });
  }

  // ─── Mode tile ─────────────────────────────────────────────────────────────

  Widget _modeTile(String value, String label, IconData icon) {
    final selected = _mode == value;
    return GestureDetector(
      onTap: () => setState(() => _mode = value),
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
                  fontSize: 16,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
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

  // ─── Transfer item type ─────────────────────────────────────────────────────

  static const String _cashId = 'cash';

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _fmtDate(DateTime d) =>
      '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

  List<DropdownMenuItem<String>> _transferItems({String? exclude}) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: _cashId,
        child: Row(children: [
          Icon(Icons.payments, size: 18, color: CMBColors.navy),
          SizedBox(width: 8),
          Text('Cash'),
        ]),
      ),
      ..._bankAccounts.map((a) => DropdownMenuItem(
            value: a.id.toString(),
            child: Row(children: [
              const Icon(Icons.account_balance, size: 18, color: CMBColors.navy),
              const SizedBox(width: 8),
              Text(a.name +
                  (a.isDefault ? '  ★' : '')),
            ]),
          )),
    ];
    if (exclude == null) return items;
    return items.where((i) => i.value != exclude).toList();
  }

  // ─── Form sections ──────────────────────────────────────────────────────────

  Widget _addCashForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _amountField(),
          const SizedBox(height: 16),
          _reasonField(),
        ],
      );

  Widget _addBankForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _amountField(),
          const SizedBox(height: 16),
          _dropdown<int?>(
            label: 'Bank Account',
            value: _selectedBankAccountId,
            items: _bankAccounts
                .map((a) => DropdownMenuItem<int?>(
                      value: a.id,
                      child: Text(a.name + (a.isDefault ? '  ★' : '')),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _selectedBankAccountId = v),
          ),
          const SizedBox(height: 16),
          _reasonField(),
        ],
      );

  Widget _transferForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dropdown<String>(
            label: 'From',
            value: _fromId,
            items: _transferItems(exclude: _toId),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _fromId = v;
                if (_fromId == _toId) _toId = null;
              });
            },
          ),
          const SizedBox(height: 16),
          _dropdown<String?>(
            label: 'To',
            value: _toId,
            items: _transferItems(exclude: _fromId),
            onChanged: (v) => setState(() => _toId = v),
          ),
          const SizedBox(height: 16),
          _amountField(),
          const SizedBox(height: 16),
          _reasonField(),
        ],
      );

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            isExpanded: true,
            items: items,
            onChanged: onChanged,
          ),
        ),
      );

  Widget _amountField() => TextField(
        controller: _amountCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [IndianNumberFormatter()],
        decoration: const InputDecoration(
            labelText: 'Amount (₹) *', prefixText: '₹ '),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      );

  Widget _reasonField() => TextField(
        controller: _reasonCtrl,
        decoration: const InputDecoration(
          labelText: 'Reason *',
          hintText: 'Why is this adjustment needed?',
        ),
        maxLines: 2,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      );

  // ─── Save ───────────────────────────────────────────────────────────────────

  Future<void> _apply() async {
    final amt =
        double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Reason is required.');
      return;
    }
    if (_mode == 'add_bank' && _selectedBankAccountId == null) {
      setState(() => _error = 'Select a bank account.');
      return;
    }
    if (_mode == 'transfer') {
      if (_toId == null) {
        setState(() => _error = 'Select a destination account.');
        return;
      }
      if (_fromId == _toId) {
        setState(() => _error = 'From and To must be different.');
        return;
      }
    }

    setState(() => _saving = true);

    final d = widget.date;
    final dateStr =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final repo = PaymentsRepository.instance;

    try {
      if (_mode == 'add_cash') {
        await repo.createAdjustment(amt, amt, 0,
            PaymentSubCategory.addCash, PaymentDirection.inward, dateStr,
            notes: reason);
      } else if (_mode == 'add_bank') {
        await repo.createAdjustment(amt, 0, amt,
            PaymentSubCategory.addBank, PaymentDirection.inward, dateStr,
            bankAccountId: _selectedBankAccountId, notes: reason);
      } else {
        final fromIsCash = _fromId == _cashId;
        final toIsCash = _toId == _cashId;
        final fromAcctId = fromIsCash ? null : int.tryParse(_fromId);
        final toAcctId = toIsCash ? null : int.tryParse(_toId!);

        if (fromIsCash && !toIsCash) {
          // Cash → Bank
          await repo.createAdjustment(amt, amt, 0,
              PaymentSubCategory.cashToBank, PaymentDirection.outward,
              dateStr, notes: reason);
          await repo.createAdjustment(amt, 0, amt,
              PaymentSubCategory.cashToBank, PaymentDirection.inward,
              dateStr, bankAccountId: toAcctId, notes: reason);
        } else if (!fromIsCash && toIsCash) {
          // Bank → Cash
          await repo.createAdjustment(amt, 0, amt,
              PaymentSubCategory.bankToCash, PaymentDirection.outward,
              dateStr, bankAccountId: fromAcctId, notes: reason);
          await repo.createAdjustment(amt, amt, 0,
              PaymentSubCategory.bankToCash, PaymentDirection.inward,
              dateStr, notes: reason);
        } else {
          // Bank → Bank
          await repo.createAdjustment(amt, 0, amt,
              PaymentSubCategory.bankToBank, PaymentDirection.outward,
              dateStr, bankAccountId: fromAcctId, notes: reason);
          await repo.createAdjustment(amt, 0, amt,
              PaymentSubCategory.bankToBank, PaymentDirection.inward,
              dateStr, bankAccountId: toAcctId, notes: reason);
        }
      }

      await AuditLogRepository.instance.log(
        actionCategory: AuditCategory.dayManagement,
        action: 'BALANCE_ADJUSTED',
        entityType: 'payments',
        entityId: dateStr,
        newValueJson: '{"type":"$_mode","amount":$amt}',
        reason: reason,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to save. Please try again.';
        _saving = false;
      });
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CMBColors.pageBackground,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Adjust Balance',
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Mode selector ──────────────────────────────────────────
                  _modeTile('add_cash', 'Add Cash Amount', Icons.payments),
                  const SizedBox(height: 10),
                  _modeTile('add_bank', 'Add Money to Bank Account',
                      Icons.account_balance),
                  const SizedBox(height: 10),
                  _modeTile('transfer', 'Transfer Money', Icons.swap_horiz),
                  const SizedBox(height: 24),

                  // ── Form ──────────────────────────────────────────────────
                  FlowCard(
                    padding: const EdgeInsets.all(16),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: KeyedSubtree(
                        key: ValueKey(_mode),
                        child: _mode == 'add_cash'
                            ? _addCashForm()
                            : _mode == 'add_bank'
                                ? _addBankForm()
                                : _transferForm(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Error ─────────────────────────────────────────────────
                  if (_error != null) ...[
                    Text(_error!,
                        style: const TextStyle(
                            color: CMBColors.warningRed, fontSize: 14)),
                    const SizedBox(height: 12),
                  ],

                  // ── Apply button ──────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _apply,
                      child: _saving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: CMBColors.goldRich))
                          : const Text('APPLY ADJUSTMENT'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
