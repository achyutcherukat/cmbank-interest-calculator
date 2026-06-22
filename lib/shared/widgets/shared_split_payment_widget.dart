import 'package:flutter/material.dart';

import 'flow_widgets.dart';

class SharedSplitPaymentWidget extends StatefulWidget {
  const SharedSplitPaymentWidget({
    super.key,
    required this.total,
    this.totalLabel = 'Total',
  });

  final double total;
  final String totalLabel;

  @override
  State<SharedSplitPaymentWidget> createState() =>
      SharedSplitPaymentWidgetState();
}

class SharedSplitPaymentWidgetState
    extends State<SharedSplitPaymentWidget> {
  String _mode = 'cash';
  final _cashCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  bool _updating = false;

  String get mode => _mode;

  double get cashAmount => _mode == 'cash'
      ? widget.total
      : _mode == 'upi'
          ? 0
          : (double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0);

  double get upiAmount => _mode == 'upi'
      ? widget.total
      : _mode == 'cash'
          ? 0
          : (double.tryParse(_upiCtrl.text.replaceAll(',', '')) ?? 0);

  @override
  void initState() {
    super.initState();
    _cashCtrl.addListener(_onCashChanged);
    _upiCtrl.addListener(_onUpiChanged);
  }

  @override
  void didUpdateWidget(SharedSplitPaymentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.total != widget.total && _mode == 'split') {
      _updating = true;
      final cash = double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0;
      final rem = widget.total - cash;
      _upiCtrl.text = rem >= 0 ? formatIndian(rem.round().toString()) : '0';
      _updating = false;
    }
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  void _onCashChanged() {
    if (_updating || _mode != 'split') return;
    _updating = true;
    final cash = double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0;
    final rem = widget.total - cash;
    if (rem >= 0) _upiCtrl.text = formatIndian(rem.round().toString());
    _updating = false;
    setState(() {});
  }

  void _onUpiChanged() {
    if (_updating || _mode != 'split') return;
    _updating = true;
    final upi = double.tryParse(_upiCtrl.text.replaceAll(',', '')) ?? 0;
    final rem = widget.total - upi;
    if (rem >= 0) _cashCtrl.text = formatIndian(rem.round().toString());
    _updating = false;
    setState(() {});
  }

  String? validate() {
    if (_mode != 'split') return null;
    final total = (double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0) +
        (double.tryParse(_upiCtrl.text.replaceAll(',', '')) ?? 0);
    if ((total - widget.total).abs() >= 0.5) {
      return 'Cash + UPI must equal ${money(widget.total.round().toDouble())}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final splitCash = double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0;
    final splitUpi = double.tryParse(_upiCtrl.text.replaceAll(',', '')) ?? 0;
    final splitTotal = splitCash + splitUpi;
    final splitOk = (splitTotal - widget.total).abs() < 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowCard(
          backgroundColor: FlowColors.accent,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.totalLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              Text(
                money(widget.total.round().toDouble()),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _modeBtn('cash', 'CASH', Icons.payments)),
            const SizedBox(width: 10),
            Expanded(
                child: _modeBtn('upi', 'UPI', Icons.qr_code_scanner)),
          ],
        ),
        const SizedBox(height: 10),
        _modeBtn('split', 'SPLIT  (Cash + UPI)', Icons.call_split),
        if (_mode == 'split') ...[
          const SizedBox(height: 16),
          _amtField('Cash Amount (₹)', _cashCtrl),
          _amtField('UPI Amount (₹)', _upiCtrl),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

  Widget _modeBtn(String value, String label, IconData icon) {
    final selected = _mode == value;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => setState(() {
          _mode = value;
          if (value != 'split') {
            _cashCtrl.clear();
            _upiCtrl.clear();
          }
        }),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? FlowColors.accent : Colors.white,
          side: BorderSide(
              color: selected ? FlowColors.primary : Colors.black26,
              width: selected ? 2.5 : 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: FlowColors.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
                color: FlowColors.primary,
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
