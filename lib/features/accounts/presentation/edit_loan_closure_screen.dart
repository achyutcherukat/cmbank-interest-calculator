import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/shared_split_payment_widget.dart';
import '../../admin/data/audit_log_repository.dart';
import '../../calculator/data/interest_calculator.dart';
import '../../pledges/data/payment_model.dart';
import '../../pledges/data/payments_repository.dart';
import '../../pledges/data/pledge_model.dart';
import '../data/bank_account_model.dart';
import '../data/bank_account_repository.dart';
import '../data/daily_balance_repository.dart';

/// Branch A of Edit Transaction: edits a LOAN_FULL_CLOSURE or
/// RENEWAL_INTEREST_PAID payment. Allows correcting the interest amount and
/// the cash/bank split. Updates both the payments row and the pledge totals
/// atomically.
class EditLoanClosureScreen extends StatefulWidget {
  const EditLoanClosureScreen({
    super.key,
    required this.payment,
    required this.pledge,
    required this.dateStr,
  });

  final PaymentModel payment;
  final PledgeModel pledge;
  final String dateStr;

  @override
  State<EditLoanClosureScreen> createState() => _EditLoanClosureScreenState();
}

class _EditLoanClosureScreenState extends State<EditLoanClosureScreen> {
  List<BankAccount> _accounts = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  late final bool _isRenewalPayment;
  late final bool _isRenewalPledge;
  late final bool _amountEditable;
  late double _minInterest;

  final _interestCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _payKey = GlobalKey<SharedSplitPaymentWidgetState>();

  double _enteredInterest = 0;

  double get _principal =>
      _isRenewalPayment ? 0 : widget.pledge.loanAmount;

  double get _newTotal => _principal + _enteredInterest;

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
    _isRenewalPayment =
        widget.payment.paymentType == PaymentType.renewalInterestPaid;
    _isRenewalPledge = widget.pledge.renewType != null ||
        widget.pledge.renewalParentId != null;
    _amountEditable = !_isRenewalPayment && widget.pledge.status == 'closed';

    // Existing interest on this payment
    final existingInterest = _isRenewalPayment
        ? widget.payment.amount // renewal: payment.amount IS the interest
        : widget.pledge.totalInterestPaid;

    _enteredInterest = existingInterest;
    _interestCtrl.text = formatIndian(existingInterest.round().toString());

    _computeMinInterest();
    _loadAccounts();
  }

  void _computeMinInterest() {
    try {
      final fromDate = DateTime.parse(widget.pledge.pledgeDate);
      final toDate = widget.pledge.closureDate != null
          ? DateTime.parse(widget.pledge.closureDate!)
          : DateTime.now();
      final calc = InterestCalculator.calculate(
        principal: widget.pledge.loanAmount,
        fromDate: fromDate,
        toDate: toDate,
        ratePercent: widget.pledge.interestRate,
        isRenewalPledge: _isRenewalPledge || _isRenewalPayment,
      );
      _minInterest = calc.interest;
    } catch (_) {
      _minInterest = _isRenewalPayment || _isRenewalPledge ? 20.0 : 50.0;
    }
  }

  Future<void> _loadAccounts() async {
    final accounts = await BankAccountRepository.instance.getActive();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _interestCtrl.dispose();
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

    if (_amountEditable && _enteredInterest <= 0) {
      setState(() => _error = 'Interest must be greater than zero.');
      return;
    }

    final payErr = _payKey.currentState?.validate();
    if (payErr != null) {
      setState(() => _error = payErr);
      return;
    }

    // Below-minimum interest warning (only when amount is editable)
    if (_amountEditable && _enteredInterest < _minInterest) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Interest Below Standard Minimum',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.orange)),
          content: Text(
            'The entered interest (${money(_enteredInterest)}) is below the '
            'standard minimum (${money(_minInterest)}). '
            'Confirm this is a deliberate discount?',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.orange,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, Apply Discount'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
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

      final oldInterest = _isRenewalPayment
          ? widget.payment.amount
          : widget.pledge.totalInterestPaid;
      final oldTotal = _isRenewalPayment
          ? widget.payment.amount
          : widget.pledge.totalAmountCollected;
      final newInterest = _enteredInterest;
      final newTotal = _newTotal;
      final interestChanged = (newInterest - oldInterest).abs() > 0.01;

      final db = await AppDatabase.instance.database;
      await db.transaction((txn) async {
        // Update payment row (amount = total collected for closure, interest for renewal)
        await PaymentsRepository.instance.updatePaymentFields(
          txn,
          payId,
          amount: _isRenewalPayment ? newInterest : newTotal,
          cashAmount: cashAmt,
          bankAmount: bankAmt,
          bankAccountId: bankAmt > 0 ? bankAccId : null,
          clearBankAccountId: bankAmt == 0,
        );

        // Update pledge totals only if interest changed
        if (interestChanged) {
          await txn.update(
            'pledges',
            {
              'total_interest_paid': newInterest,
              'total_amount_collected':
                  _isRenewalPayment ? newInterest : newTotal,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [pledgeId],
          );
        }

        // Audit log — always log payments, also log pledges if interest changed
        await AuditLogRepository.instance.log(
          actionCategory: AuditCategory.dayManagement,
          action: 'TRANSACTION_EDITED',
          entityType: 'payments',
          entityId: payId.toString(),
          oldValueJson: jsonEncode({
            'interest': oldInterest,
            'total': oldTotal,
            'cash': widget.payment.cashAmount,
            'bank': widget.payment.bankAmount,
          }),
          newValueJson: jsonEncode({
            'interest': newInterest,
            'total': _isRenewalPayment ? newInterest : newTotal,
            'cash': cashAmt,
            'bank': bankAmt,
          }),
          reason: reason,
          txn: txn,
        );

        if (interestChanged) {
          await AuditLogRepository.instance.log(
            actionCategory: AuditCategory.dayManagement,
            action: 'TRANSACTION_EDITED',
            entityType: 'pledges',
            entityId: pledgeId.toString(),
            oldValueJson: jsonEncode({
              'total_interest_paid': oldInterest,
              'total_amount_collected': oldTotal,
            }),
            newValueJson: jsonEncode({
              'total_interest_paid': newInterest,
              'total_amount_collected':
                  _isRenewalPayment ? newInterest : newTotal,
            }),
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
            Text(
              _isRenewalPayment ? 'Edit Renewal Interest' : 'Edit Loan Closure',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(widget.dateStr,
                style: const TextStyle(
                    fontSize: 13, color: FlowColors.textOnNavyMuted)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16).withNavBarInset(context),
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
                          value: widget.pledge.customerName),
                      if (!_isRenewalPayment)
                        DetailRow(
                          label: 'Principal',
                          value: money(widget.pledge.loanAmount),
                          isLast: true,
                        )
                      else
                        const DetailRow(
                            label: 'Type',
                            value: 'Renewal Interest',
                            isLast: true),
                    ],
                  ),
                ),

                // ── Interest / amount field ────────────────────────────────
                if (!_amountEditable) ...[
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
                            'Interest amount cannot be changed for renewal '
                            'interest payments. You can still update the '
                            'payment method split below.',
                            style: TextStyle(
                                fontSize: 13, color: FlowColors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                FlowCard(
                  header: _isRenewalPayment ? 'Amount' : 'Interest',
                  child: _amountEditable
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _interestCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                IndianNumberFormatter(),
                              ],
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                labelText: _isRenewalPayment
                                    ? 'Amount (₹) *'
                                    : 'Interest Paid (₹) *',
                                prefixText: '₹ ',
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (v) {
                                final parsed =
                                    double.tryParse(v.replaceAll(',', '')) ?? 0;
                                setState(() {
                                  _enteredInterest = parsed;
                                  if (_error != null) _error = null;
                                });
                              },
                            ),
                            if (!_isRenewalPayment) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: FlowColors.accent,
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: FlowColors.primaryLight),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Total Amount Collected',
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.black54)),
                                    Text(
                                      money(_newTotal),
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: FlowColors.primary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        )
                      : Container(
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
                              Text(
                                _isRenewalPayment
                                    ? 'Amount (read-only)'
                                    : 'Interest (read-only)',
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.black54),
                              ),
                              Text(
                                money(_enteredInterest),
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: FlowColors.primary),
                              ),
                            ],
                          ),
                        ),
                ),

                // ── Payment split ──────────────────────────────────────────
                FlowCard(
                  header: 'Payment Method',
                  child: SharedSplitPaymentWidget(
                    key: _payKey,
                    total: _isRenewalPayment ? _enteredInterest : _newTotal,
                    totalLabel: _isRenewalPayment
                        ? 'Amount'
                        : 'Total Amount Collected',
                    bankAccounts: _accounts,
                    isMoneyIn: true,
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
                      hintText: 'e.g. "Discount given", "Wrong amount entered"',
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
