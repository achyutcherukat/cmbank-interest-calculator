import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/settings/app_settings_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../data/pledge_item_model.dart';
import '../data/pledge_model.dart';
import '../data/pledge_repository.dart';

const _itemTypes = [
  'Gold Necklace',
  'Gold Ring',
  'Gold Earrings',
  'Gold Bangles',
  'Gold Bracelet',
  'Gold Chain',
  'Gold Coin',
  'Gold Bar',
  'Mixed Gold Items',
  'Other',
];

class NewPledgeScreen extends StatefulWidget {
  const NewPledgeScreen({super.key});

  @override
  State<NewPledgeScreen> createState() => _NewPledgeScreenState();
}

class _NewPledgeScreenState extends State<NewPledgeScreen> {
  // Step 1
  final _weightController = TextEditingController();
  final _rateController = TextEditingController();

  // Step 2
  final _pledgeNoController = TextEditingController();
  final _loanAmountController = TextEditingController();
  final _cashAmountController = TextEditingController();
  final _upiAmountController = TextEditingController();

  int _step = 1;
  String _paymentMode = 'cash';
  String? _itemDescription;
  File? _itemPhoto;
  File? _idProofPhoto;
  bool _isSaving = false;
  bool _pledgeNoError = false;
  String? _savedPledgeNo;
  double? _savedAmount;

  final _imagePicker = ImagePicker();
  final _settingsRepository = AppSettingsRepository();

  double get _weight => double.tryParse(_weightController.text) ?? 0;
  double get _rate => double.tryParse(_rateController.text) ?? 0;
  double get _maxValue => _weight * _rate;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
    _weightController.addListener(() => setState(() {}));
    _rateController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _weightController.dispose();
    _rateController.dispose();
    _pledgeNoController.dispose();
    _loanAmountController.dispose();
    _cashAmountController.dispose();
    _upiAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    final rateVal = await _settingsRepository.getString('default_pledge_rate');
    if (mounted) {
      setState(() {
        _rateController.text =
            double.tryParse(rateVal ?? '0')?.toStringAsFixed(0) ?? '0';
      });
    }
  }

  Future<void> _proceedToStep2() async {
    final w = double.tryParse(_weightController.text.trim());
    final r = double.tryParse(_rateController.text.trim());
    if (w == null || w <= 0) {
      _showError('Enter a valid weight in grams.');
      return;
    }
    if (r == null || r <= 0) {
      _showError('Enter a valid pledge rate per gram.');
      return;
    }
    final nextNo = await PledgeRepository.instance.nextPledgeNumber();
    if (mounted) {
      setState(() {
        _pledgeNoController.text = nextNo;
        _loanAmountController.text = _maxValue.toStringAsFixed(2);
        _step = 2;
      });
    }
  }

  Future<void> _checkPledgeNo() async {
    final no = _pledgeNoController.text.trim();
    if (no.isEmpty) return;
    final exists = await PledgeRepository.instance.pledgeNumberExists(no);
    if (mounted) setState(() => _pledgeNoError = exists);
  }

  Future<void> _pickPhoto(ImageSource source, {required bool isIdProof}) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1200,
      );
      if (picked == null) return;

      final docsDir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${docsDir.path}/pledge_photos');
      await destDir.create(recursive: true);
      final pledgeNo = _pledgeNoController.text.trim();
      final suffix = isIdProof ? 'idproof' : 'item';
      final destFile = File('${destDir.path}/${pledgeNo}_$suffix.jpg');
      await File(picked.path).copy(destFile.path);

      if (mounted) {
        setState(() {
          if (isIdProof) {
            _idProofPhoto = destFile;
          } else {
            _itemPhoto = destFile;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not pick photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _savePledge() async {
    final pledgeNo = _pledgeNoController.text.trim();
    final loanAmount = double.tryParse(_loanAmountController.text.trim());

    if (pledgeNo.isEmpty) {
      _showError('Enter pledge number.');
      return;
    }
    if (_pledgeNoError) {
      _showError('Pledge number $pledgeNo already exists. Choose another.');
      return;
    }
    if (loanAmount == null || loanAmount <= 0) {
      _showError('Enter a valid loan amount.');
      return;
    }
    if (loanAmount > _maxValue) {
      _showError(
          'Loan amount cannot exceed max pledge value of ${money(_maxValue)}.');
      return;
    }
    if (_paymentMode == 'split') {
      final cash = double.tryParse(_cashAmountController.text.trim()) ?? 0;
      final upi = double.tryParse(_upiAmountController.text.trim()) ?? 0;
      if ((cash + upi - loanAmount).abs() > 0.01) {
        _showError('Cash + UPI must equal the loan amount (${money(loanAmount)}).');
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final interestRateVal =
          await _settingsRepository.getString('default_interest_rate');
      final interestRate = double.tryParse(interestRateVal ?? '') ?? 18.0;
      final now = DateTime.now();
      final dateStr = now.toIso8601String().substring(0, 10);

      final pledge = PledgeModel(
        pledgeNumber: pledgeNo,
        pledgeDate: dateStr,
        loanAmount: loanAmount,
        interestRate: interestRate,
        status: 'open',
        createdAt: now.toIso8601String(),
        customerName: '',
        grossWeight: _weight,
        netWeight: _weight,
        purity: '22K',
        pledgeRate: _rate,
      );

      final item = PledgeItemModel(
        pledgeId: 0,
        description: _itemDescription,
        weight: _weight,
        purity: '22K',
        estimatedValue: _maxValue,
        photoPath: _itemPhoto?.path,
        createdAt: now.toIso8601String(),
      );

      double cashAmt = loanAmount;
      double upiAmt = 0;
      if (_paymentMode == 'upi') {
        cashAmt = 0;
        upiAmt = loanAmount;
      } else if (_paymentMode == 'split') {
        cashAmt = double.tryParse(_cashAmountController.text.trim()) ?? 0;
        upiAmt = double.tryParse(_upiAmountController.text.trim()) ?? 0;
      }

      await PledgeRepository.instance.createPledge(
        pledge,
        [item],
        paymentMode: _paymentMode,
        cashAmount: cashAmt,
        upiAmount: upiAmt,
      );

      if (mounted) {
        setState(() {
          _savedPledgeNo = pledgeNo;
          _savedAmount = loanAmount;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving pledge: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK',
                style: TextStyle(fontSize: 18, color: Color(0xFF1A237E))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_savedPledgeNo != null) {
      return _SuccessScreen(pledgeNo: _savedPledgeNo!, amount: _savedAmount ?? 0);
    }
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title:
            Text(_step == 1 ? 'New Pledge — Step 1' : 'New Pledge — Step 2'),
        leading: BackButton(
          onPressed: _step == 2
              ? () => setState(() => _step = 1)
              : () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StepIndicator(step: _step),
          const SizedBox(height: 20),
          if (_step == 1) _buildStep1() else _buildStep2(),
        ],
      ),
    );
  }

  // ─── Step 1 ───────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowSectionTitle('Gold Calculator'),
        _numberField('Weight (grams)', _weightController),
        _numberField('Pledge Rate per gram (₹)', _rateController),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Rate shown on home screen. Update it there if needed.',
            style: TextStyle(color: Colors.black54, fontSize: 15),
          ),
        ),
        FlowCard(
          backgroundColor: FlowColors.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FlowCardTitle('Max Pledge Value'),
              Text(
                money(_maxValue),
                style: const TextStyle(
                    color: FlowColors.primary,
                    fontSize: 30,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                  '${_weight.toStringAsFixed(2)} g × ₹${_rate.toStringAsFixed(2)}/g'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _proceedToStep2,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('PROCEED TO PLEDGE DETAILS'),
        ),
      ],
    );
  }

  // ─── Step 2 ───────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowSectionTitle('Pledge Details'),
        // Pledge number
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: TextField(
            controller: _pledgeNoController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Pledge Number',
              errorText:
                  _pledgeNoError ? 'This pledge number already exists' : null,
            ),
            onChanged: (_) => setState(() => _pledgeNoError = false),
            onEditingComplete: _checkPledgeNo,
          ),
        ),
        const Text('Auto-filled. Edit if needed.',
            style: TextStyle(color: Colors.black54, fontSize: 14)),
        const SizedBox(height: 14),
        _numberField('Loan Amount (₹)', _loanAmountController),
        Text('Max: ${money(_maxValue)}. Can be less.',
            style: const TextStyle(color: Colors.black54, fontSize: 14)),
        const SizedBox(height: 14),

        // Item type dropdown
        const FlowSectionTitle('Item Details'),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: DropdownButtonFormField<String>(
            initialValue: _itemDescription,
            hint: const Text('Select item type',
                style: TextStyle(fontSize: 18)),
            decoration: const InputDecoration(labelText: 'Item Type'),
            items: _itemTypes
                .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t, style: const TextStyle(fontSize: 18))))
                .toList(),
            onChanged: (val) => setState(() => _itemDescription = val),
          ),
        ),

        // Photos
        _buildPhotoBlock(
          title: 'Gold Item Photo',
          photo: _itemPhoto,
          isIdProof: false,
        ),
        const SizedBox(height: 12),
        _buildPhotoBlock(
          title: 'ID Proof Scan',
          photo: _idProofPhoto,
          isIdProof: true,
        ),
        const SizedBox(height: 18),

        // Payment mode
        const FlowSectionTitle('Payment Mode'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _modeButton('cash', 'Cash')),
            const SizedBox(width: 10),
            Expanded(child: _modeButton('upi', 'UPI')),
          ],
        ),
        const SizedBox(height: 10),
        _modeButton('split', 'Split Payment'),
        if (_paymentMode == 'split') ...[
          const SizedBox(height: 14),
          _numberField('Cash Amount (₹)', _cashAmountController),
          _numberField('UPI Amount (₹)', _upiAmountController),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _savePledge,
            icon: _isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'SAVING…' : 'SAVE PLEDGE',
                style: const TextStyle(fontSize: 20)),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildPhotoBlock({
    required String title,
    required File? photo,
    required bool isIdProof,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: FlowColors.primary,
                fontSize: 17,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _pickPhoto(ImageSource.camera, isIdProof: isIdProof),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _pickPhoto(ImageSource.gallery, isIdProof: isIdProof),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (photo != null)
          GestureDetector(
            onTap: () => _openPhotoView(context, photo),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                photo,
                height: 80,
                width: 120,
                fit: BoxFit.cover,
              ),
            ),
          )
        else
          Container(
            height: 60,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEFEFEF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('No photo yet',
                style: TextStyle(color: Colors.black54)),
          ),
      ],
    );
  }

  void _openPhotoView(BuildContext context, File file) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PhotoViewScreen(file: file)),
    );
  }

  // ─── Field Helpers ────────────────────────────────────────────────────────

  Widget _numberField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
        ],
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _modeButton(String value, String label) {
    final selected = _paymentMode == value;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => setState(() => _paymentMode = value),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? FlowColors.accent : Colors.white,
          side: BorderSide(
              color: selected ? FlowColors.primary : Colors.black26, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 17,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}

// ─── Photo Fullscreen Viewer ──────────────────────────────────────────────────

class _PhotoViewScreen extends StatelessWidget {
  const _PhotoViewScreen({required this.file});
  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Photo'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.file(file),
        ),
      ),
    );
  }
}

// ─── Step Indicator ───────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _bubble(1),
        Container(
            width: 42,
            height: 3,
            color: step > 1 ? FlowColors.primary : Colors.black26),
        _bubble(2),
        const SizedBox(width: 12),
        Text(step == 1 ? 'Gold Calculator' : 'Pledge Details',
            style: const TextStyle(fontSize: 16)),
      ],
    );
  }

  Widget _bubble(int value) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: step >= value ? FlowColors.primary : Colors.black26,
      child: Text('$value',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}

// ─── Success Screen ───────────────────────────────────────────────────────────

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
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: FlowColors.green, size: 72),
              const SizedBox(height: 16),
              const Text('Pledge Saved!',
                  style: TextStyle(
                      fontSize: 24,
                      color: FlowColors.green,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Pledge No: $pledgeNo',
                  style: const TextStyle(fontSize: 20)),
              Text('Amount: ${money(amount)}',
                  style: const TextStyle(fontSize: 20)),
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
