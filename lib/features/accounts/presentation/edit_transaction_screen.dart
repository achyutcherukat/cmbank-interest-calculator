import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/shared_split_payment_widget.dart';
import '../../admin/data/audit_log_repository.dart';
import '../../pledges/data/payment_model.dart';
import '../../pledges/data/payments_repository.dart';
import '../../pledges/data/pledge_model.dart';
import '../../pledges/data/pledge_repository.dart';
import '../data/bank_account_model.dart';
import '../data/bank_account_repository.dart';
import '../data/daily_balance_repository.dart';
import '../../ledger/data/chart_of_accounts_repository.dart';
import '../../ledger/data/ledger_account_model.dart';
import 'adjust_balance_screen.dart';
import 'edit_loan_closure_screen.dart';
import 'edit_loan_disbursement_screen.dart';

// ─── Section enum ─────────────────────────────────────────────────────────────

enum _TxnSection {
  loansClosed,
  loansDisbursed,
  expenses,
  adjustments,
  partnerTransactions,
}

extension _TxnSectionX on _TxnSection {
  String get label => switch (this) {
        _TxnSection.loansClosed => 'Loans Closed',
        _TxnSection.loansDisbursed => 'Loans Disbursed',
        _TxnSection.expenses => 'Expenses',
        _TxnSection.adjustments => 'Adjustments',
        _TxnSection.partnerTransactions => 'Partner Transactions',
      };

  List<String> get paymentTypes => switch (this) {
        _TxnSection.loansClosed => [
            PaymentType.loanFullClosure,
            PaymentType.renewalInterestPaid,
          ],
        _TxnSection.loansDisbursed => [
            PaymentType.loanDisbursed,
            PaymentType.loanIncreaseDisbursed,
          ],
        _TxnSection.expenses => [PaymentType.expense],
        _TxnSection.adjustments => [PaymentType.adjustment],
        _TxnSection.partnerTransactions => [PaymentType.capital],
      };
}

// All sections in display order.
const _allSections = [
  _TxnSection.loansClosed,
  _TxnSection.loansDisbursed,
  _TxnSection.expenses,
  _TxnSection.adjustments,
  _TxnSection.partnerTransactions,
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class EditTransactionScreen extends StatefulWidget {
  const EditTransactionScreen({
    super.key,
    required this.dateStr,
    required this.displayDate,
  });

  final String dateStr;
  final String displayDate;

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  bool _loading = true;

  /// All payments for the day, keyed by payment type for quick lookup.
  List<PaymentModel> _allPayments = [];

  /// Sections that have at least one payment row for this day.
  List<_TxnSection> _availableSections = [];

  /// Pledge data for pledge-linked payments (lazy-loaded but cached upfront).
  final Map<int, PledgeModel?> _pledgeCache = {};

  /// Ledger account names for CAPITAL (partner) rows.
  final Map<int, String> _ledgerNameCache = {};

  _TxnSection? _selectedSection;
  int? _selectedPaymentId; // for single-row types
  // For adjustments we track the 'primary' payment (out for transfers, the row
  // itself for add_cash/add_bank) separately from the partner.
  PaymentModel? _selectedPayment;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final allTypes = _allSections.expand((s) => s.paymentTypes).toList();
    final payments =
        await PaymentsRepository.instance.getByDateAndTypes(widget.dateStr, allTypes);

    // Resolve pledges for all pledge-linked payments.
    final pledgeIds = payments
        .where((p) => p.pledgeId != null)
        .map((p) => p.pledgeId!)
        .toSet();
    for (final id in pledgeIds) {
      _pledgeCache[id] =
          await PledgeRepository.instance.getPledgeById(id);
    }

    // Resolve ledger account names for CAPITAL (partner) rows.
    final ledgerIds = payments
        .where((p) =>
            p.paymentType == PaymentType.capital &&
            p.ledgerAccountId != null)
        .map((p) => p.ledgerAccountId!)
        .toSet();
    if (ledgerIds.isNotEmpty) {
      final allAccounts =
          await ChartOfAccountsRepository.instance.getAll();
      for (final a in allAccounts) {
        if (a.id != null && ledgerIds.contains(a.id)) {
          _ledgerNameCache[a.id!] = a.name;
        }
      }
    }

    // Determine which sections have ≥1 visible item.
    final availableSections = _allSections.where((section) {
      final items = _itemsForSection(section, payments);
      return items.isNotEmpty;
    }).toList();

    if (!mounted) return;
    setState(() {
      _allPayments = payments;
      _availableSections = availableSections;
      _loading = false;
    });
  }

  /// Returns the display items for [section], deduplicating transfer-adjustment
  /// pairs to show only one row per logical adjustment.
  List<PaymentModel> _itemsForSection(
      _TxnSection section, List<PaymentModel> payments) {
    final sectionPayments = payments
        .where((p) => section.paymentTypes.contains(p.paymentType))
        .toList();

    if (section != _TxnSection.adjustments) return sectionPayments;

    // For adjustments: show only the 'out' direction for transfer types,
    // and the 'in' direction for add types (which are single-row).
    const transferSubs = {
      PaymentSubCategory.cashToBank,
      PaymentSubCategory.cashToUpi,
      PaymentSubCategory.bankToCash,
      PaymentSubCategory.upiToCash,
      PaymentSubCategory.bankToBank,
    };
    return sectionPayments.where((p) {
      final sub = p.subCategory ?? '';
      if (transferSubs.contains(sub)) {
        return p.direction == PaymentDirection.outward;
      }
      return true;
    }).toList();
  }

  List<PaymentModel> get _currentItems =>
      _selectedSection == null
          ? []
          : _itemsForSection(_selectedSection!, _allPayments);

  // ─── Item label helpers ───────────────────────────────────────────────────

  String _itemLabel(PaymentModel p) {
    final section = _selectedSection;
    if (section == null) return '';

    switch (section) {
      case _TxnSection.loansClosed:
      case _TxnSection.loansDisbursed:
        final pledge = _pledgeCache[p.pledgeId];
        final pledgeNo = pledge?.pledgeNumber ?? '#?';
        final customer = pledge?.customerName ?? '';
        final suffix = customer.isNotEmpty ? ' — $customer' : '';
        return 'Pledge #$pledgeNo$suffix — ${money(p.amount)}';

      case _TxnSection.expenses:
        final cat = p.subCategory ?? 'Expense';
        return '$cat — ${money(p.amount)}';

      case _TxnSection.adjustments:
        return '${_adjustmentLabel(p)} — ${money(p.amount)}';

      case _TxnSection.partnerTransactions:
        final kind = switch (p.subCategory) {
          PaymentSubCategory.capitalContribution => 'Contribution',
          PaymentSubCategory.tdsPayment => 'TDS Payment',
          _ => 'Drawings',
        };
        final partner = (p.ledgerAccountId != null
                ? _ledgerNameCache[p.ledgerAccountId]
                : null) ??
            '?';
        return '$kind — $partner — ${money(p.amount)}';
    }
  }

  String _adjustmentLabel(PaymentModel p) {
    return switch (p.subCategory ?? '') {
      PaymentSubCategory.addCash => 'Cash Added',
      PaymentSubCategory.addBank => 'Bank Amount Added',
      PaymentSubCategory.addUpi => 'UPI Added',
      PaymentSubCategory.cashToBank => 'Cash → Bank',
      PaymentSubCategory.cashToUpi => 'Cash → UPI',
      PaymentSubCategory.bankToCash => 'Bank → Cash',
      PaymentSubCategory.upiToCash => 'UPI → Cash',
      PaymentSubCategory.bankToBank => 'Bank → Bank',
      _ => 'Adjustment',
    };
  }

  // ─── Proceed / route ─────────────────────────────────────────────────────

  Future<void> _proceed() async {
    if (_selectedPayment == null || _selectedSection == null) return;

    bool? result;

    switch (_selectedSection!) {
      case _TxnSection.loansClosed:
        result = await _routeToLoanClosure(_selectedPayment!);

      case _TxnSection.loansDisbursed:
        result = await _routeToLoanDisbursement(_selectedPayment!);

      case _TxnSection.expenses:
        result = await _showEditExpenseSheet(_selectedPayment!);

      case _TxnSection.adjustments:
        result = await _routeToAdjustment(_selectedPayment!);

      case _TxnSection.partnerTransactions:
        result = await _showEditPartnerSheet(_selectedPayment!);
    }

    if (!mounted) return;
    if (result == true) Navigator.pop(context, true);
  }

  bool get _canDelete =>
      _selectedSection == _TxnSection.expenses ||
      _selectedSection == _TxnSection.adjustments ||
      _selectedSection == _TxnSection.partnerTransactions;

  Future<bool?> _routeToLoanClosure(PaymentModel payment) async {
    final pledge = _pledgeCache[payment.pledgeId];
    if (pledge == null) {
      _showError('Could not load pledge data. Please try again.');
      return null;
    }
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditLoanClosureScreen(
          payment: payment,
          pledge: pledge,
          dateStr: widget.dateStr,
        ),
      ),
    );
  }

  Future<bool?> _routeToLoanDisbursement(PaymentModel payment) async {
    final pledge = _pledgeCache[payment.pledgeId];
    if (pledge == null) {
      _showError('Could not load pledge data. Please try again.');
      return null;
    }
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditLoanDisbursementScreen(
          payment: payment,
          pledge: pledge,
          dateStr: widget.dateStr,
        ),
      ),
    );
  }

  Future<bool?> _routeToAdjustment(PaymentModel payment) async {
    const transferSubs = {
      PaymentSubCategory.cashToBank,
      PaymentSubCategory.cashToUpi,
      PaymentSubCategory.bankToCash,
      PaymentSubCategory.upiToCash,
      PaymentSubCategory.bankToBank,
    };

    PaymentModel? partner;
    final sub = payment.subCategory ?? '';

    if (transferSubs.contains(sub)) {
      // The 'out' row is the editPayment; find its 'in' partner.
      partner = await PaymentsRepository.instance.getAdjustmentPartner(
        payment.id!,
        widget.dateStr,
        sub,
        payment.amount,
        PaymentDirection.inward,
      );
      if (partner == null) {
        _showError(
            'Could not find the paired row for this transfer. Data may be '
            'inconsistent — please contact support.');
        return null;
      }
    }

    if (!mounted) return null;
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdjustBalanceScreen(
          date: _parseDate(widget.dateStr),
          editPayment: payment,
          editPartnerPayment: partner,
        ),
      ),
    );
  }

  // ─── Delete ──────────────────────────────────────────────────────────────

  Future<void> _delete() async {
    final payment = _selectedPayment;
    if (payment == null) return;

    // Show confirmation dialog with mandatory reason.
    String reason = '';
    String? dialogError;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Delete Transaction?',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.red)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _itemLabel(payment),
                style: const TextStyle(
                    fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Reason for deletion *',
                  hintText: 'e.g. "Added to wrong date"',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                onChanged: (v) {
                  reason = v;
                  if (dialogError != null) setD(() => dialogError = null);
                },
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(dialogError!,
                    style: const TextStyle(
                        color: FlowColors.red, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.red,
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
              onPressed: () {
                if (reason.trim().isEmpty) {
                  setD(() => dialogError = 'Reason is required.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;

    // Day-lock guard.
    final isLocked = await DailyBalanceRepository.instance
        .isDateLocked(widget.dateStr);
    if (!mounted) return;
    if (isLocked) {
      _showError('Day is locked — deletions are not allowed.');
      return;
    }

    // For transfer adjustments, find the paired row.
    const transferSubs = {
      PaymentSubCategory.cashToBank,
      PaymentSubCategory.cashToUpi,
      PaymentSubCategory.bankToCash,
      PaymentSubCategory.upiToCash,
      PaymentSubCategory.bankToBank,
    };
    PaymentModel? partner;
    final sub = payment.subCategory ?? '';
    if (_selectedSection == _TxnSection.adjustments &&
        transferSubs.contains(sub)) {
      partner = await PaymentsRepository.instance.getAdjustmentPartner(
        payment.id!,
        widget.dateStr,
        sub,
        payment.amount,
        PaymentDirection.inward,
      );
    }
    if (!mounted) return;

    try {
      final db = await AppDatabase.instance.database;
      await db.transaction((txn) async {
        await PaymentsRepository.instance.deletePayment(txn, payment.id!);
        if (partner != null) {
          await PaymentsRepository.instance.deletePayment(txn, partner.id!);
        }
        await AuditLogRepository.instance.log(
          actionCategory: AuditCategory.dayManagement,
          action: 'TRANSACTION_DELETED',
          entityType: 'payments',
          entityId: payment.id.toString(),
          oldValueJson: jsonEncode({
            'type': payment.paymentType,
            'subCategory': payment.subCategory,
            'amount': payment.amount,
            'direction': payment.direction,
          }),
          reason: reason.trim(),
          txn: txn,
        );
      });
      await DailyBalanceRepository.instance.cascadeFrom(widget.dateStr);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      _showError('Failed to delete. Please try again.');
    }
  }

  // ─── Expense edit bottom sheet (Branch C) ─────────────────────────────────

  Future<bool?> _showEditExpenseSheet(PaymentModel payment) async {
    final db = await AppDatabase.instance.database;
    final catRows = await db.query(
      'expense_categories',
      columns: ['id', 'name'],
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
    final allCats = catRows.map((r) => r['name'] as String).toList();
    final catIdByName = {
      for (final r in catRows) r['name'] as String: r['id'] as int,
    };
    // Ledger account linked to each category — a category change must also
    // update payments.ledger_account_id (the posting engine's sole reference).
    final chartRows = await db.query('chart_of_accounts',
        columns: ['id', 'linked_id'],
        where: "linked_table = 'expense_categories'");
    final ledgerIdByCategoryId = {
      for (final r in chartRows) r['linked_id'] as int: r['id'] as int,
    };
    final accounts = await BankAccountRepository.instance.getActive();

    if (!mounted) return null;

    final payKey = GlobalKey<SharedSplitPaymentWidgetState>();
    final amtPaise = (payment.amount.abs() * 100).round() % 100;
    final amountCtrl = TextEditingController(
        text: amtPaise == 0
            ? formatIndian(payment.amount.round().toString())
            : '${formatIndian(payment.amount.floor().toString())}.'
                '${amtPaise.toString().padLeft(2, '0')}');
    final notesCtrl = TextEditingController(text: payment.notes ?? '');
    final reasonCtrl = TextEditingController();

    final existingCat = payment.subCategory;
    String? selectedCat =
        (existingCat != null && allCats.contains(existingCat))
            ? existingCat
            : null;

    double expTotal = payment.amount;
    String? error;
    bool saving = false;

    final String initialMode;
    if (payment.cashAmount > 0 && payment.bankAmount > 0) {
      initialMode = 'split';
    } else if (payment.bankAmount > 0) {
      initialMode = 'bank';
    } else {
      initialMode = 'cash';
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 16),
                  const Text('Edit Expense',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: FlowColors.primary)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: amountCtrl,
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [IndianDecimalFormatter()],
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹) *',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final parsed =
                          double.tryParse(v.replaceAll(',', '')) ?? 0;
                      setBS(() {
                        expTotal = parsed;
                        if (error != null) error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCat,
                    decoration: const InputDecoration(
                        labelText: 'Category *',
                        border: OutlineInputBorder()),
                    items: allCats
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setBS(() => selectedCat = v),
                  ),
                  const SizedBox(height: 16),
                  SharedSplitPaymentWidget(
                    key: payKey,
                    total: expTotal,
                    totalLabel: 'Expense Amount',
                    bankAccounts: accounts,
                    isMoneyIn: false,
                    showTotalBanner: false,
                    initialMode: initialMode,
                    initialCashAmount: payment.cashAmount > 0
                        ? payment.cashAmount
                        : null,
                    initialBankAmount: payment.bankAmount > 0
                        ? payment.bankAmount
                        : null,
                    initialBankAccountId: payment.bankAccountId,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reason for edit *',
                      hintText: 'e.g. "Wrong category selected"',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    onChanged: (_) {
                      if (error != null) setBS(() => error = null);
                    },
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!,
                        style: const TextStyle(
                            color: FlowColors.red, fontSize: 14)),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel',
                              style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: FlowColors.orange,
                              foregroundColor: Colors.white),
                          onPressed: saving
                              ? null
                              : () async {
                                  final amt = double.tryParse(
                                      amountCtrl.text.replaceAll(',', '').trim());
                                  if (amt == null || amt <= 0) {
                                    setBS(() => error = 'Enter a valid amount.');
                                    return;
                                  }
                                  if (selectedCat == null) {
                                    setBS(() => error = 'Select a category.');
                                    return;
                                  }
                                  final reason = reasonCtrl.text.trim();
                                  if (reason.isEmpty) {
                                    setBS(() => error = 'Reason is required.');
                                    return;
                                  }
                                  final payErr =
                                      payKey.currentState?.validate();
                                  if (payErr != null) {
                                    setBS(() => error = payErr);
                                    return;
                                  }

                                  final isLocked = await DailyBalanceRepository
                                      .instance
                                      .isDateLocked(widget.dateStr);
                                  if (isLocked) {
                                    setBS(() => error = 'Day is locked.');
                                    return;
                                  }

                                  final cashAmt =
                                      payKey.currentState?.cashAmount ?? amt;
                                  final bankAmt =
                                      payKey.currentState?.bankAmount ?? 0;
                                  final bankAccId =
                                      payKey.currentState?.bankAccountId;
                                  final notes = notesCtrl.text.trim();
                                  final payId = payment.id!;

                                  setBS(() => saving = true);
                                  try {
                                    final db = await AppDatabase.instance.database;
                                    await db.transaction((txn) async {
                                      await PaymentsRepository.instance
                                          .updatePaymentFields(
                                        txn,
                                        payId,
                                        amount: amt,
                                        cashAmount: cashAmt,
                                        bankAmount: bankAmt,
                                        bankAccountId:
                                            bankAmt > 0 ? bankAccId : null,
                                        clearBankAccountId: bankAmt == 0,
                                        notes: notes.isEmpty ? null : notes,
                                        subCategory: selectedCat,
                                        ledgerAccountId: ledgerIdByCategoryId[
                                            catIdByName[selectedCat]],
                                      );
                                      await AuditLogRepository.instance.log(
                                        actionCategory:
                                            AuditCategory.dayManagement,
                                        action: 'TRANSACTION_EDITED',
                                        entityType: 'payments',
                                        entityId: payId.toString(),
                                        oldValueJson: jsonEncode({
                                          'category': payment.subCategory,
                                          'amount': payment.amount,
                                          'cash': payment.cashAmount,
                                          'bank': payment.bankAmount,
                                        }),
                                        newValueJson: jsonEncode({
                                          'category': selectedCat,
                                          'amount': amt,
                                          'cash': cashAmt,
                                          'bank': bankAmt,
                                        }),
                                        reason: reason,
                                        txn: txn,
                                      );
                                    });
                                    await DailyBalanceRepository.instance
                                        .cascadeFrom(widget.dateStr);
                                    if (!ctx.mounted) return;
                                    Navigator.pop(ctx, true);
                                  } catch (_) {
                                    setBS(() {
                                      error = 'Failed to save. Please try again.';
                                      saving = false;
                                    });
                                  }
                                },
                          child: saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Text('SAVE',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return result;
  }

  // ─── Partner transaction edit sheet ──────────────────────────────────────

  Future<bool?> _showEditPartnerSheet(PaymentModel payment) async {
    // Load all capital accounts and active bank accounts before opening sheet.
    final allAccounts = await ChartOfAccountsRepository.instance.getAll();
    final partners = allAccounts
        .where(
            (a) => a.accountType == LedgerAccountType.capital && a.isSystem)
        .toList();
    final bankAccounts = await BankAccountRepository.instance.getActive();
    if (!mounted) return null;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditPartnerSheet(
        payment: payment,
        partners: partners,
        bankAccounts: bankAccounts,
        dateStr: widget.dateStr,
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  DateTime _parseDate(String iso) {
    final p = iso.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

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
            const Text('Edit Transaction',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.displayDate,
                style: const TextStyle(
                    fontSize: 13, color: FlowColors.textOnNavyMuted)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _availableSections.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No transactions to edit for this day.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const FlowNoticeBox(
                      text:
                          'Select the section and then the specific transaction '
                          'you want to correct.',
                      color: FlowColors.primary,
                      backgroundColor: FlowColors.accent,
                      icon: Icons.info_outline,
                    ),
                    const SizedBox(height: 20),

                    // ── Step 1: Section dropdown ───────────────────────────
                    _SectionHeader(step: '1', label: 'Select Section'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<_TxnSection>(
                      initialValue: _selectedSection,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      hint: const Text('Choose a section…'),
                      items: _availableSections
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s.label),
                              ))
                          .toList(),
                      onChanged: (s) => setState(() {
                        _selectedSection = s;
                        _selectedPayment = null;
                        _selectedPaymentId = null;
                      }),
                    ),
                    const SizedBox(height: 24),

                    // ── Step 2: Item dropdown ──────────────────────────────
                    if (_selectedSection != null) ...[
                      _SectionHeader(step: '2', label: 'Select Transaction'),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedPaymentId,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        hint: const Text('Choose a transaction…'),
                        isExpanded: true,
                        items: _currentItems.map((p) {
                          return DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              _itemLabel(p),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (id) {
                          final pay = _currentItems
                              .cast<PaymentModel?>()
                              .firstWhere((p) => p?.id == id,
                                  orElse: () => null);
                          setState(() {
                            _selectedPaymentId = id;
                            _selectedPayment = pay;
                          });
                        },
                      ),
                      const SizedBox(height: 32),
                    ],

                    // ── Action buttons ─────────────────────────────────────
                    if (_selectedPayment != null)
                      Row(
                        children: [
                          if (_canDelete) ...[
                            Expanded(
                              child: SizedBox(
                                height: 54,
                                child: OutlinedButton.icon(
                                  onPressed: _delete,
                                  icon: const Icon(Icons.delete_outline,
                                      color: FlowColors.red, size: 20),
                                  label: const Text('DELETE',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: FlowColors.red)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: FlowColors.red),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: SizedBox(
                              height: 54,
                              child: ElevatedButton.icon(
                                onPressed: _proceed,
                                icon: const Icon(Icons.edit, size: 20),
                                label: const Text('PROCEED TO EDIT',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: FlowColors.primary,
                                  foregroundColor: FlowColors.goldRich,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
    );
  }
}

// ─── Partner transaction edit sheet widget ────────────────────────────────────

class _EditPartnerSheet extends StatefulWidget {
  const _EditPartnerSheet({
    required this.payment,
    required this.partners,
    required this.bankAccounts,
    required this.dateStr,
  });

  final PaymentModel payment;
  final List<LedgerAccount> partners;
  final List<BankAccount> bankAccounts;
  final String dateStr;

  @override
  State<_EditPartnerSheet> createState() => _EditPartnerSheetState();
}

class _EditPartnerSheetState extends State<_EditPartnerSheet> {
  static const _modeDrawings = 'drawings';
  static const _modeContribution = 'contribution';
  static const _modeTds = 'tds';

  late String _mode;
  late int? _selectedPartnerId;
  GlobalKey<SharedSplitPaymentWidgetState> _payKey = GlobalKey();

  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  double _total = 0;
  String? _error;
  bool _saving = false;

  bool get _isMoneyIn => _mode == _modeContribution;

  String get _subCategory => switch (_mode) {
        _modeDrawings => PaymentSubCategory.drawings,
        _modeTds => PaymentSubCategory.tdsPayment,
        _ => PaymentSubCategory.capitalContribution,
      };

  String get _direction =>
      _isMoneyIn ? PaymentDirection.inward : PaymentDirection.outward;

  @override
  void initState() {
    super.initState();
    final sub = widget.payment.subCategory ?? '';
    _mode = switch (sub) {
      PaymentSubCategory.capitalContribution => _modeContribution,
      PaymentSubCategory.tdsPayment => _modeTds,
      _ => _modeDrawings,
    };
    _selectedPartnerId = widget.payment.ledgerAccountId;
    _amountCtrl.text = widget.payment.amount.round().toString();
    _total = widget.payment.amount;
    _notesCtrl.text = widget.payment.notes ?? '';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  void _setMode(String mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _payKey = GlobalKey();
      _error = null;
    });
  }

  Future<void> _save() async {
    final amt =
        double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    if (_selectedPartnerId == null) {
      setState(() => _error = 'Select a partner.');
      return;
    }
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Reason for edit is required.');
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
    final notes = _notesCtrl.text.trim();
    final payId = widget.payment.id!;

    setState(() => _saving = true);
    try {
      final isLocked = await DailyBalanceRepository.instance
          .isDateLocked(widget.dateStr);
      if (isLocked) {
        setState(() {
          _error = 'Day is locked.';
          _saving = false;
        });
        return;
      }

      final db = await AppDatabase.instance.database;
      await db.transaction((txn) async {
        await PaymentsRepository.instance.updatePaymentFields(
          txn,
          payId,
          amount: amt,
          cashAmount: cashAmt,
          bankAmount: bankAmt,
          bankAccountId: bankAmt > 0 ? bankAccId : null,
          clearBankAccountId: bankAmt == 0,
          subCategory: _subCategory,
          ledgerAccountId: _selectedPartnerId,
          direction: _direction,
          notes: notes.isEmpty ? null : notes,
        );
        await AuditLogRepository.instance.log(
          actionCategory: AuditCategory.dayManagement,
          action: 'TRANSACTION_EDITED',
          entityType: 'payments',
          entityId: payId.toString(),
          oldValueJson: jsonEncode({
            'subCategory': widget.payment.subCategory,
            'amount': widget.payment.amount,
            'cash': widget.payment.cashAmount,
            'bank': widget.payment.bankAmount,
            'partnerId': widget.payment.ledgerAccountId,
          }),
          newValueJson: jsonEncode({
            'subCategory': _subCategory,
            'amount': amt,
            'cash': cashAmt,
            'bank': bankAmt,
            'partnerId': _selectedPartnerId,
          }),
          reason: reason,
          txn: txn,
        );
      });
      await DailyBalanceRepository.instance.cascadeFrom(widget.dateStr);
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Edit Partner Transaction',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.primary)),
              const SizedBox(height: 16),
              // Mode selector
              Row(
                children: [
                  _ModeChipBtn(
                    label: 'Drawings',
                    icon: Icons.north_east,
                    selected: _mode == _modeDrawings,
                    onTap: () => _setMode(_modeDrawings),
                  ),
                  const SizedBox(width: 8),
                  _ModeChipBtn(
                    label: 'Contribution',
                    icon: Icons.south_west,
                    selected: _mode == _modeContribution,
                    onTap: () => _setMode(_modeContribution),
                  ),
                  const SizedBox(width: 8),
                  _ModeChipBtn(
                    label: 'TDS',
                    icon: Icons.receipt_long,
                    selected: _mode == _modeTds,
                    onTap: () => _setMode(_modeTds),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Partner dropdown
              DropdownButtonFormField<int>(
                initialValue: _selectedPartnerId,
                decoration: const InputDecoration(
                    labelText: 'Partner', border: OutlineInputBorder()),
                items: widget.partners
                    .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.name,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedPartnerId = v),
              ),
              const SizedBox(height: 14),
              // Amount
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [IndianNumberFormatter()],
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  labelText: 'Amount (₹) *',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final parsed =
                      double.tryParse(v.replaceAll(',', '')) ?? 0;
                  setState(() {
                    _total = parsed;
                    if (_error != null) _error = null;
                  });
                },
              ),
              const SizedBox(height: 14),
              SharedSplitPaymentWidget(
                key: _payKey,
                total: _total,
                totalLabel: switch (_mode) {
                  _modeDrawings => 'Drawings Amount',
                  _modeTds => 'TDS Amount',
                  _ => 'Contribution Amount',
                },
                bankAccounts: widget.bankAccounts,
                isMoneyIn: _isMoneyIn,
                showTotalBanner: false,
                initialMode: widget.payment.cashAmount > 0 &&
                        widget.payment.bankAmount > 0
                    ? 'split'
                    : widget.payment.bankAmount > 0
                        ? 'bank'
                        : 'cash',
                initialCashAmount: widget.payment.cashAmount > 0
                    ? widget.payment.cashAmount
                    : null,
                initialBankAmount: widget.payment.bankAmount > 0
                    ? widget.payment.bankAmount
                    : null,
                initialBankAccountId: widget.payment.bankAccountId,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason for edit *',
                  hintText: 'e.g. "Wrong amount entered"',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(
                        color: FlowColors.red, fontSize: 14)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel',
                          style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: FlowColors.orange,
                          foregroundColor: Colors.white),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('SAVE',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChipBtn extends StatelessWidget {
  const _ModeChipBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color:
                selected ? FlowColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? FlowColors.primary : Colors.black26,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18,
                  color:
                      selected ? FlowColors.goldRich : Colors.black45),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: selected ? FlowColors.goldRich : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Step header widget ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.step, required this.label});
  final String step;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: FlowColors.primary,
          child: Text(step,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.goldRich)),
        ),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: FlowColors.primary)),
      ],
    );
  }
}
