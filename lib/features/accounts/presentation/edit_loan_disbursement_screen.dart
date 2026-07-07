import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/shared_split_payment_widget.dart';
import '../../admin/data/audit_log_repository.dart';
import '../../pledges/data/payment_model.dart';
import '../../pledges/data/payments_repository.dart';
import '../../pledges/data/pledge_model.dart';
import '../data/bank_account_model.dart';
import '../data/bank_account_repository.dart';
import '../data/daily_balance_repository.dart';

/// Branch B of Edit Transaction: edits a LOAN_DISBURSED or
/// LOAN_INCREASE_DISBURSED payment. Allows correcting the principal amount
/// (only when the pledge has no renewal chain activity) and the cash/bank
/// split. Updates both the payments row and the pledge principal atomically.
class EditLoanDisbursementScreen extends StatefulWidget {
  const EditLoanDisbursementScreen({
    super.key,
    required this.payment,
    required this.pledge,
    required this.dateStr,
  });

  final PaymentModel payment;
  final PledgeModel pledge;
  final String dateStr;

  @override
  State<EditLoanDisbursementScreen> createState() =>
      _EditLoanDisbursementScreenState();
}

class _EditLoanDisbursementScreenState
    extends State<EditLoanDisbursementScreen> {
  List<BankAccount> _accounts = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// True when the pledge has renewal chain activity — principal becomes
  /// read-only in this case.
  bool _hasRenewalChain = false;

  final _principalCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _payKey = GlobalKey<SharedSplitPaymentWidgetState>();

  double _enteredPrincipal = 0;

  String _initialSplitMode() {
    final c = widget.payment.cashAmount;
    final b = widget.payment.bankAmount;
    if (c > 0 && b > 0) return 'split';
    if (b > 0) return 'bank';
    return 'cash';
  }

  @override
  void initState() {
    super.initState();
    _enteredPrincipal = widget.pledge.loanAmount;
    _principalCtrl.text =
        formatIndian(widget.pledge.loanAmount.round().toString());
    _loadData();
  }

  Future<void> _loadData() async {
    final results = await Future.wait([
      BankAccountRepository.instance.getActive(),
      _checkRenewalChain(),
    ]);
    if (!mounted) return;
    setState(() {
      _accounts = results[0] as List<BankAccount>;
      _hasRenewalChain = results[1] as bool;
      _loading = false;
    });
  }

  Future<bool> _checkRenewalChain() async {
    // Pledge was created by a renewal or loan increase — principal read-only
    if (widget.pledge.renewalParentId != null) return true;
    // If pledge itself was subsequently renewed/part-paid/topped-up
    if (widget.pledge.renewType != null) return true;
    // If any other pledge references this one as its renewal parent
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) as c FROM pledges WHERE renewal_parent_id = ?',
      [widget.pledge.id],
    );
    return ((rows.first['c'] as int?) ?? 0) > 0;
  }

  @override
  void dispose() {
    _principalCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  // ─── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Reason is required.');
      return;
    }

    if (_enteredPrincipal <= 0) {
      setState(() => _error = 'Principal must be greater than zero.');
      return;
    }

    final payErr = _payKey.currentState?.validate();
    if (payErr != null) {
      setState(() => _error = payErr);
      return;
    }

    setState(() => _saving = true);

    try {
      final isLocked =
          await DailyBalanceRepository.instance.isDateLocked(widget.dateStr);
      if (isLocked) throw Exception('Day is locked');

      final payState = _payKey.currentState!;
      final cashAmt = payState.cashAmount;
      final bankAmt = payState.bankAmount;
      final bankAccId = payState.bankAccountId;

      final payId = widget.payment.id!;
      final pledgeId = widget.pledge.id!;

      final oldPrincipal = widget.pledge.loanAmount;
      final newPrincipal =
          _hasRenewalChain ? oldPrincipal : _enteredPrincipal;
      final principalChanged =
          !_hasRenewalChain && (newPrincipal - oldPrincipal).abs() > 0.01;

      final db = await AppDatabase.instance.database;
      await db.transaction((txn) async {
        await PaymentsRepository.instance.updatePaymentFields(
          txn,
          payId,
          amount: newPrincipal,
          cashAmount: cashAmt,
          bankAmount: bankAmt,
          bankAccountId: bankAmt > 0 ? bankAccId : null,
          clearBankAccountId: bankAmt == 0,
        );

        if (principalChanged) {
          await txn.update(
            'pledges',
            {
              'principal_amount': newPrincipal,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [pledgeId],
          );
        }

        await AuditLogRepository.instance.log(
          actionCategory: AuditCategory.dayManagement,
          action: 'TRANSACTION_EDITED',
          entityType: 'payments',
          entityId: payId.toString(),
          oldValueJson: jsonEncode({
            'principal': oldPrincipal,
            'cash': widget.payment.cashAmount,
            'bank': widget.payment.bankAmount,
          }),
          newValueJson: jsonEncode({
            'principal': newPrincipal,
            'cash': cashAmt,
            'bank': bankAmt,
          }),
          reason: reason,
          txn: txn,
        );

        if (principalChanged) {
          await AuditLogRepository.instance.log(
            actionCategory: AuditCategory.dayManagement,
            action: 'TRANSACTION_EDITED',
            entityType: 'pledges',
            entityId: pledgeId.toString(),
            oldValueJson: jsonEncode({'principal_amount': oldPrincipal}),
            newValueJson: jsonEncode({'principal_amount': newPrincipal}),
            reason: reason,
            txn: txn,
          );
        }
      });

      await DailyBalanceRepository.instance.cascadeFrom(widget.dateStr);

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

  // ─── Build ─────────────────────────────────────────────────────────────────

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
            const Text('Edit Loan Disbursement',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.dateStr,
                style: const TextStyle(
                    fontSize: 13, color: FlowColors.textOnNavyMuted)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Context (read-only) ────────────────────────────────────
                FlowCard(
                  backgroundColor: FlowColors.accent,
                  header: 'Pledge Context',
                  child: Column(
                    children: [
                      DetailRow(
                          label: 'Pledge #',
                          value: widget.pledge.pledgeNumber),
                      DetailRow(
                          label: 'Customer',
                          value: widget.pledge.customerName,
                          isLast: true),
                    ],
                  ),
                ),

                // ── Renewal chain warning (if applicable) ─────────────────
                if (_hasRenewalChain) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: FlowColors.orangeLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: FlowColors.orange),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: FlowColors.orange, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This pledge is part of a renewal or loan increase '
                            'chain — principal cannot be edited. You can still '
                            'correct the payment method split below.',
                            style: TextStyle(
                                fontSize: 13, color: FlowColors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Principal field ────────────────────────────────────────
                FlowCard(
                  header: 'Principal Amount',
                  child: _hasRenewalChain
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: FlowColors.accent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: FlowColors.primaryLight),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Principal (read-only)',
                                  style: TextStyle(
                                      fontSize: 14, color: Colors.black54)),
                              Text(
                                money(widget.pledge.loanAmount),
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: FlowColors.primary),
                              ),
                            ],
                          ),
                        )
                      : TextField(
                          controller: _principalCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            IndianNumberFormatter(),
                          ],
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            labelText: 'Principal Amount (₹) *',
                            prefixText: '₹ ',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            final parsed =
                                double.tryParse(v.replaceAll(',', '')) ?? 0;
                            setState(() {
                              _enteredPrincipal = parsed;
                              if (_error != null) _error = null;
                            });
                          },
                        ),
                ),

                // ── Payment split ──────────────────────────────────────────
                FlowCard(
                  header: 'Payment Method',
                  child: SharedSplitPaymentWidget(
                    key: _payKey,
                    total: _hasRenewalChain
                        ? widget.pledge.loanAmount
                        : _enteredPrincipal,
                    totalLabel: 'Principal Amount',
                    bankAccounts: _accounts,
                    isMoneyIn: false,
                    showTotalBanner: true,
                    initialMode: _initialSplitMode(),
                    initialCashAmount: widget.payment.cashAmount > 0
                        ? widget.payment.cashAmount
                        : null,
                    initialBankAmount: widget.payment.bankAmount > 0
                        ? widget.payment.bankAmount
                        : null,
                    initialBankAccountId: widget.payment.bankAccountId,
                  ),
                ),

                // ── Reason (mandatory) ────────────────────────────────────
                FlowCard(
                  header: 'Edit Reason',
                  child: TextField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reason for edit *',
                      hintText:
                          'e.g. "Forgot to switch from cash to bank"',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                ),

                if (_error != null) ...[
                  Text(_error!,
                      style: const TextStyle(
                          color: FlowColors.red, fontSize: 14)),
                  const SizedBox(height: 10),
                ],

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(
                      _saving ? 'Saving…' : 'SAVE CHANGES',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlowColors.primary,
                      foregroundColor: FlowColors.goldRich,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
