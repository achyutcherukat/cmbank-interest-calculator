import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../features/accounts/data/bank_account_model.dart';
import 'flow_widgets.dart';

class SharedSplitPaymentWidget extends StatefulWidget {
  const SharedSplitPaymentWidget({
    super.key,
    required this.total,
    this.totalLabel = 'Total',
    this.bankAccounts = const [],
    this.isMoneyIn = true,
    this.showTotalBanner = true,
    this.initialMode = 'cash',
    this.initialCashAmount,
    this.initialBankAmount,
    this.initialBankAccountId,
  });

  final double total;
  final String totalLabel;
  final List<BankAccount> bankAccounts;
  final bool isMoneyIn;
  final bool showTotalBanner;
  final String initialMode;
  final double? initialCashAmount;
  final double? initialBankAmount;
  final int? initialBankAccountId;

  @override
  State<SharedSplitPaymentWidget> createState() =>
      SharedSplitPaymentWidgetState();
}

class SharedSplitPaymentWidgetState extends State<SharedSplitPaymentWidget> {
  String _mode = 'cash';
  final _cashCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  bool _updating = false;
  int? _selectedBankAccountId;

  String get mode => _mode;

  double get cashAmount => _mode == 'cash'
      ? widget.total
      : _mode == 'bank'
          ? 0
          : (double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0);

  double get bankAmount => _mode == 'bank'
      ? widget.total
      : _mode == 'cash'
          ? 0
          : (double.tryParse(_bankCtrl.text.replaceAll(',', '')) ?? 0);

  int? get bankAccountId => _mode == 'cash' ? null : _selectedBankAccountId;

  BankAccount? get _selectedAccount {
    if (widget.bankAccounts.isEmpty) return null;
    if (_selectedBankAccountId != null) {
      final match = widget.bankAccounts
          .cast<BankAccount?>()
          .firstWhere((a) => a?.id == _selectedBankAccountId, orElse: () => null);
      if (match != null) return match;
    }
    final def = widget.bankAccounts
        .cast<BankAccount?>()
        .firstWhere((a) => a?.isDefault == true, orElse: () => null);
    return def ?? widget.bankAccounts.first;
  }

  String get _accountButtonLabel =>
      (_selectedAccount?.name ?? 'BANK').toUpperCase();

  @override
  void initState() {
    super.initState();
    _cashCtrl.addListener(_onCashChanged);
    _bankCtrl.addListener(_onBankChanged);
    _initAccountSelection();
    _mode = widget.initialMode;
    if (widget.initialMode == 'split' &&
        widget.initialCashAmount != null &&
        widget.initialBankAmount != null) {
      _cashCtrl.text = formatIndian(widget.initialCashAmount!.round().toString());
      _bankCtrl.text = formatIndian(widget.initialBankAmount!.round().toString());
    }
  }

  void _initAccountSelection() {
    if (widget.bankAccounts.isEmpty || _selectedBankAccountId != null) return;

    // Prefer the explicitly supplied initial account (e.g. restored from an existing pledge).
    if (widget.initialBankAccountId != null) {
      final match = widget.bankAccounts
          .cast<BankAccount?>()
          .firstWhere((a) => a?.id == widget.initialBankAccountId, orElse: () => null);
      if (match != null) {
        _selectedBankAccountId = match.id;
        return;
      }
    }
    // Fall back to default or first.
    final def = widget.bankAccounts
        .cast<BankAccount?>()
        .firstWhere((a) => a?.isDefault == true, orElse: () => null);
    _selectedBankAccountId = (def ?? widget.bankAccounts.first).id;
  }

  @override
  void didUpdateWidget(SharedSplitPaymentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bankAccounts.isEmpty && widget.bankAccounts.isNotEmpty) {
      _initAccountSelection();
    }
    if (oldWidget.total != widget.total && _mode == 'split') {
      _updating = true;
      final cash = double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0;
      final rem = widget.total - cash;
      _bankCtrl.text = rem >= 0 ? formatIndian(rem.round().toString()) : '0';
      _updating = false;
    }
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  void _onCashChanged() {
    if (_updating || _mode != 'split') return;
    _updating = true;
    final cash = double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0;
    final rem = widget.total - cash;
    if (rem >= 0) _bankCtrl.text = formatIndian(rem.round().toString());
    _updating = false;
    setState(() {});
  }

  void _onBankChanged() {
    if (_updating || _mode != 'split') return;
    _updating = true;
    final bank = double.tryParse(_bankCtrl.text.replaceAll(',', '')) ?? 0;
    final rem = widget.total - bank;
    if (rem >= 0) _cashCtrl.text = formatIndian(rem.round().toString());
    _updating = false;
    setState(() {});
  }

  String? validate() {
    if (_mode != 'split') return null;
    final total = (double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0) +
        (double.tryParse(_bankCtrl.text.replaceAll(',', '')) ?? 0);
    if ((total - widget.total).abs() >= 0.5) {
      final name = _selectedAccount?.name ?? 'Bank';
      return 'Cash + $name must equal ${money(widget.total.round().toDouble())}';
    }
    return null;
  }

  void _showAccountPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomPad = MediaQuery.of(ctx).viewPadding.bottom;
        return Container(
        decoration: const BoxDecoration(
          color: CMBColors.navy,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(color: CMBColors.borderOnNavy, width: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: CMBColors.borderOnNavy,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'SELECT BANK ACCOUNT',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: CMBColors.textOnNavyMuted,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const Divider(color: CMBColors.borderOnNavy, height: 1),
            // Account list
            ...widget.bankAccounts.map((acct) {
              final isSelected = acct.id == _selectedBankAccountId;
              return ListTile(
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _selectedBankAccountId = acct.id;
                    if (_mode == 'cash') _mode = 'bank';
                  });
                },
                leading: Icon(
                  Icons.account_balance,
                  color: isSelected
                      ? CMBColors.goldRich
                      : CMBColors.textOnNavyMuted,
                  size: 20,
                ),
                title: Text(
                  acct.name,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.normal,
                    color: isSelected
                        ? CMBColors.textOnNavyLarge
                        : CMBColors.warmWhite,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (acct.isDefault)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: CMBColors.goldRich.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DEFAULT',
                          style: TextStyle(
                            fontSize: 10,
                            color: CMBColors.goldRich,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    if (isSelected) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.check_circle,
                          color: CMBColors.goldRich, size: 20),
                    ],
                  ],
                ),
              );
            }),
            SizedBox(height: bottomPad + 16),
          ],
        ),
      );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final splitCash = double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0;
    final splitBank = double.tryParse(_bankCtrl.text.replaceAll(',', '')) ?? 0;
    final splitTotal = splitCash + splitBank;
    final splitOk = (splitTotal - widget.total).abs() < 0.5;
    final multiAccount = widget.bankAccounts.length > 1;
    final acctName = _selectedAccount?.name ?? 'Bank';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Total display — semantic green (collecting) / red (disbursing)
        if (widget.showTotalBanner) ...[
          Container(
            decoration: BoxDecoration(
              color: widget.isMoneyIn ? FlowColors.greenLight : FlowColors.redLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isMoneyIn ? FlowColors.green : FlowColors.red,
                width: 1.0,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.totalLabel,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: widget.isMoneyIn ? FlowColors.green : FlowColors.red,
                  ),
                ),
                Text(
                  money(widget.total.round().toDouble()),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: widget.isMoneyIn ? FlowColors.green : FlowColors.red,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        // Account hint — visible when Bank or Split is active and multiple accounts exist
        if ((_mode == 'bank' || _mode == 'split') && multiAccount) ...[
          Row(
            children: [
              const Icon(Icons.touch_app_outlined, size: 13, color: Colors.black38),
              const SizedBox(width: 4),
              const Text(
                'Long press to change bank account',
                style: TextStyle(fontSize: 12, color: Colors.black38),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        // Cash / Bank buttons
        Row(
          children: [
            Expanded(child: _modeBtn('cash', 'CASH', Icons.payments)),
            const SizedBox(width: 10),
            Expanded(
              child: _modeBtn(
                'bank',
                _accountButtonLabel,
                Icons.account_balance,
                onLongPress: multiAccount ? _showAccountPicker : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Split button
        _modeBtn('split', 'SPLIT  (Cash + $acctName)', Icons.call_split,
            onLongPress: multiAccount ? _showAccountPicker : null),
        // Split fields
        if (_mode == 'split') ...[
          const SizedBox(height: 16),
          _amtField('Cash Amount (₹)', _cashCtrl),
          _amtField('$acctName Amount (₹)', _bankCtrl),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: splitOk ? FlowColors.greenLight : FlowColors.redLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: splitOk ? FlowColors.green : FlowColors.red),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total: ${money(splitTotal)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Icon(
                  splitOk ? Icons.check_circle : Icons.cancel,
                  color: splitOk ? FlowColors.green : FlowColors.red,
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _modeBtn(String value, String label, IconData icon,
      {VoidCallback? onLongPress}) {
    final selected = _mode == value;
    return GestureDetector(
      onTap: () => setState(() {
        _mode = value;
        if (value != 'split') {
          _cashCtrl.clear();
          _bankCtrl.clear();
        }
      }),
      onLongPress: onLongPress,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? CMBColors.navy : Colors.white,
          border: Border.all(
            color: selected ? CMBColors.borderOnNavy : CMBColors.borderOnLight,
            width: selected ? 2.0 : 1.5,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? CMBColors.goldRich : CMBColors.navy,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? CMBColors.goldRich : CMBColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amtField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [IndianNumberFormatter()],
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(labelText: label, prefixText: '₹ '),
      ),
    );
  }
}
