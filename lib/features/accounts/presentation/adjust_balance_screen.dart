import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../accounts/data/bank_account_model.dart';
import '../../accounts/data/bank_account_repository.dart';
import '../../accounts/data/daily_balance_repository.dart';
import '../../admin/data/audit_log_repository.dart';
import '../../pledges/data/payment_model.dart';
import '../../pledges/data/payments_repository.dart';

class AdjustBalanceScreen extends StatefulWidget {
  final DateTime date;

  /// When non-null, the screen operates in edit mode: form is pre-populated
  /// from [editPayment] and Save updates the existing row(s) rather than
  /// inserting new ones.
  ///
  /// For two-row transfer adjustments (CASH_TO_BANK, BANK_TO_CASH,
  /// BANK_TO_BANK), also pass [editPartnerPayment] — the IN-direction row that
  /// forms the pair with [editPayment] (the OUT-direction row).
  final PaymentModel? editPayment;
  final PaymentModel? editPartnerPayment;

  const AdjustBalanceScreen({
    super.key,
    required this.date,
    this.editPayment,
    this.editPartnerPayment,
  });

  @override
  State<AdjustBalanceScreen> createState() => _AdjustBalanceScreenState();
}

class _AdjustBalanceScreenState extends State<AdjustBalanceScreen> {
  List<BankAccount> _bankAccounts = [];
  bool _loading = true;

  // ADD_CASH / ADD_UPI-style "add money in" adjustments are retired — new
  // adjustments are transfers only. 'add_cash' / 'add_bank' remain reachable
  // in edit mode for historical rows.
  String _mode = 'transfer';
  int? _selectedBankAccountId;
  String _fromId = 'cash';
  String? _toId;

  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  String? _error;
  bool _saving = false;

  bool get _isEditMode => widget.editPayment != null;

  String get _dateStr {
    final d = widget.date;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

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

    String initialMode = 'transfer';
    int? initialBankAccountId;
    String initialFromId = _cashId;
    String? initialToId;

    if (_isEditMode) {
      final sub = widget.editPayment!.subCategory ?? '';
      final amt = widget.editPayment!.amount;
      final amtPaise = (amt.abs() * 100).round() % 100;
      _amountCtrl.text = amtPaise == 0
          ? formatIndian(amt.round().toString())
          : '${formatIndian(amt.floor().toString())}.${amtPaise.toString().padLeft(2, '0')}';
      _reasonCtrl.text = widget.editPayment!.notes ?? '';

      if (sub == PaymentSubCategory.addCash) {
        initialMode = 'add_cash';
      } else if (sub == PaymentSubCategory.addBank ||
          sub == PaymentSubCategory.addUpi) {
        initialMode = 'add_bank';
        initialBankAccountId = widget.editPayment!.bankAccountId;
        if (initialBankAccountId == null && accounts.isNotEmpty) {
          final def = accounts.cast<BankAccount?>().firstWhere(
              (a) => a?.isDefault == true,
              orElse: () => null);
          initialBankAccountId = (def ?? accounts.first).id;
        }
      } else {
        // Transfer types
        initialMode = 'transfer';
        final isCashToBank = sub == PaymentSubCategory.cashToBank ||
            sub == PaymentSubCategory.cashToUpi;
        final isBankToCash = sub == PaymentSubCategory.bankToCash ||
            sub == PaymentSubCategory.upiToCash;

        if (isCashToBank) {
          initialFromId = _cashId;
          final toAcctId = widget.editPartnerPayment?.bankAccountId;
          initialToId = toAcctId?.toString() ??
              (accounts.isNotEmpty ? accounts.first.id.toString() : null);
        } else if (isBankToCash) {
          initialFromId =
              widget.editPayment!.bankAccountId?.toString() ?? _cashId;
          initialToId = _cashId;
        } else {
          // BANK_TO_BANK
          initialFromId =
              widget.editPayment!.bankAccountId?.toString() ?? _cashId;
          final toAcctId = widget.editPartnerPayment?.bankAccountId;
          initialToId = toAcctId?.toString() ??
              (accounts.length > 1 ? accounts[1].id.toString() : null);
        }
      }
    } else {
      // Create mode: pick default bank account
      if (accounts.isNotEmpty) {
        final def = accounts.cast<BankAccount?>().firstWhere(
            (a) => a?.isDefault == true,
            orElse: () => null);
        initialBankAccountId = (def ?? accounts.first).id;
      }
    }

    setState(() {
      _bankAccounts = accounts;
      _loading = false;
      _mode = initialMode;
      _selectedBankAccountId = initialBankAccountId ?? _selectedBankAccountId;
      _fromId = initialFromId;
      _toId = initialToId;
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

  Widget _editModeChip() {
    final modeLabel = switch (_mode) {
      'add_cash' => 'Add Cash',
      'add_bank' => 'Add Bank Amount',
      _ => 'Transfer Money',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: CMBColors.warmWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CMBColors.borderOnLight, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit, size: 18, color: CMBColors.navy),
          const SizedBox(width: 10),
          Text(
            'Editing: $modeLabel',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: CMBColors.navy),
          ),
        ],
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
              Text(a.name + (a.isDefault ? '  ★' : '')),
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
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [IndianDecimalFormatter()],
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

    try {
      if (_isEditMode) {
        await _applyEdit(amt, reason);
      } else {
        await _applyCreate(amt, reason);
      }
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

  /// Create mode records transfers only — the retired ADD_CASH / ADD_UPI /
  /// ADD_BANK "add money in" adjustments can no longer be created here.
  Future<void> _applyCreate(double amt, String reason) async {
    final repo = PaymentsRepository.instance;

    final fromIsCash = _fromId == _cashId;
    final toIsCash = _toId == _cashId;
    final fromAcctId = fromIsCash ? null : int.tryParse(_fromId);
    final toAcctId = toIsCash ? null : int.tryParse(_toId!);

    if (fromIsCash && !toIsCash) {
      await repo.createAdjustment(amt, amt, 0,
          PaymentSubCategory.cashToBank, PaymentDirection.outward,
          _dateStr, notes: reason);
      await repo.createAdjustment(amt, 0, amt,
          PaymentSubCategory.cashToBank, PaymentDirection.inward,
          _dateStr, bankAccountId: toAcctId, notes: reason);
    } else if (!fromIsCash && toIsCash) {
      await repo.createAdjustment(amt, 0, amt,
          PaymentSubCategory.bankToCash, PaymentDirection.outward,
          _dateStr, bankAccountId: fromAcctId, notes: reason);
      await repo.createAdjustment(amt, amt, 0,
          PaymentSubCategory.bankToCash, PaymentDirection.inward,
          _dateStr, notes: reason);
    } else {
      await repo.createAdjustment(amt, 0, amt,
          PaymentSubCategory.bankToBank, PaymentDirection.outward,
          _dateStr, bankAccountId: fromAcctId, notes: reason);
      await repo.createAdjustment(amt, 0, amt,
          PaymentSubCategory.bankToBank, PaymentDirection.inward,
          _dateStr, bankAccountId: toAcctId, notes: reason);
    }

    await AuditLogRepository.instance.log(
      actionCategory: AuditCategory.dayManagement,
      action: 'BALANCE_ADJUSTED',
      entityType: 'payments',
      entityId: _dateStr,
      newValueJson: '{"type":"$_mode","amount":$amt}',
      reason: reason,
    );
  }

  Future<void> _applyEdit(double amt, String reason) async {
    final isLocked =
        await DailyBalanceRepository.instance.isDateLocked(_dateStr);
    if (isLocked) throw Exception('Day is locked');

    final payId = widget.editPayment!.id!;
    final oldAmt = widget.editPayment!.amount;
    final repo = PaymentsRepository.instance;

    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      if (_mode == 'add_cash') {
        await repo.updatePaymentFields(txn, payId,
            amount: amt,
            cashAmount: amt,
            bankAmount: 0,
            clearBankAccountId: true,
            notes: reason);
      } else if (_mode == 'add_bank') {
        await repo.updatePaymentFields(txn, payId,
            amount: amt,
            cashAmount: 0,
            bankAmount: amt,
            bankAccountId: _selectedBankAccountId,
            notes: reason);
      } else {
        // Transfer: update both rows and keep sub_category in sync with
        // the current from/to selection.
        final partnerId = widget.editPartnerPayment!.id!;
        final fromIsCash = _fromId == _cashId;
        final toIsCash = _toId == _cashId;
        final fromAcctId = fromIsCash ? null : int.tryParse(_fromId);
        final toAcctId = toIsCash ? null : int.tryParse(_toId ?? '');

        final String newSub;
        if (fromIsCash && !toIsCash) {
          newSub = PaymentSubCategory.cashToBank;
          // OUT row: cash out
          await repo.updatePaymentFields(txn, payId,
              amount: amt,
              cashAmount: amt,
              bankAmount: 0,
              clearBankAccountId: true,
              notes: reason,
              subCategory: newSub);
          // IN row: bank in
          await repo.updatePaymentFields(txn, partnerId,
              amount: amt,
              cashAmount: 0,
              bankAmount: amt,
              bankAccountId: toAcctId,
              notes: reason,
              subCategory: newSub);
        } else if (!fromIsCash && toIsCash) {
          newSub = PaymentSubCategory.bankToCash;
          // OUT row: bank out
          await repo.updatePaymentFields(txn, payId,
              amount: amt,
              cashAmount: 0,
              bankAmount: amt,
              bankAccountId: fromAcctId,
              notes: reason,
              subCategory: newSub);
          // IN row: cash in
          await repo.updatePaymentFields(txn, partnerId,
              amount: amt,
              cashAmount: amt,
              bankAmount: 0,
              clearBankAccountId: true,
              notes: reason,
              subCategory: newSub);
        } else {
          newSub = PaymentSubCategory.bankToBank;
          // OUT row
          await repo.updatePaymentFields(txn, payId,
              amount: amt,
              cashAmount: 0,
              bankAmount: amt,
              bankAccountId: fromAcctId,
              notes: reason,
              subCategory: newSub);
          // IN row
          await repo.updatePaymentFields(txn, partnerId,
              amount: amt,
              cashAmount: 0,
              bankAmount: amt,
              bankAccountId: toAcctId,
              notes: reason,
              subCategory: newSub);
        }
      }

      await AuditLogRepository.instance.log(
        actionCategory: AuditCategory.dayManagement,
        action: 'TRANSACTION_EDITED',
        entityType: 'payments',
        entityId: payId.toString(),
        oldValueJson: jsonEncode({'amount': oldAmt, 'type': _mode}),
        newValueJson:
            jsonEncode({'amount': amt, 'type': _mode, 'reason': reason}),
        reason: reason,
        txn: txn,
      );
    });

    await DailyBalanceRepository.instance.cascadeFrom(_dateStr);
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
            Text(_isEditMode ? 'Edit Adjustment' : 'Adjust Balance',
                style: const TextStyle(
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
                  // ── Mode selector (create) or read-only chip (edit) ────────
                  // Only transfers can be created; "add money in" is handled
                  // via Capital Contribution (separate feature), not here.
                  if (!_isEditMode)
                    _modeTile('transfer', 'Transfer Money', Icons.swap_horiz)
                  else
                    _editModeChip(),
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
                          : Text(_isEditMode
                              ? 'SAVE CHANGES'
                              : 'APPLY ADJUSTMENT'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
