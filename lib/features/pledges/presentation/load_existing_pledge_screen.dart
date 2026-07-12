import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/restricted_action.dart';
import '../../../shared/widgets/shared_customer_details_step.dart';
import '../../../shared/widgets/shared_item_details_step.dart';
import '../../customers/data/customer_repository.dart';
import '../data/pledge_item_model.dart';
import '../data/pledge_model.dart';
import '../../../core/services/photo_sync_repository.dart';
import '../data/pledge_repository.dart';
import 'open_pledge_screen.dart';

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

// ─── Screen ───────────────────────────────────────────────────────────────────

class LoadExistingPledgeScreen extends StatefulWidget {
  const LoadExistingPledgeScreen({
    super.key,
    this.prefilledPledgeId,
    this.prefilledAmount,
    this.prefilledOpenDate,
    this.openDateEditable = true,
    this.closeDate,
    this.closeDateEditable = true,
    this.sourceContext,
    this.contextDate,
    this.editMode = false,
    this.existingPledge,
    this.existingItems,
    this.existingCustomerRow,
    this.editReason,
  });

  /// Pre-fill values (calculator / record-closure flows).
  final String? prefilledPledgeId;
  final double? prefilledAmount;
  final DateTime? prefilledOpenDate;
  final bool openDateEditable;

  /// Closure date shown as a banner; passed on to the Close/Renew flow as a
  /// non-editable context date when [closeDateEditable] is false.
  final DateTime? closeDate;
  final bool closeDateEditable;

  /// 'calculator' / 'daily_accounts' switches step 5 to MIGRATE & CLOSE /
  /// MIGRATE & RENEW. Null keeps the normal single MIGRATE button.
  final String? sourceContext;
  final DateTime? contextDate;

  // ── Edit mode ────────────────────────────────────────────────────────────────
  final bool editMode;
  final PledgeModel? existingPledge;
  final List<PledgeItemModel>? existingItems;
  final Map<String, dynamic>? existingCustomerRow;
  final String? editReason;

  @override
  State<LoadExistingPledgeScreen> createState() =>
      _LoadExistingPledgeScreenState();
}

class _LoadExistingPledgeScreenState
    extends State<LoadExistingPledgeScreen> {
  int _step = 1;
  final _imagePicker = ImagePicker();
  final _scrollController = ScrollController();

  // ── Step 1 ──────────────────────────────────────────────────────────────────
  final _pledgeNoCtrl = TextEditingController();
  final _pledgeDateCtrl = TextEditingController();
  final _loanAmtCtrl = TextEditingController();
  final _grossWeightCtrl = TextEditingController();
  final _netWeightCtrl = TextEditingController();
  final _loanAmtFocus = FocusNode();
  final _grossFocus = FocusNode();
  final _netFocus = FocusNode();
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

  // ── App start date (ISO) — pledge date must be strictly before this ──────────
  String? _appStartDate;

  // ── Computed getters ─────────────────────────────────────────────────────────
  double get _grossWeight =>
      double.tryParse(_grossWeightCtrl.text) ?? 0;
  double get _netWeight => double.tryParse(_netWeightCtrl.text) ?? 0;
  double get _loanAmount =>
      double.tryParse(_loanAmtCtrl.text.replaceAll(',', '')) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadAppStartDate();
    if (widget.editMode) {
      _prefillForEdit();
    } else {
      final openDate = widget.prefilledOpenDate;
      _pledgeDateCtrl.text = openDate != null ? formatDmy(openDate) : '';
      if (widget.prefilledPledgeId != null) {
        _pledgeNoCtrl.text = widget.prefilledPledgeId!;
      }
      if (widget.prefilledAmount != null && widget.prefilledAmount! > 0) {
        _loanAmtCtrl.text =
            formatIndian(widget.prefilledAmount!.round().toString());
      }
    }
    _grossWeightCtrl.addListener(() => setState(() {}));
    _netWeightCtrl.addListener(() => setState(() {}));
    _loanAmtCtrl.addListener(() => setState(() {}));
  }

  Future<void> _loadAppStartDate() async {
    final date = await AppSettingsRepository().getString('app_use_start_date');
    if (mounted) setState(() => _appStartDate = date);
  }

  Future<void> _prefillForEdit() async {
    final p = widget.existingPledge;
    if (p == null) return;

    _pledgeNoCtrl.text = p.pledgeNumber;
    final dt = DateTime.tryParse(p.pledgeDate);
    _pledgeDateCtrl.text = dt != null ? formatDmy(dt) : p.pledgeDate;
    _loanAmtCtrl.text = formatIndian(p.loanAmount.round().toString());
    _grossWeightCtrl.text = p.grossWeight.toStringAsFixed(2);
    _netWeightCtrl.text = p.netWeight.toStringAsFixed(2);

    // Pre-fill form photos from photo_sync_log
    final formEntries = p.id != null
        ? await PhotoSyncRepository.instance
            .getByPledge(p.id!, PhotoType.document)
        : <PhotoSyncEntry>[];
    _formPhotos = formEntries.map((e) => File(e.localPath)).toList();

    // Pre-fill customer
    final row = widget.existingCustomerRow;
    if (row != null) {
      final customerId = row['id'] as int?;
      List<File> idPhotos = [];
      if (customerId != null) {
        final syncEntries =
            await PhotoSyncRepository.instance.getByCustomer(customerId);
        idPhotos = syncEntries.map((e) => File(e.localPath)).toList();
      }
      _capturedCustomer = CustomerDetailsData(
        phone: (row['phone'] as String?) ?? '',
        name: (row['name'] as String?) ?? '',
        address: (row['address'] as String?) ?? '',
        idProofType: (row['id_proof_type'] as String?) ?? 'None',
        idNumber: (row['id_proof_number'] as String?) ?? '',
        idProofPhotos: idPhotos,
        existingCustomerId: customerId,
        pinCode: row['pin_code'] as String?,
        district: row['district'] as String?,
        state: row['state'] as String?,
      );
    }

    // Pre-fill items + gold photos from photo_sync_log
    final goldEntries = p.id != null
        ? await PhotoSyncRepository.instance.getByPledge(p.id!, PhotoType.gold)
        : <PhotoSyncEntry>[];
    final goldPhotos = goldEntries.map((e) => File(e.localPath)).toList();

    final items = widget.existingItems ?? [];
    _capturedItems = ItemDetailsData(
      items: items
          .map((it) => ItemEntryData(
                itemType: it.itemType,
                grossWeight: it.grossWeight,
                netWeight: it.netWeight,
                quantity: it.quantity,
                purity: it.purity.isNotEmpty ? it.purity : null,
                notes: it.notes,
              ))
          .toList(),
      photos: goldPhotos,
    );

    // Start on step 5
    if (mounted) _goToStep(5);
  }

  @override
  void dispose() {
    _pledgeNoCtrl.dispose();
    _pledgeDateCtrl.dispose();
    _loanAmtCtrl.dispose();
    _grossWeightCtrl.dispose();
    _netWeightCtrl.dispose();
    _loanAmtFocus.dispose();
    _grossFocus.dispose();
    _netFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  /// Switches to [step] and resets the shared ListView's scroll position to
  /// the top, since every step is rendered inside the same scrollable and
  /// otherwise inherits the previous step's scroll offset.
  void _goToStep(int step) {
    setState(() => _step = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _back() {
    if (widget.editMode) {
      if (_step > 1 && _step != 5) {
        _goToStep(_step - 1);
      } else {
        Navigator.pop(context);
      }
    } else {
      if (_step == 5) {
        _goToStep(3);
      } else if (_step > 1) {
        _goToStep(_step - 1);
      } else {
        Navigator.pop(context);
      }
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
    final parsedDate = _parseDisplayDate(dateText);
    if (parsedDate == null) {
      setState(() => _pledgeDateError = true);
      _showError('Enter a valid pledge date (DD/MM/YYYY).');
      return;
    }

    // Pledge date must be strictly before the app start date.
    final appStart = _appStartDate != null
        ? DateTime.tryParse(_appStartDate!)
        : null;
    if (appStart != null && !parsedDate.isBefore(appStart)) {
      setState(() => _pledgeDateError = true);
      final d = '${appStart.day.toString().padLeft(2, '0')}/'
          '${appStart.month.toString().padLeft(2, '0')}/${appStart.year}';
      _showError(
        'Pledge date must be before $d. Loans created on or after this date '
        'should be added via New Loan, or via Cash Book\'s backdated entry '
        'options if a specific day was missed.',
      );
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

    // Duplicate pledge number check.
    // For normal creation: always check.
    // For migrated-pledge edit: check only when the number was changed
    //   (unchanged number references itself — not a conflict).
    // For new-loan edit: skip (field is locked, number can't change).
    final isMigratedEdit =
        widget.editMode && widget.existingPledge?.source == 'migrated';
    if (!widget.editMode ||
        (isMigratedEdit &&
            no != (widget.existingPledge?.pledgeNumber ?? ''))) {
      await _checkPledgeNo();
      if (!mounted) return;
      if (_pledgeNoError) {
        _showError(
            'Pledge number $no already exists. Please use a different number.');
        return;
      }
    }

    _goToStep(2);
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

  /// Builds and persists the migrated (open) pledge. Returns its new id, or
  /// null on failure. Leaves [_isSaving] true on success so the caller can
  /// chain navigation; resets it on error.
  Future<int?> _persistPledge() async {
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();

      // ── Customer ───────────────────────────────────────────────────────────────
      final customerData = _capturedCustomer;
      int? customerId = customerData?.existingCustomerId;
      final name = customerData?.name ?? '';

      if (name.isNotEmpty && customerData != null) {
        if (customerId != null) {
          await CustomerRepository.instance
              .updateCustomer(customerId, customerData);
        } else {
          customerId =
              await CustomerRepository.instance.upsertCustomer(customerData);
        }
      }

      // ── Customer snapshot (denormalised onto the pledge) ───────────────────────
      final customerSnapshot = customerData != null && name.isNotEmpty
          ? <String, dynamic>{
              'name': customerData.name,
              'phone': customerData.phone,
              'address': customerData.address,
              'district': customerData.district,
              'state': customerData.state,
              'pin_code': customerData.pinCode,
              'id_proof_type': customerData.idProofType,
              'id_proof_number': customerData.idNumber,
            }
          : null;

      // ── Gold photos (item photos, if any) ──────────────────────────────────────
      final itemData = _capturedItems;
      final goldPhotoPaths =
          (itemData?.photos ?? []).map((f) => f.path).toList();

      // ── Build pledge items ───────────────────────────────────────────────────
      List<PledgeItemModel> pledgeItems = (itemData?.items ?? [])
          .where((e) => e.grossWeight > 0 || e.netWeight > 0)
          .map((e) => PledgeItemModel(
                pledgeId: 0,
                itemType: e.itemType,
                grossWeight: e.grossWeight,
                netWeight: e.netWeight,
                quantity: e.quantity,
                purity: e.purity ?? '',
                notes: e.notes,
                createdAt: now.toIso8601String(),
              ))
          .toList();

      if (pledgeItems.isEmpty) {
        pledgeItems.add(PledgeItemModel(
          pledgeId: 0,
          itemType: 'Other',
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
        goldPhotoPaths: goldPhotoPaths.isEmpty ? null : goldPhotoPaths,
        createdAt: now.toIso8601String(),
        customerId: customerId,
        customerSnapshot: customerSnapshot,
        grossWeight: _grossWeight,
        netWeight: _netWeight,
        goldRate: 0,
        pledgeRate: 0,
        actualItemValue: 0,
      );

      final newId = await PledgeRepository.instance
          .createMigratedPledge(pledge, pledgeItems);
      return newId;
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving pledge: $e'),
              backgroundColor: Colors.red),
        );
      }
      return null;
    }
  }

  /// Normal flow: save and show the success screen.
  Future<void> _savePledge() async {
    final id = await _persistPledge();
    if (id == null || !mounted) return;
    setState(() {
      _savedPledgeNo = _pledgeNoCtrl.text.trim();
      _savedAmount = _loanAmount;
      _isSaving = false;
    });
  }

  /// MIGRATE & CLOSE: save as open, then go straight to the Close Pledge screen
  /// with the close date as a non-editable context date.
  Future<void> _migrateAndClose() async {
    final id = await _persistPledge();
    if (id == null || !mounted) return;
    final pledge = await PledgeRepository.instance.getPledgeById(id);
    if (pledge == null || !mounted) return;
    setState(() => _isSaving = false);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClosePledgeScreen(
            pledge: pledge, contextDate: widget.closeDate),
      ),
    );
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// MIGRATE & RENEW: save as open, then go to the Renew Selection screen with
  /// the close date as a non-editable context date.
  Future<void> _migrateAndRenew() async {
    final id = await _persistPledge();
    if (id == null || !mounted) return;
    final pledge = await PledgeRepository.instance.getPledgeById(id);
    if (pledge == null || !mounted) return;
    setState(() => _isSaving = false);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RenewSelectionScreen(
            pledge: pledge, contextDate: widget.closeDate),
      ),
    );
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _reset() {
    setState(() {
      _step = 1;
      _pledgeNoCtrl.clear();
      _pledgeDateCtrl.text = '';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
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
      if (widget.editMode) {
        return _EditSuccessScreen(pledgeNo: _savedPledgeNo!);
      }
      return _SuccessScreen(
        pledgeNo: _savedPledgeNo!,
        amount: _savedAmount ?? 0,
        onAddAnother: _reset,
      );
    }
    final appBarTitle = widget.editMode
        ? 'Edit Pledge #${widget.existingPledge?.pledgeNumber ?? ''}'
        : 'Add Existing Loan';
    return PopScope(
      canPop: widget.editMode ? _step == 5 : _step == 1,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          if (widget.editMode) {
            if (_step > 1 && _step != 5) _goToStep(_step - 1);
          } else {
            _goToStep(_step - 1);
          }
        }
      },
      child: Scaffold(
        backgroundColor: FlowColors.bg,
        appBar: AppBar(
          backgroundColor: FlowColors.primary,
          foregroundColor: FlowColors.goldRich,
          title: Text(appBarTitle),
          leading: BackButton(onPressed: _back),
        ),
        body: Column(
          children: [
            _LEPStepIndicator(currentStep: _step),
            if (widget.closeDate != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ContextDateBanner(
                    label: 'Close Date', date: widget.closeDate!),
              ),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40)
                    .withNavBarInset(context),
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
    // Migrated pledges in edit mode: pledge number and date are fully editable
    // (staff-entered historical facts that may need correction).
    // New Loan pledges in edit mode: pledge number stays locked (system-sequenced).
    // Exception: renewal-child pledges lock all Step 1 fields regardless of source
    // to prevent accounting issues in payments/stock register.
    final isMigratedEdit =
        widget.editMode && widget.existingPledge?.source == 'migrated';
    final readOnly = (widget.editMode && !isMigratedEdit) ||
        (widget.editMode &&
            widget.existingPledge?.renewalParentId != null);
    final dateReadOnly =
        !widget.openDateEditable || (widget.editMode && !isMigratedEdit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (readOnly && widget.existingPledge?.renewalParentId != null)
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
                Icon(Icons.info_outline, color: FlowColors.orange, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Step 1 details are read-only — this pledge was created from a renewal or loan increase and its details cannot be changed.',
                    style: TextStyle(fontSize: 13, color: FlowColors.orange),
                  ),
                ),
              ],
            ),
          ),
        const _SecHeader('Pledge Number'),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: TextField(
            controller: _pledgeNoCtrl,
            readOnly: readOnly,
            keyboardType: TextInputType.number,
            inputFormatters: readOnly
                ? []
                : [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              labelText: 'Pledge Number',
              prefixIcon: Icon(readOnly ? Icons.lock : Icons.tag),
              errorText: _pledgeNoError
                  ? 'This pledge number already exists'
                  : null,
            ),
            textInputAction: TextInputAction.next,
            onChanged: readOnly
                ? null
                : (_) => setState(() => _pledgeNoError = false),
            onEditingComplete: readOnly ? null : _checkPledgeNo,
            onSubmitted: readOnly
                ? null
                : (_) => FocusScope.of(context).nextFocus(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(
            readOnly
                ? 'Pledge number cannot be changed.'
                : 'Enter the exact number from the original pledge form.',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
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
                  readOnly: dateReadOnly,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [_DateFormatter()],
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'Pledge Date (DD/MM/YYYY)',
                    prefixIcon: Icon(dateReadOnly
                        ? Icons.lock
                        : Icons.calendar_today),
                    errorText:
                        _pledgeDateError ? 'Enter a valid date' : null,
                  ),
                  onChanged: (_) =>
                      setState(() => _pledgeDateError = false),
                  onSubmitted: (_) => _loanAmtFocus.requestFocus(),
                ),
              ),
            ),
            if (widget.openDateEditable) ...[
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
                    // lastDate is the day before app_use_start_date so the
                    // picker only allows strictly-before dates.
                    final DateTime pickerLastDate;
                    if (_appStartDate != null) {
                      final start = DateTime.parse(_appStartDate!);
                      pickerLastDate = start.subtract(const Duration(days: 1));
                    } else {
                      pickerLastDate = DateTime.now();
                    }
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: (dt != null && dt.isBefore(pickerLastDate))
                          ? dt
                          : pickerLastDate,
                      firstDate: DateTime(1990),
                      lastDate: pickerLastDate,
                    );
                    if (picked != null && mounted) {
                      _pledgeDateCtrl.text =
                          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                      setState(() => _pledgeDateError = false);
                      // After picking a date, jump to Loan Amount (not Pledge
                      // ID) and open the keyboard.
                      _loanAmtFocus.requestFocus();
                    }
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        const _SecHeader('Loan Amount'),
        _numberField('Loan Amount (₹)', _loanAmtCtrl,
            prefixText: '₹ ',
            indianFormat: true,
            readOnly: readOnly,
            focusNode: _loanAmtFocus,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _grossFocus.requestFocus()),
        if (readOnly && widget.existingPledge?.renewalParentId != null)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'Loan amount cannot be changed.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        const _SecHeader('Gold Weights'),
        _decimalField('Gross Weight (grams)', _grossWeightCtrl,
            focusNode: _grossFocus,
            readOnly: readOnly,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _netFocus.requestFocus()),
        _decimalField('Net Weight (grams)', _netWeightCtrl,
            focusNode: _netFocus,
            readOnly: readOnly,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus()),
        const SizedBox(height: 8),
        _proceedBtn(_proceedFromStep1),
      ],
    );
  }

  // ─── Step 2: Customer Details ────────────────────────────────────────────────

  Widget _buildStep2() {
    void skip() {
      _capturedCustomer = _customerKey.currentState?.getData();
      _goToStep(3);
    }

    void proceed() {
      final error = _customerKey.currentState?.validate();
      if (error != null) {
        _showError(error);
        return;
      }
      _capturedCustomer = _customerKey.currentState?.getData();
      _goToStep(3);
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
            _goToStep(5);
          },
          () {
            final validationError = _itemsKey.currentState?.validate();
            if (validationError != null) {
              _showError(validationError);
              return;
            }
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
            _goToStep(5);
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
          () => _goToStep(5),
          () => _goToStep(5),
        ),
      ],
    );
  }

  // ─── Step 5: Review & Confirm ────────────────────────────────────────────────

  Widget _buildStep5() {
    if (widget.editMode) return _buildEditStep5();

    final customer = _capturedCustomer;
    final itemData = _capturedItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SecHeader('Review & Confirm'),

        // Pledge Details
        _summarySection(
          title: 'PLEDGE DETAILS',
          onEdit: () => _goToStep(1),
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
          onEdit: () => _goToStep(2),
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
          onEdit: () => _goToStep(3),
          children: itemData != null && itemData.items.isNotEmpty
              ? [
                  ...List.generate(itemData.items.length, (i) {
                    final it = itemData.items[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (i > 0)
                          const Divider(height: 16, thickness: 0.8),
                        Text('Item List ${i + 1}',
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600)),
                        _summaryRow('  Item Types', it.itemType),
                        _summaryRow('  Total Quantity', '${it.quantity}'),
                        _summaryRow('  Gross',
                            '${it.grossWeight.toStringAsFixed(2)} g'),
                        _summaryRow('  Net',
                            '${it.netWeight.toStringAsFixed(2)} g'),
                        if (it.purity != null && it.purity!.isNotEmpty)
                          _summaryRow('  Purity', it.purity!),
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
          onEdit: () => _goToStep(4),
          editLabel: _formPhotos.isEmpty ? 'ADD FORMS' : 'EDIT',
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
        ..._buildStep5Actions(),
        const SizedBox(height: 20),
      ],
    );
  }

  // ─── Edit Step 5 ─────────────────────────────────────────────────────────────

  Widget _buildEditStep5() {
    final p = widget.existingPledge!;
    final customer = _capturedCustomer;
    final itemData = _capturedItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Edit mode banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: CMBColors.warningOrange.withValues(alpha: 0.12),
            border: Border.all(color: CMBColors.warningOrange, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.edit_note,
                  color: CMBColors.warningOrange, size: 20),
              const SizedBox(width: 10),
              Text(
                'Editing Pledge #${p.pledgeNumber}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: CMBColors.warningOrange),
              ),
            ],
          ),
        ),

        // Read-only edit reason
        _summarySection(
          title: 'EDIT REASON',
          onEdit: () {},
          hideEditButton: true,
          children: [
            Text(widget.editReason ?? '',
                style: const TextStyle(
                    fontSize: 15, color: FlowColors.darkText)),
          ],
        ),

        // Pledge Details (no edit button for pledge no & date)
        _summarySection(
          title: 'PLEDGE DETAILS',
          onEdit: () => _goToStep(1),
          children: [
            _summaryRow('Pledge No.', '#${p.pledgeNumber}',
                highlight: true),
            _summaryRow('Date', _pledgeDateCtrl.text),
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
          onEdit: () => _goToStep(2),
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
                      style: TextStyle(
                          color: Colors.black45, fontSize: 15)),
                ],
        ),

        // Items
        _summarySection(
          title: 'ITEMS',
          onEdit: () => _goToStep(3),
          children: itemData != null && itemData.items.isNotEmpty
              ? [
                  ...List.generate(itemData.items.length, (i) {
                    final it = itemData.items[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (i > 0)
                          const Divider(height: 16, thickness: 0.8),
                        Text('Item List ${i + 1}',
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600)),
                        _summaryRow('  Item Types', it.itemType),
                        _summaryRow('  Total Quantity', '${it.quantity}'),
                        _summaryRow('  Gross',
                            '${it.grossWeight.toStringAsFixed(2)} g'),
                        _summaryRow('  Net',
                            '${it.netWeight.toStringAsFixed(2)} g'),
                        if (it.purity != null && it.purity!.isNotEmpty)
                          _summaryRow('  Purity', it.purity!),
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
                      style: TextStyle(
                          color: Colors.black45, fontSize: 15)),
                ],
        ),

        // Form Scan
        _summarySection(
          title: 'FORM SCAN',
          onEdit: () => _goToStep(4),
          editLabel: _formPhotos.isEmpty ? 'ADD FORMS' : 'EDIT',
          children: _formPhotos.isNotEmpty
              ? [
                  Text('${_formPhotos.length} page(s) scanned.',
                      style: const TextStyle(fontSize: 15)),
                ]
              : [
                  const Text('No form photos attached.',
                      style: TextStyle(
                          color: Colors.black45, fontSize: 15)),
                ],
        ),

        const SizedBox(height: 24),
        RestrictedAction(
          child: SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _updateMigratedPledge,
            icon: _isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: FlowColors.textOnNavyLarge))
                : const Icon(Icons.save, size: 24),
            label: Text(
                _isSaving ? 'SAVING…' : 'SAVE CHANGES',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: CMBColors.warningOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Future<void> _updateMigratedPledge() async {
    final existingPledge = widget.existingPledge!;
    if (_loanAmount <= 0) {
      _showError('Loan amount is invalid.');
      return;
    }

    // Validate pledge date if it was changed.
    final newDateIso = _toIsoDate(_pledgeDateCtrl.text.trim());
    final newParsed = _parseDisplayDate(_pledgeDateCtrl.text.trim());
    final appStart = _appStartDate != null
        ? DateTime.tryParse(_appStartDate!)
        : null;
    if (newParsed != null && appStart != null && !newParsed.isBefore(appStart)) {
      final d = '${appStart.day.toString().padLeft(2, '0')}/'
          '${appStart.month.toString().padLeft(2, '0')}/${appStart.year}';
      _showError(
        'Pledge date must be before $d. Loans created on or after this date '
        'should be added via New Loan, or via Cash Book\'s backdated entry '
        'options if a specific day was missed.',
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();

      // Customer upsert
      final customerData = _capturedCustomer;
      int? customerId = customerData?.existingCustomerId;
      final name = customerData?.name ?? '';
      if (name.isNotEmpty && customerData != null) {
        if (customerId != null) {
          await CustomerRepository.instance
              .updateCustomer(customerId, customerData);
        } else {
          customerId =
              await CustomerRepository.instance.upsertCustomer(customerData);
        }
      }

      final customerSnapshot = customerData != null && name.isNotEmpty
          ? <String, dynamic>{
              'name': customerData.name,
              'phone': customerData.phone,
              'address': customerData.address,
              'district': customerData.district,
              'state': customerData.state,
              'pin_code': customerData.pinCode,
              'id_proof_type': customerData.idProofType,
              'id_proof_number': customerData.idNumber,
            }
          : existingPledge.customerSnapshot;

      final itemData = _capturedItems;
      final goldPhotoPaths =
          (itemData?.photos ?? []).map((f) => f.path).toList();
      final formPhotoPaths = _formPhotos.map((f) => f.path).toList();

      List<PledgeItemModel> pledgeItems = (itemData?.items ?? [])
          .where((e) => e.grossWeight > 0 || e.netWeight > 0)
          .map((e) => PledgeItemModel(
                pledgeId: existingPledge.id!,
                itemType: e.itemType,
                grossWeight: e.grossWeight,
                netWeight: e.netWeight,
                quantity: e.quantity,
                purity: e.purity ?? '',
                notes: e.notes,
                createdAt: now.toIso8601String(),
              ))
          .toList();

      if (pledgeItems.isEmpty) {
        pledgeItems.add(PledgeItemModel(
          pledgeId: existingPledge.id!,
          itemType: 'Other',
          grossWeight: _grossWeight,
          netWeight: _netWeight,
          createdAt: now.toIso8601String(),
        ));
      }

      final updatedPledge = PledgeModel(
        id: existingPledge.id,
        pledgeNumber: _pledgeNoCtrl.text.trim(),
        pledgeDate: newDateIso,
        loanAmount: _loanAmount,
        interestRate: existingPledge.interestRate,
        status: existingPledge.status,
        source: existingPledge.source,
        createdAt: existingPledge.createdAt,
        customerId: customerId ?? existingPledge.customerId,
        customerSnapshot: customerSnapshot,
        goldPhotoPaths: goldPhotoPaths.isEmpty ? null : goldPhotoPaths,
        formPhotoPaths: formPhotoPaths.isEmpty ? null : formPhotoPaths,
        grossWeight: _grossWeight,
        netWeight: _netWeight,
        goldRate: existingPledge.goldRate,
        pledgeRate: existingPledge.pledgeRate,
        actualItemValue: existingPledge.actualItemValue,
        renewalParentId: existingPledge.renewalParentId,
        renewType: existingPledge.renewType,
        renewSubtype: existingPledge.renewSubtype,
        closureDate: existingPledge.closureDate,
        closedAt: existingPledge.closedAt,
        totalInterestPaid: existingPledge.totalInterestPaid,
        totalAmountCollected: existingPledge.totalAmountCollected,
      );

      final oldJson = jsonEncode({
        'pledge_no': existingPledge.pledgeNumber,
        'pledge_date': existingPledge.pledgeDate,
        'gross_weight': existingPledge.grossWeight,
        'net_weight': existingPledge.netWeight,
        'principal_amount': existingPledge.loanAmount,
        'customer_id': existingPledge.customerId,
      });
      final newJson = jsonEncode({
        'pledge_no': _pledgeNoCtrl.text.trim(),
        'pledge_date': newDateIso,
        'gross_weight': _grossWeight,
        'net_weight': _netWeight,
        'principal_amount': _loanAmount,
        'customer_id': customerId ?? existingPledge.customerId,
        'form_photo_paths': formPhotoPaths,
        'gold_photo_paths': goldPhotoPaths,
      });

      await PledgeRepository.instance.editPledge(
        pledgeId: existingPledge.id!,
        updatedPledge: updatedPledge,
        updatedItems: pledgeItems,
        newGoldPhotoPaths: goldPhotoPaths,
        newFormPhotoPaths: formPhotoPaths,
        originalPrincipal: existingPledge.loanAmount,
        editReason: widget.editReason ?? '',
        oldValueJson: oldJson,
        newValueJson: newJson,
        // Migrated pledges fall before app_use_start_date — no daily_stock
        // rows exist for those dates so gold stock cascade is a guaranteed
        // no-op and is explicitly skipped here for clarity.
        cascadeGoldStock: false,
      );

      if (mounted) {
        setState(() {
          _savedPledgeNo = existingPledge.pledgeNumber;
          _savedAmount = _loanAmount;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving changes: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Step 5 action buttons (context dependent) ────────────────────────────────

  List<Widget> _buildStep5Actions() {
    final spinner = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
            strokeWidth: 2.5, color: FlowColors.textOnNavyLarge));

    final migrateFlow = widget.sourceContext == 'calculator' ||
        widget.sourceContext == 'daily_accounts';

    if (!migrateFlow) {
      return [
        RestrictedAction(
          child: SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _savePledge,
            icon: _isSaving ? spinner : const Icon(Icons.save_alt, size: 24),
            label: Text(_isSaving ? 'SAVING…' : 'SAVE MIGRATED PLEDGE',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: FlowColors.primary,
              foregroundColor: FlowColors.textOnNavyLarge,
              side:
                  const BorderSide(color: FlowColors.borderOnNavy, width: 0.8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        ),
      ];
    }

    return [
      RestrictedAction(
        child: SizedBox(
        width: double.infinity,
        height: 64,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _migrateAndClose,
          icon: _isSaving ? spinner : const Icon(Icons.lock, size: 24),
          label: Text(_isSaving ? 'SAVING…' : 'MIGRATE & CLOSE',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: FlowColors.primary,
            foregroundColor: FlowColors.textOnNavyLarge,
            side:
                const BorderSide(color: FlowColors.borderOnNavy, width: 0.8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      ),
      const SizedBox(height: 12),
      RestrictedAction(
        child: SizedBox(
        width: double.infinity,
        height: 64,
        child: OutlinedButton.icon(
          onPressed: _isSaving ? null : _migrateAndRenew,
          icon: const Icon(Icons.autorenew, size: 24, color: FlowColors.primary),
          label: const Text('MIGRATE & RENEW',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: FlowColors.primary)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: FlowColors.primary, width: 1.5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      ),
    ];
  }

  // ─── Summary helpers ──────────────────────────────────────────────────────────

  Widget _summarySection({
    required String title,
    required VoidCallback onEdit,
    required List<Widget> children,
    bool hideEditButton = false,
    String editLabel = 'EDIT',
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
                if (!hideEditButton)
                  GestureDetector(
                    onTap: onEdit,
                    child: Row(
                      children: [
                        const Icon(Icons.edit_note,
                            size: 16, color: FlowColors.textOnNavyLarge),
                        const SizedBox(width: 4),
                        Text(editLabel,
                            style: const TextStyle(
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 17,
                    color: FlowColors.medText,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 18,
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

  Widget _decimalField(
    String label,
    TextEditingController ctrl, {
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        focusNode: focusNode,
        readOnly: readOnly,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: readOnly
            ? []
            : [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: readOnly
              ? const Icon(Icons.lock_outline,
                  size: 18, color: Colors.black38)
              : null,
        ),
      ),
    );
  }

  Widget _numberField(
    String label,
    TextEditingController ctrl, {
    String? prefixText,
    bool indianFormat = false,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        focusNode: focusNode,
        readOnly: readOnly,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        keyboardType: TextInputType.number,
        inputFormatters: readOnly
            ? []
            : (indianFormat
                ? [IndianNumberFormatter()]
                : [FilteringTextInputFormatter.digitsOnly]),
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefixText,
          suffixIcon: readOnly
              ? const Icon(Icons.lock_outline,
                  size: 18, color: Colors.black38)
              : null,
        ),
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
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
                decoration: BoxDecoration(
                  color: FlowColors.primary,
                  borderRadius: BorderRadius.circular(16),
                  border: const Border.fromBorderSide(BorderSide(
                      color: FlowColors.borderOnNavy, width: 0.8)),
                ),
                child: Column(
                  children: [
                    const Text('Pledge Number',
                        style: TextStyle(
                            fontSize: 16,
                            color: FlowColors.textOnNavyMuted)),
                    const SizedBox(height: 4),
                    Text('#$pledgeNo',
                        style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: FlowColors.goldRich)),
                    const SizedBox(height: 18),
                    const Text('Amount Disbursed',
                        style: TextStyle(
                            fontSize: 16,
                            color: FlowColors.textOnNavyMuted)),
                    const SizedBox(height: 4),
                    Text(money(amount),
                        style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: FlowColors.goldRich)),
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

}

// ─── Edit success screen ──────────────────────────────────────────────────────

class _EditSuccessScreen extends StatelessWidget {
  const _EditSuccessScreen({required this.pledgeNo});
  final String pledgeNo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Pledge Updated'),
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
              const Text('Changes Saved!',
                  style: TextStyle(
                      fontSize: 26,
                      color: FlowColors.green,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
                decoration: BoxDecoration(
                  color: FlowColors.primary,
                  borderRadius: BorderRadius.circular(16),
                  border: const Border.fromBorderSide(
                      BorderSide(color: FlowColors.borderOnNavy, width: 0.8)),
                ),
                child: Column(
                  children: [
                    const Text('Pledge Number',
                        style: TextStyle(
                            fontSize: 16,
                            color: FlowColors.textOnNavyMuted)),
                    const SizedBox(height: 4),
                    Text('#$pledgeNo',
                        style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: FlowColors.goldRich)),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: const Text('DONE',
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
}
