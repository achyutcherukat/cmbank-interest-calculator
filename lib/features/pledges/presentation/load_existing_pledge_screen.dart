import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/shared_customer_details_step.dart';
import '../../../shared/widgets/shared_item_details_step.dart';
import '../data/pledge_item_model.dart';
import '../data/pledge_model.dart';
import '../data/pledge_repository.dart';

// ─── Date formatter: types 02012023 → 02/01/2023 ─────────────────────────────

class _DateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    final clamped =
        digits.length > 8 ? digits.substring(0, 8) : digits;
    final buf = StringBuffer();
    for (int i = 0; i < clamped.length; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(clamped[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

DateTime? _parseDisplayDate(String text) {
  final parts = text.trim().split('/');
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  if (year < 1900 || year > 2100) return null;
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;
  try {
    return DateTime(year, month, day);
  } catch (_) {
    return null;
  }
}

String _toIsoDate(String displayDate) {
  final dt = _parseDisplayDate(displayDate);
  if (dt == null) return DateTime.now().toIso8601String().substring(0, 10);
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

String _todayDisplay() {
  final now = DateTime.now();
  return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class LoadExistingPledgeScreen extends StatefulWidget {
  const LoadExistingPledgeScreen({super.key});

  @override
  State<LoadExistingPledgeScreen> createState() =>
      _LoadExistingPledgeScreenState();
}

class _LoadExistingPledgeScreenState
    extends State<LoadExistingPledgeScreen> {
  int _step = 1;
  final _imagePicker = ImagePicker();

  // ── Step 1 ──────────────────────────────────────────────────────────────────
  final _pledgeNoCtrl = TextEditingController();
  final _pledgeDateCtrl = TextEditingController();
  final _loanAmtCtrl = TextEditingController();
  final _grossWeightCtrl = TextEditingController();
  final _netWeightCtrl = TextEditingController();
  bool _pledgeNoError = false;
  bool _pledgeDateError = false;

  // ── Step 2 — Customer ────────────────────────────────────────────────────────
  final _customerKey = GlobalKey<SharedCustomerDetailsStepState>();
  CustomerDetailsData? _capturedCustomer;

  // ── Step 3 — Items ───────────────────────────────────────────────────────────
  final _itemsKey = GlobalKey<SharedItemDetailsStepState>();
  ItemDetailsData? _capturedItems;

  // ── Step 4 — Form scan ───────────────────────────────────────────────────────
  List<File> _formPhotos = [];

  // ── Save state ───────────────────────────────────────────────────────────────
  bool _isSaving = false;
  String? _savedPledgeNo;
  double? _savedAmount;

  // ── Computed getters ─────────────────────────────────────────────────────────
  double get _grossWeight =>
      double.tryParse(_grossWeightCtrl.text) ?? 0;
  double get _netWeight => double.tryParse(_netWeightCtrl.text) ?? 0;
  double get _loanAmount =>
      double.tryParse(_loanAmtCtrl.text.replaceAll(',', '')) ?? 0;

  @override
  void initState() {
    super.initState();
    _pledgeDateCtrl.text = _todayDisplay();
    _grossWeightCtrl.addListener(() => setState(() {}));
    _netWeightCtrl.addListener(() => setState(() {}));
    _loanAmtCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pledgeNoCtrl.dispose();
    _pledgeDateCtrl.dispose();
    _loanAmtCtrl.dispose();
    _grossWeightCtrl.dispose();
    _netWeightCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  void _back() {
    if (_step > 1) {
      setState(() => _step--);
    } else {
      Navigator.pop(context);
    }
  }

  // ── Step 1: proceed ──────────────────────────────────────────────────────────

  Future<void> _proceedFromStep1() async {
    final no = _pledgeNoCtrl.text.trim();
    if (no.isEmpty) {
      _showError('Enter a pledge number.');
      return;
    }

    final dateText = _pledgeDateCtrl.text.trim();
    if (_parseDisplayDate(dateText) == null) {
      setState(() => _pledgeDateError = true);
      _showError('Enter a valid pledge date (DD/MM/YYYY).');
      return;
    }
    setState(() => _pledgeDateError = false);

    if (_loanAmount <= 0) {
      _showError('Enter a valid loan amount.');
      return;
    }

    if (_grossWeight <= 0) {
      _showError('Enter a valid gross weight (grams).');
      return;
    }
    if (_netWeight <= 0) {
      _showError('Enter a valid net weight (grams).');
      return;
    }
    if (_netWeight > _grossWeight) {
      _showError('Net weight cannot exceed gross weight.');
      return;
    }

    // Duplicate pledge number check
    await _checkPledgeNo();
    if (!mounted) return;
    if (_pledgeNoError) {
      _showError(
          'Pledge number $no already exists. Please use a different number.');
      return;
    }

    setState(() => _step = 2);
  }

  Future<void> _checkPledgeNo() async {
    final no = _pledgeNoCtrl.text.trim();
    if (no.isEmpty) return;
    final exists = await PledgeRepository.instance.pledgeNumberExists(no);
    if (mounted) setState(() => _pledgeNoError = exists);
  }

  // ── Step 4: form photo pick ──────────────────────────────────────────────────

  Future<void> _pickFormPhoto(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Form Page',
            toolbarColor: FlowColors.primary,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
            hideBottomControls: true,
          ),
          IOSUiSettings(title: 'Crop Form Page'),
        ],
      );
      if (cropped == null || !mounted) return;

      final docsDir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${docsDir.path}/pledge_photos');
      await destDir.create(recursive: true);

      final ts = DateTime.now().millisecondsSinceEpoch;
      final prefix = _pledgeNoCtrl.text.trim().isNotEmpty
          ? _pledgeNoCtrl.text.trim()
          : 'migrated';
      final pageNo = _formPhotos.length + 1;
      final dest =
          File('${destDir.path}/${prefix}_form_p${pageNo}_$ts.jpg');
      await File(cropped.path).copy(dest.path);

      if (mounted) setState(() => _formPhotos = [..._formPhotos, dest]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not pick photo: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Save (migrate) pledge ────────────────────────────────────────────────────

  Future<void> _savePledge() async {
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final db = await AppDatabase.instance.database;

      // ── Customer upsert ──────────────────────────────────────────────────────
      final customerData = _capturedCustomer;
      int? customerId = customerData?.existingCustomerId;
      final name = customerData?.name ?? '';

      if (name.isNotEmpty) {
        final photoPathsJson = jsonEncode(
            (customerData?.idProofPhotos ?? []).map((f) => f.path).toList());
        if (customerId != null) {
          await db.update(
            'customers',
            {
              'name': name,
              'phone': customerData?.phone ?? '',
              'address': customerData?.address ?? '',
              'district': customerData?.district,
              'state': customerData?.state,
              'pin_code': customerData?.pinCode,
              'id_proof_type': customerData?.idProofType ?? 'Aadhaar Card',
              'id_proof_number': customerData?.idNumber ?? '',
              'id_proof_photo_paths': photoPathsJson,
              'updated_at': now.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [customerId],
          );
        } else {
          customerId = await db.insert('customers', {
            'name': name,
            'phone': customerData?.phone ?? '',
            'address': customerData?.address ?? '',
            'district': customerData?.district,
            'state': customerData?.state,
            'pin_code': customerData?.pinCode,
            'id_proof_type': customerData?.idProofType ?? 'Aadhaar Card',
            'id_proof_number': customerData?.idNumber ?? '',
            'id_proof_photo_paths': photoPathsJson,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          });
        }
      }

      // ── Build pledge items ───────────────────────────────────────────────────
      final itemData = _capturedItems;
      final itemPhotoPathsList =
          (itemData?.photos ?? []).map((f) => f.path).toList();
      List<PledgeItemModel> pledgeItems = (itemData?.items ?? [])
          .where((e) => e.grossWeight > 0 || e.netWeight > 0)
          .map((e) => PledgeItemModel(
                pledgeId: 0,
                itemType: e.itemType,
                grossWeight: e.grossWeight,
                netWeight: e.netWeight,
                purity: e.purity ?? '',
                notes: e.notes,
                photoPaths: itemPhotoPathsList,
                createdAt: now.toIso8601String(),
              ))
          .toList();

      if (pledgeItems.isEmpty) {
        pledgeItems.add(PledgeItemModel(
          pledgeId: 0,
          itemType: 'other',
          grossWeight: _grossWeight,
          netWeight: _netWeight,
          createdAt: now.toIso8601String(),
        ));
      }

      // ── Build pledge model ───────────────────────────────────────────────────
      final pledge = PledgeModel(
        pledgeNumber: _pledgeNoCtrl.text.trim(),
        pledgeDate: _toIsoDate(_pledgeDateCtrl.text.trim()),
        loanAmount: _loanAmount,
        interestRate: 18.0,
        status: 'open',
        source: 'migrated',
        formPhotoPaths: _formPhotos.isNotEmpty
            ? _formPhotos.map((f) => f.path).toList()
            : null,
        createdAt: now.toIso8601String(),
        customerName: name,
        customerId: customerId,
        customerPhone: (customerData?.phone ?? '').isEmpty
            ? null
            : customerData?.phone,
        customerAddress: (customerData?.address ?? '').isEmpty
            ? null
            : customerData?.address,
        grossWeight: _grossWeight,
        netWeight: _netWeight,
        purity: '22K',
        goldRate: 0,
        pledgeRate: 0,
        actualItemValue: 0,
      );

      await PledgeRepository.instance.createMigratedPledge(pledge, pledgeItems);

      if (mounted) {
        setState(() {
          _savedPledgeNo = _pledgeNoCtrl.text.trim();
          _savedAmount = _loanAmount;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving pledge: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _reset() {
    setState(() {
      _step = 1;
      _pledgeNoCtrl.clear();
      _pledgeDateCtrl.text = _todayDisplay();
      _loanAmtCtrl.clear();
      _grossWeightCtrl.clear();
      _netWeightCtrl.clear();
      _pledgeNoError = false;
      _pledgeDateError = false;
      _capturedCustomer = null;
      _capturedItems = null;
      _formPhotos = [];
      _isSaving = false;
      _savedPledgeNo = null;
      _savedAmount = null;
    });
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(fontSize: 17)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK',
                style: TextStyle(fontSize: 18, color: FlowColors.primary)),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_savedPledgeNo != null) {
      return _SuccessScreen(
        pledgeNo: _savedPledgeNo!,
        amount: _savedAmount ?? 0,
        onAddAnother: _reset,
      );
    }
    return PopScope(
      canPop: _step == 1,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        backgroundColor: FlowColors.bg,
        appBar: AppBar(
          backgroundColor: FlowColors.primary,
          foregroundColor: FlowColors.goldRich,
          title: const Text('Load Existing Pledge'),
          leading: BackButton(onPressed: _back),
        ),
        body: Column(
          children: [
            _LEPStepIndicator(currentStep: _step),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  if (_step == 1) _buildStep1(),
                  if (_step == 2) _buildStep2(),
                  if (_step == 3) _buildStep3(),
                  if (_step == 4) _buildStep4(),
                  if (_step == 5) _buildStep5(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 1: Pledge Details ──────────────────────────────────────────────────

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SecHeader('Pledge Number'),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: TextField(
            controller: _pledgeNoCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              labelText: 'Pledge Number',
              prefixIcon: const Icon(Icons.tag),
              errorText: _pledgeNoError
                  ? 'This pledge number already exists'
                  : null,
            ),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() => _pledgeNoError = false),
            onEditingComplete: () {
              FocusScope.of(context).unfocus();
              _checkPledgeNo();
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: Text('Enter the exact number from the original pledge form.',
              style: TextStyle(color: Colors.black54, fontSize: 13)),
        ),
        const _SecHeader('Pledge Date'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: TextField(
                  controller: _pledgeDateCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_DateFormatter()],
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'Pledge Date (DD/MM/YYYY)',
                    prefixIcon: const Icon(Icons.calendar_today),
                    errorText:
                        _pledgeDateError ? 'Enter a valid date' : null,
                  ),
                  onChanged: (_) =>
                      setState(() => _pledgeDateError = false),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: IconButton(
                icon: const Icon(Icons.date_range,
                    color: FlowColors.primary, size: 28),
                tooltip: 'Pick date',
                onPressed: () async {
                  final dt = _parseDisplayDate(
                      _pledgeDateCtrl.text.trim());
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dt ?? DateTime.now(),
                    firstDate: DateTime(1990),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null && mounted) {
                    _pledgeDateCtrl.text =
                        '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                    setState(() => _pledgeDateError = false);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _SecHeader('Loan Amount'),
        _numberField('Loan Amount (₹)', _loanAmtCtrl,
            prefixText: '₹ ', indianFormat: true),
        const _SecHeader('Gold Weights'),
        _decimalField('Gross Weight (grams)', _grossWeightCtrl),
        _decimalField('Net Weight (grams)', _netWeightCtrl),
        const SizedBox(height: 8),
        _proceedBtn(_proceedFromStep1),
      ],
    );
  }

  // ─── Step 2: Customer Details ────────────────────────────────────────────────

  Widget _buildStep2() {
    void skip() {
      _capturedCustomer = _customerKey.currentState?.getData();
      setState(() => _step = 3);
    }

    void proceed() {
      final error = _customerKey.currentState?.validate();
      if (error != null) {
        _showError(error);
        return;
      }
      _capturedCustomer = _customerKey.currentState?.getData();
      setState(() => _step = 3);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SharedCustomerDetailsStep(
          key: _customerKey,
          initialData: _capturedCustomer,
          pledgeNumber: _pledgeNoCtrl.text.trim(),
        ),
        const SizedBox(height: 20),
        _skipProceedRow(skip, proceed),
      ],
    );
  }

  // ─── Step 3: Item Details ────────────────────────────────────────────────────

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SharedItemDetailsStep(
          key: _itemsKey,
          grossWeight: _grossWeight,
          netWeight: _netWeight,
          initialData: _capturedItems,
          pledgeNumber: _pledgeNoCtrl.text.trim(),
        ),
        const SizedBox(height: 20),
        _skipProceedRow(
          () {
            _capturedItems = _itemsKey.currentState?.getData();
            setState(() => _step = 4);
          },
          () {
            final data = _itemsKey.currentState?.getData();
            if (data != null && data.items.isNotEmpty) {
              final totalGross =
                  data.items.fold(0.0, (s, e) => s + e.grossWeight);
              final totalNet =
                  data.items.fold(0.0, (s, e) => s + e.netWeight);
              if (_grossWeight > 0 &&
                  (_grossWeight - totalGross).abs() > 0.001) {
                _showError(
                    'Gross weight total (${totalGross.toStringAsFixed(2)}g) must match ${_grossWeight.toStringAsFixed(2)}g.');
                return;
              }
              if (_netWeight > 0 &&
                  (_netWeight - totalNet).abs() > 0.001) {
                _showError(
                    'Net weight total (${totalNet.toStringAsFixed(2)}g) must match ${_netWeight.toStringAsFixed(2)}g.');
                return;
              }
            }
            _capturedItems = data;
            setState(() => _step = 4);
          },
        ),
      ],
    );
  }

  // ─── Step 4: Physical Form Scan ──────────────────────────────────────────────

  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SecHeader('Physical Form Scan'),
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: FlowColors.accent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: FlowColors.primaryLight),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: FlowColors.primary, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Scan or photograph each page of the original pledge form. You can add multiple pages.',
                  style: TextStyle(fontSize: 14, color: FlowColors.darkText),
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickFormPhoto(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('Scan Page'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FlowColors.primary,
                  side:
                      const BorderSide(color: FlowColors.primary, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickFormPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('Gallery'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FlowColors.primary,
                  side:
                      const BorderSide(color: FlowColors.primary, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_formPhotos.isEmpty)
          Container(
            height: 60,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEEEEEE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('No pages scanned yet',
                style: TextStyle(color: Colors.black54)),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_formPhotos.length} page(s) scanned',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: FlowColors.primary)),
              const SizedBox(height: 8),
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _formPhotos.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: 10),
                  itemBuilder: (ctx, i) => Stack(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  _PhotoView(file: _formPhotos[i])),
                        ),
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(_formPhotos[i],
                                  height: 86,
                                  width: 86,
                                  fit: BoxFit.cover),
                            ),
                            const SizedBox(height: 2),
                            Text('Pg ${i + 1}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54)),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _formPhotos =
                                List.from(_formPhotos)..removeAt(i);
                          }),
                          child: Container(
                            decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 24),
        _skipProceedRow(
          () => setState(() => _step = 5),
          () => setState(() => _step = 5),
        ),
      ],
    );
  }

  // ─── Step 5: Review & Confirm ────────────────────────────────────────────────

  Widget _buildStep5() {
    final customer = _capturedCustomer;
    final itemData = _capturedItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SecHeader('Review & Confirm'),

        // Pledge Details
        _summarySection(
          title: 'PLEDGE DETAILS',
          onEdit: () => setState(() => _step = 1),
          children: [
            _summaryRow('Pledge No.', '#${_pledgeNoCtrl.text}',
                highlight: true),
            _summaryRow('Pledge Date', _pledgeDateCtrl.text),
            _summaryRow('Loan Amount', money(_loanAmount), highlight: true),
            _summaryRow(
                'Gross Weight', '${_grossWeight.toStringAsFixed(2)} g'),
            _summaryRow(
                'Net Weight', '${_netWeight.toStringAsFixed(2)} g'),
          ],
        ),

        // Customer
        _summarySection(
          title: 'CUSTOMER',
          onEdit: () => setState(() => _step = 2),
          children: customer != null && customer.name.isNotEmpty
              ? [
                  if (customer.phone.isNotEmpty)
                    _summaryRow('Phone', customer.phone),
                  _summaryRow('Name', customer.name),
                  if (customer.address.isNotEmpty ||
                      (customer.district?.isNotEmpty ?? false))
                    _summaryRow(
                      'Address',
                      formatCustomerAddress(
                        address: customer.address.isNotEmpty
                            ? customer.address
                            : null,
                        district: customer.district,
                        state: customer.state,
                        pinCode: customer.pinCode,
                      ),
                    ),
                  if (customer.idNumber.isNotEmpty)
                    _summaryRow(customer.idProofType, customer.idNumber),
                ]
              : [
                  const Text('No customer details entered.',
                      style: TextStyle(color: Colors.black45, fontSize: 15)),
                ],
        ),

        // Items
        _summarySection(
          title: 'ITEMS',
          onEdit: () => setState(() => _step = 3),
          children: itemData != null && itemData.items.isNotEmpty
              ? [
                  ...List.generate(itemData.items.length, (i) {
                    final it = itemData.items[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (i > 0)
                          const Divider(height: 16, thickness: 0.8),
                        Text('Item ${i + 1}: ${it.itemType}',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        _summaryRow('  Gross',
                            '${it.grossWeight.toStringAsFixed(2)} g'),
                        _summaryRow('  Net',
                            '${it.netWeight.toStringAsFixed(2)} g'),
                        if (it.notes != null && it.notes!.isNotEmpty)
                          _summaryRow('  Notes', it.notes!),
                      ],
                    );
                  }),
                  if (itemData.photos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          '${itemData.photos.length} item photo(s) attached.',
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 14)),
                    ),
                ]
              : [
                  const Text('No items detailed.',
                      style: TextStyle(color: Colors.black45, fontSize: 15)),
                ],
        ),

        // Form scan
        _summarySection(
          title: 'FORM SCAN',
          onEdit: () => setState(() => _step = 4),
          children: _formPhotos.isNotEmpty
              ? [
                  Text('${_formPhotos.length} page(s) scanned.',
                      style: const TextStyle(fontSize: 15)),
                ]
              : [
                  const Text('No form photos attached.',
                      style: TextStyle(color: Colors.black45, fontSize: 15)),
                ],
        ),

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
                        strokeWidth: 2.5, color: FlowColors.textOnNavyLarge))
                : const Icon(Icons.save_alt, size: 24),
            label: Text(
                _isSaving ? 'SAVING…' : 'SAVE MIGRATED PLEDGE',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: FlowColors.primary,
              foregroundColor: FlowColors.textOnNavyLarge,
              side: const BorderSide(color: FlowColors.borderOnNavy, width: 0.8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ─── Summary helpers ──────────────────────────────────────────────────────────

  Widget _summarySection({
    required String title,
    required VoidCallback onEdit,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FlowColors.primaryLight, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: FlowColors.primary,
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12)),
              border: Border(
                  bottom: BorderSide(
                      color: FlowColors.borderOnNavy, width: 0.8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: FlowColors.textOnNavyLarge,
                        letterSpacing: 0.5)),
                GestureDetector(
                  onTap: onEdit,
                  child: const Row(
                    children: [
                      Icon(Icons.edit_note,
                          size: 16, color: FlowColors.textOnNavyLarge),
                      SizedBox(width: 4),
                      Text('EDIT',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: FlowColors.textOnNavyLarge)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 126,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        highlight ? FontWeight.bold : FontWeight.w600,
                    color: highlight
                        ? FlowColors.primary
                        : FlowColors.darkText)),
          ),
        ],
      ),
    );
  }

  // ─── Field helpers ────────────────────────────────────────────────────────────

  Widget _decimalField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
        ],
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _numberField(
    String label,
    TextEditingController ctrl, {
    String? prefixText,
    bool indianFormat = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: indianFormat
            ? [IndianNumberFormatter()]
            : [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 18),
        decoration:
            InputDecoration(labelText: label, prefixText: prefixText),
      ),
    );
  }

  Widget _proceedBtn(VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_forward),
        label: const Text('PROCEED',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: FlowColors.primary,
          foregroundColor: FlowColors.textOnNavyLarge,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _skipProceedRow(VoidCallback onSkip, VoidCallback onProceed) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onSkip,
            style: OutlinedButton.styleFrom(
              foregroundColor: FlowColors.primary,
              side: const BorderSide(
                  color: FlowColors.primary, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('SKIP', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _proceedBtn(onProceed),
        ),
      ],
    );
  }
}

// ─── Step Indicator ───────────────────────────────────────────────────────────

class _LEPStepIndicator extends StatelessWidget {
  const _LEPStepIndicator({required this.currentStep});
  final int currentStep;

  static const _labels = [
    'Details', 'Customer', 'Items', 'Form Scan', 'Review'
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              for (int s = 1; s <= 5; s++) ...[
                _bubble(s),
                if (s < 5)
                  Expanded(
                    child: Container(
                      height: 2.5,
                      color: currentStep > s
                          ? FlowColors.primary
                          : Colors.black12,
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Step $currentStep of 5 — ${_labels[currentStep - 1]}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: FlowColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(int n) {
    final done = n < currentStep;
    final current = n == currentStep;
    return CircleAvatar(
      radius: 13,
      backgroundColor:
          (done || current) ? FlowColors.primary : Colors.black12,
      child: done
          ? const Icon(Icons.check, color: FlowColors.goldRich, size: 14)
          : Text(
              '$n',
              style: TextStyle(
                color: current ? FlowColors.textOnNavySmall : Colors.black38,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
    );
  }
}

// ─── Private helpers ──────────────────────────────────────────────────────────

class _SecHeader extends StatelessWidget {
  const _SecHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Text(title,
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: FlowColors.primary)),
    );
  }
}

class _PhotoView extends StatelessWidget {
  const _PhotoView({required this.file});
  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Form Page'),
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

// ─── Success screen ───────────────────────────────────────────────────────────

class _SuccessScreen extends StatelessWidget {
  const _SuccessScreen({
    required this.pledgeNo,
    required this.amount,
    required this.onAddAnother,
  });

  final String pledgeNo;
  final double amount;
  final VoidCallback onAddAnother;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Pledge Loaded'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle,
                  color: FlowColors.green, size: 80),
              const SizedBox(height: 20),
              const Text('Pledge Migrated!',
                  style: TextStyle(
                      fontSize: 26,
                      color: FlowColors.green,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: FlowColors.greenLight),
                ),
                child: Column(
                  children: [
                    _row('Pledge Number', '#$pledgeNo'),
                    const SizedBox(height: 6),
                    _row('Loan Amount', money(amount)),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onAddAnother,
                  icon: const Icon(Icons.add_circle_outline,
                      color: FlowColors.primary),
                  label: const Text('ADD ANOTHER',
                      style: TextStyle(
                          fontSize: 16, color: FlowColors.primary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: FlowColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  icon: const Icon(Icons.home),
                  label: const Text('BACK TO HOME',
                      style: TextStyle(fontSize: 17)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlowColors.primary,
                    foregroundColor: FlowColors.textOnNavyLarge,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 16, color: Colors.black54)),
        Text(value,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
