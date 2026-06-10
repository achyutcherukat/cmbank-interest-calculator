import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/flow_widgets.dart';

class NewPledgeScreen extends StatefulWidget {
  const NewPledgeScreen({super.key});

  @override
  State<NewPledgeScreen> createState() => _NewPledgeScreenState();
}

class _NewPledgeScreenState extends State<NewPledgeScreen> {
  final _weightController = TextEditingController(text: '20');
  final _rateController = TextEditingController(text: '5000');
  final _pledgeNoController = TextEditingController(text: '3211');
  final _loanAmountController = TextEditingController();

  int _step = 1;
  bool _saved = false;
  String _paymentMode = 'cash';

  double get _weight => double.tryParse(_weightController.text) ?? 0;
  double get _rate => double.tryParse(_rateController.text) ?? 0;
  double get _maxValue => _weight * _rate;

  @override
  void initState() {
    super.initState();
    _loanAmountController.text = _maxValue.toStringAsFixed(2);
    _weightController.addListener(_syncLoanAmount);
    _rateController.addListener(_syncLoanAmount);
  }

  @override
  void dispose() {
    _weightController.dispose();
    _rateController.dispose();
    _pledgeNoController.dispose();
    _loanAmountController.dispose();
    super.dispose();
  }

  void _syncLoanAmount() {
    _loanAmountController.text = _maxValue.toStringAsFixed(2);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_saved) {
      return _SuccessScreen(
        pledgeNo: _pledgeNoController.text,
        amount: double.tryParse(_loanAmountController.text) ?? 0,
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: Text(_step == 1 ? 'New Pledge - Step 1' : 'New Pledge - Step 2'),
        leading: BackButton(
          onPressed: _step == 2 ? () => setState(() => _step = 1) : null,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StepIndicator(step: _step),
          const SizedBox(height: 20),
          if (_step == 1) _goldCalculator() else _pledgeDetails(),
        ],
      ),
    );
  }

  Widget _goldCalculator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowSectionTitle('Gold Calculator'),
        _numberField('Weight (grams)', _weightController),
        _numberField('Pledge Rate per gram', _rateController),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Rate is usually set on the home screen by staff today.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        FlowCard(
          backgroundColor: FlowColors.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Max Pledge Value',
                style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                money(_maxValue),
                style: const TextStyle(
                  color: FlowColors.primary,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text('${_weight.toStringAsFixed(2)}g x Rs ${_rate.toStringAsFixed(2)}/g'),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => setState(() => _step = 2),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('CALCULATE & PROCEED'),
        ),
      ],
    );
  }

  Widget _pledgeDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowSectionTitle('Pledge Details'),
        _textField('Pledge Number', _pledgeNoController),
        const Text(
          'Auto generated. Edit if needed. Duplicate check will be applied.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 14),
        _numberField('Loan Amount', _loanAmountController),
        Text(
          'Max: ${money(_maxValue)}. Edit if giving less.',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 18),
        _photoPicker('ID Proof Photo'),
        _photoPicker('Gold Item Photo'),
        const FlowSectionTitle('How is cash being given?'),
        Row(
          children: [
            Expanded(child: _modeButton('cash', 'Cash')),
            const SizedBox(width: 10),
            Expanded(child: _modeButton('upi', 'UPI')),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => setState(() => _paymentMode = 'split'),
          icon: const Icon(Icons.call_split),
          label: const Text('SPLIT PAYMENT'),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: () => setState(() => _saved = true),
          icon: const Icon(Icons.save_outlined),
          label: const Text('SAVE PLEDGE'),
        ),
      ],
    );
  }

  Widget _textField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
        ],
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _photoPicker(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: FlowColors.primary, fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        Container(
          height: 78,
          width: double.infinity,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(top: 8, bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFEFEF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('No photo yet - tap to add', style: TextStyle(color: Colors.black54)),
        ),
      ],
    );
  }

  Widget _modeButton(String value, String label) {
    final selected = _paymentMode == value;
    return OutlinedButton(
      onPressed: () => setState(() => _paymentMode = value),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? FlowColors.accent : Colors.white,
        side: BorderSide(color: selected ? FlowColors.primary : Colors.black26, width: 2),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(label),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _bubble(1),
        Container(width: 42, height: 3, color: step > 1 ? FlowColors.primary : Colors.black26),
        _bubble(2),
        const SizedBox(width: 12),
        Text(step == 1 ? 'Gold Calculator' : 'Pledge Details'),
      ],
    );
  }

  Widget _bubble(int value) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: step >= value ? FlowColors.primary : Colors.black26,
      child: Text('$value', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}

class _SuccessScreen extends StatelessWidget {
  const _SuccessScreen({required this.pledgeNo, required this.amount});

  final String pledgeNo;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: const Text('New Pledge'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: FlowColors.green, size: 72),
              const SizedBox(height: 16),
              const Text('Pledge Saved!', style: TextStyle(fontSize: 24, color: FlowColors.green, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Pledge No: $pledgeNo', style: const TextStyle(fontSize: 18)),
              Text('Amount: ${money(amount)}', style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('BACK TO HOME'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
