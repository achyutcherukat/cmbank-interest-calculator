import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/print_service.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../pledge_form_print_report.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/shared_customer_details_step.dart';
import '../../../shared/widgets/shared_item_details_step.dart';
import '../../../shared/widgets/shared_split_payment_widget.dart';
import '../../../shared/widgets/restricted_action.dart';
import '../../accounts/data/bank_account_model.dart';
import '../../accounts/data/bank_account_repository.dart';
import '../../customers/data/customer_repository.dart';
import '../../gold_stock/data/gold_rates_repository.dart';
import '../data/payment_model.dart';
import '../data/pledge_item_model.dart';
import '../data/pledge_model.dart';
import '../../../core/services/photo_sync_repository.dart';
import '../data/pledge_repository.dart';

// ─── Main screen ──────────────────────────────────────────────────────────────

class NewPledgeScreen extends StatefulWidget {
  const NewPledgeScreen({
    super.key,
    this.contextDate,
    this.editMode = false,
    this.existingPledge,
    this.existingItems,
    this.existingCustomerRow,
    this.editReason,
  });

  /// Backdated pledge date. When set, the pledge start_date, loan-disbursed
  /// payment, daily-balance and gold-stock updates all use this date, and a
  /// navy banner is shown on step 1.
  final DateTime? contextDate;

  // ── Edit mode ────────────────────────────────────────────────────────────────
  final bool editMode;
  final PledgeModel? existingPledge;
  final List<PledgeItemModel>? existingItems;
  final Map<String, dynamic>? existingCustomerRow;
  final String? editReason;

  @override
  State<NewPledgeScreen> createState() => _NewPledgeScreenState();
}

class _NewPledgeScreenState extends State<NewPledgeScreen> {
  int _step = 1;
  final _settingsRepo = AppSettingsRepository();

  // ── Step 1 ──────────────────────────────────────────────────────────────────
  final _grossWeightCtrl = TextEditingController();
  final _netWeightCtrl = TextEditingController();
  final _pledgeRateCtrl = TextEditingController();
  final _pledgeNoCtrl = TextEditingController();
  final _loanAmtCtrl = TextEditingController();
  final _netFocus = FocusNode();
  final _loanAmtFocus = FocusNode();
  double _goldRate = 0;
  bool _pledgeNoError = false;

  // ── Step 2 — Customer ────────────────────────────────────────────────────────
  final _customerKey = GlobalKey<SharedCustomerDetailsStepState>();
  CustomerDetailsData? _capturedCustomer;

  // ── Step 3 — Items ───────────────────────────────────────────────────────────
  final _itemsKey = GlobalKey<SharedItemDetailsStepState>();
  ItemDetailsData? _capturedItems;
  // Form photo paths for the existing pledge (edit mode only). Loaded from
  // photo_sync_log in _prefillForEdit() so the editPledge() call can pass them.
  List<String> _existingFormPhotoPaths = [];

  // ── Step 4 — Payment ─────────────────────────────────────────────────────────
  final _payKey = GlobalKey<SharedSplitPaymentWidgetState>();
  String _paymentMode = 'cash';
  final _cashCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  List<BankAccount> _bankAccounts = const [];
  int? _selectedBankAccountId;

  // ── Save state ───────────────────────────────────────────────────────────────
  bool _isSaving = false;
  String? _savedPledgeNo;
  double? _savedAmount;

  final _scrollCtrl = ScrollController();

  // ── Computed getters ─────────────────────────────────────────────────────────
  double get _grossWeight => double.tryParse(_grossWeightCtrl.text) ?? 0;
  double get _netWeight => double.tryParse(_netWeightCtrl.text) ?? 0;
  double get _pledgeRate =>
      double.tryParse(_pledgeRateCtrl.text.replaceAll(',', '')) ?? 0;
  double get _maxPledgeValue => _netWeight * _pledgeRate;
  double get _actualItemValue => _goldRate * _netWeight;
  double get _loanAmount =>
      double.tryParse(_loanAmtCtrl.text.replaceAll(',', '')) ?? 0;

  @override
  void initState() {
    super.initState();
    if (widget.editMode) {
      _prefillForEdit();
    } else {
      _loadDefaults();
    }
    _grossWeightCtrl.addListener(() => setState(() {}));
    _netWeightCtrl.addListener(() => setState(() {}));
    _pledgeRateCtrl.addListener(() => setState(() {}));
    _loanAmtCtrl.addListener(() => setState(() {}));
    _loadBankAccounts();
  }

  Future<void> _prefillForEdit() async {
    final p = widget.existingPledge;
    if (p == null) return;

    _pledgeNoCtrl.text = p.pledgeNumber;
    _grossWeightCtrl.text = p.grossWeight.toStringAsFixed(2);
    _netWeightCtrl.text = p.netWeight.toStringAsFixed(2);
    _pledgeRateCtrl.text = formatIndian(p.pledgeRate.round().toString());
    _loanAmtCtrl.text = formatIndian(p.loanAmount.round().toString());
    _goldRate = p.goldRate;

    // Pre-fill customer from the customer row
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
    final formEntries = p.id != null
        ? await PhotoSyncRepository.instance
            .getByPledge(p.id!, PhotoType.document)
        : <PhotoSyncEntry>[];
    _existingFormPhotoPaths = formEntries.map((e) => e.localPath).toList();

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

    // Start on step 5 (review screen)
    _step = 5;

    // Pre-fill payment split from the existing LOAN_DISBURSED payment entry.
    if (p.id != null) {
      final payments =
          await PledgeRepository.instance.getPaymentsForPledge(p.id!);
      final disbursal = payments.firstWhere(
        (pm) =>
            pm.paymentType == PaymentType.loanDisbursed ||
            pm.paymentType == PaymentType.loanIncreaseDisbursed,
        orElse: () => PaymentModel(
          paymentDate: p.pledgeDate,
          paymentType: PaymentType.loanDisbursed,
          direction: PaymentDirection.outward,
          amount: p.loanAmount,
          cashAmount: p.loanAmount,
          bankAmount: 0,
          createdAt: p.pledgeDate,
        ),
      );
      if (mounted) {
        setState(() {
          final cash = disbursal.cashAmount;
          final bank = disbursal.bankAmount;
          if (bank <= 0) {
            _paymentMode = 'cash';
          } else if (cash <= 0) {
            _paymentMode = 'bank';
          } else {
            _paymentMode = 'split';
            _cashCtrl.text = formatIndian(cash.round().toString());
            _bankCtrl.text = formatIndian(bank.round().toString());
          }
          if (disbursal.bankAccountId != null) {
            _selectedBankAccountId = disbursal.bankAccountId;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _grossWeightCtrl.dispose();
    _netWeightCtrl.dispose();
    _pledgeRateCtrl.dispose();
    _pledgeNoCtrl.dispose();
    _loanAmtCtrl.dispose();
    _netFocus.dispose();
    _loanAmtFocus.dispose();
    _cashCtrl.dispose();
    _bankCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    if (widget.editMode) return;
    final rates = await GoldRatesRepository.instance.getCurrentRates();
    final nextPledgeNo = await PledgeRepository.instance.nextPledgeNumber();
    if (mounted) {
      setState(() {
        _pledgeRateCtrl.text =
            formatIndian((rates?.pledgeRate ?? 0).round().toString());
        _goldRate = rates?.goldRate ?? 0;
        if (_pledgeNoCtrl.text.trim().isEmpty) {
          _pledgeNoCtrl.text = nextPledgeNo;
        }
      });
    }
  }

  Future<void> _loadBankAccounts() async {
    final accounts = await BankAccountRepository.instance.getActive();
    if (mounted) {
      setState(() {
        _bankAccounts = accounts;
        if (_selectedBankAccountId == null) {
          final def = accounts.cast<BankAccount?>()
              .firstWhere((a) => a?.isDefault == true, orElse: () => null);
          _selectedBankAccountId =
              (def ?? (accounts.isNotEmpty ? accounts.first : null))?.id;
        }
      });
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  void _back() {
    if (widget.editMode) {
      // In edit mode, step 5 is the entry point — going back from step 5 exits
      if (_step > 1 && _step != 5) {
        setState(() => _step--);
      } else {
        Navigator.pop(context);
      }
    } else {
      if (_step > 1) {
        setState(() => _step--);
      } else {
        Navigator.pop(context);
      }
    }
  }

  void _advanceTo(int step) {
    setState(() => _step = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    });
  }

  // ── Step 1: proceed ──────────────────────────────────────────────────────────

  Future<void> _proceedFromStep1() async {
    final gw = double.tryParse(_grossWeightCtrl.text.trim());
    final nw = double.tryParse(_netWeightCtrl.text.trim());
    final pr =
        double.tryParse(_pledgeRateCtrl.text.trim().replaceAll(',', ''));

    if (gw == null || gw <= 0) {
      _showError('Enter a valid gross weight (grams).');
      return;
    }
    if (nw == null || nw <= 0) {
      _showError('Enter a valid net weight (grams).');
      return;
    }
    if (nw > gw) {
      _showError('Net weight cannot exceed gross weight.');
      return;
    }
    if (pr == null || pr <= 0) {
      _showError('Enter a valid pledge rate per gram.');
      return;
    }

    if (!widget.editMode) {
      if (_pledgeNoCtrl.text.trim().isEmpty) {
        final next = await PledgeRepository.instance.nextPledgeNumber();
        _pledgeNoCtrl.text = next;
      }
      await _checkPledgeNo();
      if (!mounted) return;
      if (_pledgeNoError) {
        _showError(
            'Pledge number ${_pledgeNoCtrl.text.trim()} already exists. Please change it.');
        return;
      }
    }

    if (_loanAmtCtrl.text.trim().isEmpty) {
      _loanAmtCtrl.text = formatIndian(_maxPledgeValue.round().toString());
    }

    _advanceTo(2);
  }

  // ── Pledge number check ───────────────────────────────────────────────────────

  Future<void> _checkPledgeNo() async {
    final no = _pledgeNoCtrl.text.trim();
    if (no.isEmpty) return;
    final exists = await PledgeRepository.instance.pledgeNumberExists(no);
    if (mounted) setState(() => _pledgeNoError = exists);
  }

  // ── Save pledge ───────────────────────────────────────────────────────────────

  Future<void> _savePledge() async {
    if (_pledgeNoError) {
      _showError(
          'Pledge number ${_pledgeNoCtrl.text.trim()} already exists.');
      return;
    }
    if (_loanAmount <= 0) {
      _showError('Loan amount is invalid.');
      return;
    }
    if (_paymentMode == 'split') {
      final cash = double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0;
      final upi = double.tryParse(_bankCtrl.text.replaceAll(',', '')) ?? 0;
      if ((cash + upi - _loanAmount).abs() > 0.5) {
        _showError(
            'Cash + UPI (${money(cash + upi)}) must equal loan amount (${money(_loanAmount)}).');
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final interestRateStr =
          await _settingsRepo.getString('interest_rate') ??
              await _settingsRepo.getString('default_interest_rate');
      final interestRate = double.tryParse(interestRateStr ?? '') ?? 18.0;
      final now = DateTime.now();
      final dateStr = widget.contextDate != null
          ? widget.contextDate!.toIso8601String().substring(0, 10)
          : now.toIso8601String().substring(0, 10);

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

      // ── Gold photos (now stored at pledge level) ───────────────────────────────
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

      // ── Payment amounts ──────────────────────────────────────────────────────
      double cashAmt = _loanAmount;
      double bankAmt = 0;
      if (_paymentMode == 'bank') {
        cashAmt = 0;
        bankAmt = _loanAmount;
      } else if (_paymentMode == 'split') {
        cashAmt = double.tryParse(_cashCtrl.text.replaceAll(',', '').trim()) ?? 0;
        bankAmt = double.tryParse(_bankCtrl.text.replaceAll(',', '').trim()) ?? 0;
      }

      // ── Save pledge ──────────────────────────────────────────────────────────
      final pledge = PledgeModel(
        pledgeNumber: _pledgeNoCtrl.text.trim(),
        pledgeDate: dateStr,
        loanAmount: _loanAmount,
        interestRate: interestRate,
        status: 'open',
        source: 'new',
        createdAt: now.toIso8601String(),
        customerId: customerId,
        customerSnapshot: customerSnapshot,
        goldPhotoPaths: goldPhotoPaths.isEmpty ? null : goldPhotoPaths,
        grossWeight: _grossWeight,
        netWeight: _netWeight,
        goldRate: _goldRate,
        pledgeRate: _pledgeRate,
        actualItemValue: _actualItemValue,
      );

      await PledgeRepository.instance.createPledge(
        pledge,
        pledgeItems,
        cashAmount: cashAmt,
        bankAmount: bankAmt,
        bankAccountId: _selectedBankAccountId,
        contextDate: widget.contextDate != null ? dateStr : null,
      );

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
        isEdit: widget.editMode,
      );
    }
    final appBarTitle = widget.editMode
        ? 'Edit Pledge #${widget.existingPledge?.pledgeNumber ?? ''}'
        : 'New Pledge';
    return PopScope(
      canPop: widget.editMode ? _step == 5 : _step == 1,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          if (widget.editMode) {
            if (_step > 1) setState(() => _step--);
          } else {
            setState(() => _step--);
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
            _StepIndicator(currentStep: _step),
            Expanded(
              child: ListView(
                controller: _scrollCtrl,
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

  // ─── Step 1: Gold & Loan Details ────────────────────────────────────────────

  Widget _buildStep1() {
    final step1ReadOnly = widget.editMode &&
        widget.existingPledge?.renewalParentId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (step1ReadOnly)
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
        if (widget.contextDate != null)
          ContextDateBanner(label: 'Pledge Date', date: widget.contextDate!),
        const _SectionHeader('Gold Details'),
        _decimalField('Gross Weight (grams)', _grossWeightCtrl,
            readOnly: step1ReadOnly,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _netFocus.requestFocus()),
        _decimalField('Net Weight (grams)', _netWeightCtrl,
            focusNode: _netFocus,
            readOnly: step1ReadOnly,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _loanAmtFocus.requestFocus()),
        _numberField('Pledge Rate (₹/gram)', _pledgeRateCtrl,
            suffixText: '/g',
            indianFormat: true,
            readOnly: step1ReadOnly,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus()),
        FlowCard(
          backgroundColor: FlowColors.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardLabel('MAX PLEDGE VALUE'),
              Text(
                money(_maxPledgeValue),
                style: const TextStyle(
                    color: FlowColors.primary,
                    fontSize: 30,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '${_netWeight.toStringAsFixed(2)} g × ${money(_pledgeRate)}/g',
                style: const TextStyle(
                    color: FlowColors.medText, fontSize: 14),
              ),
            ],
          ),
        ),
        const _SectionHeader('Pledge Number'),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: TextField(
            controller: _pledgeNoCtrl,
            readOnly: step1ReadOnly,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: step1ReadOnly
                ? []
                : [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              labelText: 'Pledge Number',
              prefixIcon: Icon(step1ReadOnly ? Icons.lock : Icons.tag),
              errorText: _pledgeNoError
                  ? 'This pledge number already exists'
                  : null,
            ),
            onChanged: step1ReadOnly
                ? null
                : (_) => setState(() => _pledgeNoError = false),
            onEditingComplete: step1ReadOnly ? null : _checkPledgeNo,
            onSubmitted: step1ReadOnly
                ? null
                : (_) => FocusScope.of(context).nextFocus(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            step1ReadOnly
                ? 'Pledge number cannot be changed.'
                : 'Auto-filled. Edit if needed.',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
        const _SectionHeader('Loan Amount'),
        _numberField('Loan Amount (₹)', _loanAmtCtrl,
            focusNode: _loanAmtFocus,
            prefixText: '₹ ',
            indianFormat: true,
            readOnly: step1ReadOnly,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus()),
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Text(
            step1ReadOnly
                ? 'Loan amount cannot be changed.'
                : 'Max: ${money(_maxPledgeValue)}. Can be lower.',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
        _proceedBtn(_proceedFromStep1),
      ],
    );
  }

  // ─── Step 2: Customer Details (shared widget) ────────────────────────────────

  Widget _buildStep2() {
    void skip() {
      _capturedCustomer = _customerKey.currentState?.getData();
      _advanceTo(3);
    }

    void proceed() {
      final error = _customerKey.currentState?.validate();
      if (error != null) {
        _showError(error);
        return;
      }
      _capturedCustomer = _customerKey.currentState?.getData();
      _advanceTo(3);
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

  // ─── Step 3: Item Details (shared widget) ────────────────────────────────────

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
            _advanceTo(4);
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
            _advanceTo(4);
          },
        ),
      ],
    );
  }

  // ─── Step 4: Payment Mode ────────────────────────────────────────────────────

  Widget _buildStep4() {
    final initCash = _paymentMode == 'split'
        ? (double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0)
        : null;
    final initBank = _paymentMode == 'split'
        ? (double.tryParse(_bankCtrl.text.replaceAll(',', '')) ?? 0)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Payment Mode'),
        SharedSplitPaymentWidget(
          key: _payKey,
          total: _loanAmount,
          totalLabel: 'Loan Amount',
          bankAccounts: _bankAccounts,
          isMoneyIn: false,
          initialMode: _paymentMode,
          initialCashAmount: initCash,
          initialBankAmount: initBank,
          initialBankAccountId: _selectedBankAccountId,
        ),
        const SizedBox(height: 28),
        _proceedBtn(() {
          final payState = _payKey.currentState;
          final err = payState?.validate();
          if (err != null) { _showError(err); return; }
          // Capture before widget leaves the tree
          _paymentMode = payState?.mode ?? 'cash';
          final ca = payState?.cashAmount ?? _loanAmount;
          final ba = payState?.bankAmount ?? 0;
          _cashCtrl.text = ca > 0 ? formatIndian(ca.round().toString()) : '';
          _bankCtrl.text = ba > 0 ? formatIndian(ba.round().toString()) : '';
          _selectedBankAccountId = payState?.bankAccountId;
          _advanceTo(5);
        }),
      ],
    );
  }

  // ─── Step 5: Summary & Confirmation ─────────────────────────────────────────

  String _bankLabel() {
    if (_selectedBankAccountId == null) return 'Bank';
    final name = _bankAccounts
        .cast<BankAccount?>()
        .firstWhere((a) => a?.id == _selectedBankAccountId, orElse: () => null)
        ?.name;
    return name != null ? 'Bank ($name)' : 'Bank';
  }

  Widget _buildStep5() {
    if (widget.editMode) return _buildEditStep5();

    final now = DateTime.now();
    final displayDate = formatDmy(widget.contextDate ?? now);
    final cashAmt = _paymentMode == 'cash'
        ? _loanAmount
        : _paymentMode == 'bank'
            ? 0.0
            : double.tryParse(_cashCtrl.text.replaceAll(',', '')) ?? 0;
    final bankAmt = _paymentMode == 'bank'
        ? _loanAmount
        : _paymentMode == 'cash'
            ? 0.0
            : double.tryParse(_bankCtrl.text.replaceAll(',', '')) ?? 0;
    final customer = _capturedCustomer;
    final itemData = _capturedItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Review & Confirm'),

        // Loan
        _summarySection(
          title: 'LOAN',
          onEdit: () => setState(() => _step = 1),
          children: [
            _summaryRow('Pledge No.', '#${_pledgeNoCtrl.text}',
                highlight: true),
            _summaryRow('Date', displayDate),
            _summaryRow('Loan Amount', money(_loanAmount), highlight: true),
          ],
        ),

        // Gold
        _summarySection(
          title: 'GOLD',
          onEdit: () => setState(() => _step = 1),
          children: [
            _summaryRow(
                'Gross Weight', '${_grossWeight.toStringAsFixed(2)} g'),
            _summaryRow(
                'Net Weight', '${_netWeight.toStringAsFixed(2)} g'),
            _summaryRow('Pledge Rate', '${money(_pledgeRate)}/g'),
            _summaryRow('Actual Item Value', money(_actualItemValue)),
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
                      style:
                          TextStyle(color: Colors.black45, fontSize: 15)),
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
                      style:
                          TextStyle(color: Colors.black45, fontSize: 15)),
                ],
        ),

        // Payment
        _summarySection(
          title: 'PAYMENT',
          onEdit: () => setState(() => _step = 4),
          children: [
            _summaryRow('Mode', _paymentMode.toUpperCase()),
            if (_paymentMode != 'bank') _summaryRow('Cash', money(cashAmt)),
            if (_paymentMode != 'cash') _summaryRow(_bankLabel(), money(bankAmt)),
            _summaryRow('Total', money(_loanAmount), highlight: true),
          ],
        ),

        const SizedBox(height: 24),
        RestrictedAction(
          child: SizedBox(
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
                : const Icon(Icons.check_circle, size: 24),
            label: Text(
                _isSaving ? 'SAVING…' : 'ACCEPT PLEDGE',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: FlowColors.primary,
              foregroundColor: FlowColors.textOnNavyLarge,
              side: const BorderSide(color: FlowColors.borderOnNavy, width: 0.8),
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

  // ─── Edit Step 5: Edit review + SAVE CHANGES ─────────────────────────────────

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

        // Gold & Loan
        _summarySection(
          title: 'GOLD & LOAN',
          onEdit: () => setState(() => _step = 1),
          children: [
            _summaryRow('Pledge No.', '#${p.pledgeNumber}', highlight: true),
            _summaryRow('Date', isoToDisplay(p.pledgeDate)),
            _summaryRow(
                'Gross Weight', '${_grossWeight.toStringAsFixed(2)} g'),
            _summaryRow(
                'Net Weight', '${_netWeight.toStringAsFixed(2)} g'),
            _summaryRow('Pledge Rate', '${money(_pledgeRate)}/g'),
            _summaryRow('Loan Amount', money(_loanAmount), highlight: true),
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
                      style:
                          TextStyle(color: Colors.black45, fontSize: 15)),
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
                        if (i > 0) const Divider(height: 16, thickness: 0.8),
                        Text('Item List ${i + 1}',
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
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
                      style:
                          TextStyle(color: Colors.black45, fontSize: 15)),
                ],
        ),

        // Payment
        _summarySection(
          title: 'PAYMENT',
          onEdit: () => setState(() => _step = 4),
          children: [
            _summaryRow('Mode', _paymentMode.toUpperCase()),
            if (_paymentMode != 'bank')
              _summaryRow(
                  'Cash',
                  money(_paymentMode == 'cash'
                      ? _loanAmount
                      : (double.tryParse(
                              _cashCtrl.text.replaceAll(',', '')) ??
                          0))),
            if (_paymentMode != 'cash')
              _summaryRow(
                  _bankLabel(),
                  money(_paymentMode == 'bank'
                      ? _loanAmount
                      : (double.tryParse(
                              _bankCtrl.text.replaceAll(',', '')) ??
                          0))),
            _summaryRow('Total', money(_loanAmount), highlight: true),
          ],
        ),

        const SizedBox(height: 24),
        RestrictedAction(
          child: SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _updatePledge,
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
                    fontSize: 20, fontWeight: FontWeight.w600)),
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

  Future<void> _updatePledge() async {
    final existingPledge = widget.existingPledge!;
    if (_loanAmount <= 0) {
      _showError('Loan amount is invalid.');
      return;
    }

    // Compute exact split from user's Step 4 selection.
    final cashAmt = _paymentMode == 'bank'
        ? 0.0
        : _paymentMode == 'cash'
            ? _loanAmount
            : double.tryParse(
                    _cashCtrl.text.replaceAll(',', '').trim()) ??
                0.0;
    final bankAmt = _paymentMode == 'cash'
        ? 0.0
        : _paymentMode == 'bank'
            ? _loanAmount
            : double.tryParse(
                    _bankCtrl.text.replaceAll(',', '').trim()) ??
                0.0;
    if ((cashAmt + bankAmt - _loanAmount).abs() > 0.5) {
      _showError(
          'Cash + Bank must equal the loan amount (${money(_loanAmount)}). '
          'Please go back to Step 4 and correct the payment split.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final settingsRepo = AppSettingsRepository();
      final interestRateStr =
          await settingsRepo.getString('interest_rate') ??
              await settingsRepo.getString('default_interest_rate');
      final interestRate = double.tryParse(interestRateStr ?? '') ?? 18.0;

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
        pledgeNumber: existingPledge.pledgeNumber,
        pledgeDate: existingPledge.pledgeDate,
        loanAmount: _loanAmount,
        interestRate: interestRate,
        status: existingPledge.status,
        source: existingPledge.source,
        createdAt: existingPledge.createdAt,
        customerId: customerId ?? existingPledge.customerId,
        customerSnapshot: customerSnapshot,
        goldPhotoPaths: goldPhotoPaths.isEmpty ? null : goldPhotoPaths,
        formPhotoPaths: _existingFormPhotoPaths.isNotEmpty ? _existingFormPhotoPaths : null,
        grossWeight: _grossWeight,
        netWeight: _netWeight,
        goldRate: _goldRate,
        pledgeRate: _pledgeRate,
        actualItemValue: _goldRate * _netWeight,
        renewalParentId: existingPledge.renewalParentId,
        renewType: existingPledge.renewType,
        renewSubtype: existingPledge.renewSubtype,
        closureDate: existingPledge.closureDate,
        closedAt: existingPledge.closedAt,
        totalInterestPaid: existingPledge.totalInterestPaid,
        totalAmountCollected: existingPledge.totalAmountCollected,
      );

      // Build audit JSON
      final oldJson = jsonEncode({
        'gross_weight': existingPledge.grossWeight,
        'net_weight': existingPledge.netWeight,
        'principal_amount': existingPledge.loanAmount,
        'pledge_rate': existingPledge.pledgeRate,
        'customer_id': existingPledge.customerId,
        'gold_photo_paths': null,
      });
      final newJson = jsonEncode({
        'gross_weight': _grossWeight,
        'net_weight': _netWeight,
        'principal_amount': _loanAmount,
        'pledge_rate': _pledgeRate,
        'customer_id': customerId ?? existingPledge.customerId,
        'gold_photo_paths': goldPhotoPaths,
      });

      await PledgeRepository.instance.editPledge(
        pledgeId: existingPledge.id!,
        updatedPledge: updatedPledge,
        updatedItems: pledgeItems,
        newGoldPhotoPaths: goldPhotoPaths,
        newFormPhotoPaths: _existingFormPhotoPaths,
        originalPrincipal: existingPledge.loanAmount,
        editReason: widget.editReason ?? '',
        oldValueJson: oldJson,
        newValueJson: newJson,
        newCashAmount: cashAmt,
        newBankAmount: bankAmt,
        newBankAccountId: _selectedBankAccountId,
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

  Widget _summarySection({
    required String title,
    required VoidCallback onEdit,
    required List<Widget> children,
    bool hideEditButton = false,
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
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: FlowColors.goldRich,
                        letterSpacing: 0.5)),
                if (!hideEditButton)
                GestureDetector(
                  onTap: onEdit,
                  child: const Row(
                    children: [
                      Icon(Icons.edit_note,
                          size: 16, color: FlowColors.goldRich),
                      SizedBox(width: 4),
                      Text('EDIT',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: FlowColors.goldRich)),
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

  Widget _summaryRow(String label, String value, {bool highlight = false}) {
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
    bool dense = false,
    VoidCallback? onChanged,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    FocusNode? focusNode,
    bool readOnly = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 10 : 14),
      child: TextField(
        controller: ctrl,
        focusNode: focusNode,
        readOnly: readOnly,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        inputFormatters: readOnly
            ? []
            : [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
        style: TextStyle(fontSize: dense ? 16 : 18),
        onChanged: onChanged != null ? (_) => onChanged() : null,
        decoration: InputDecoration(
          labelText: label,
          isDense: dense,
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
    String? suffixText,
    bool dense = false,
    bool indianFormat = false,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    FocusNode? focusNode,
    bool readOnly = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 10 : 14),
      child: TextField(
        controller: ctrl,
        focusNode: focusNode,
        readOnly: readOnly,
        keyboardType: TextInputType.number,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        inputFormatters: readOnly
            ? []
            : (indianFormat
                ? [IndianNumberFormatter()]
                : [FilteringTextInputFormatter.digitsOnly]),
        style: TextStyle(fontSize: dense ? 16 : 18),
        decoration: InputDecoration(
          labelText: label,
          isDense: dense,
          prefixText: prefixText,
          suffixText: readOnly ? null : suffixText,
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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
              side: const BorderSide(color: FlowColors.primary, width: 1.5),
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

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep});
  final int currentStep;

  static const _labels = [
    'Gold', 'Customer', 'Items', 'Payment', 'Review'
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

// ─── Section header & card label ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
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

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: FlowColors.medText,
              letterSpacing: 0.5)),
    );
  }
}

// ─── Success screen ───────────────────────────────────────────────────────────

class _SuccessScreen extends StatelessWidget {
  const _SuccessScreen({
    required this.pledgeNo,
    required this.amount,
    this.isEdit = false,
  });
  final String pledgeNo;
  final double amount;
  final bool isEdit;

  @override
  Widget build(BuildContext context) {
    final title = isEdit ? 'Pledge Updated' : 'Pledge Created';
    final message = isEdit ? 'Changes Saved!' : 'Pledge Saved!';
    final btnLabel = isEdit ? 'DONE' : 'BACK TO HOME';
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Text(title),
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
              Text(message,
                  style: const TextStyle(
                      fontSize: 26,
                      color: FlowColors.green,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _SuccessValuesCard(pledgeNo: pledgeNo, amount: amount),
              const SizedBox(height: 28),
              if (!isEdit) ...[
                OutlinedButton.icon(
                  onPressed: () => _printForm(context),
                  icon: const Icon(Icons.print, color: FlowColors.primary),
                  label: const Text('PRINT RECEIPT',
                      style: TextStyle(
                          fontSize: 16, color: FlowColors.primary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: FlowColors.primary),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: Text(btnLabel,
                      style: const TextStyle(fontSize: 17)),
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

  // ─── Print the double-sided pledge form (Form E) ────────────────────────────

  Future<void> _printForm(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      // Only pledgeNo is in scope here — resolve the pledge id.
      final db = await AppDatabase.instance.database;
      final rows = await db.query('pledges',
          columns: ['id'],
          where: 'pledge_no = ?',
          whereArgs: [pledgeNo],
          limit: 1);
      if (rows.isEmpty) throw StateError('Pledge $pledgeNo not found.');
      final pledgeId = rows.first['id'] as int;

      final doc = await PledgeFormPrintReport.generate(pledgeId);
      if (!context.mounted) return;
      Navigator.pop(context); // dismiss loader
      _showPrintSheet(context, doc);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // dismiss loader
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate pledge form: $e')),
      );
    }
  }

  void _showPrintSheet(BuildContext context, pw.Document doc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            Text('Pledge Form — #$pledgeNo',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.primary)),
            ListTile(
              leading: const Icon(Icons.print, color: FlowColors.primary),
              title: const Text('Print'),
              onTap: () {
                Navigator.pop(ctx);
                PrintService.printDocument(
                    pdf: doc, documentName: 'PledgeForm_$pledgeNo');
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt, color: FlowColors.primary),
              title: const Text('Save as PDF'),
              onTap: () {
                Navigator.pop(ctx);
                PrintService.saveAsPdf(
                    pdf: doc,
                    fileName: 'PledgeForm_$pledgeNo.pdf',
                    context: context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Prominent navy card with gold values used on the success screens to make
/// the Pledge Number and Amount Disbursed stand out.
class _SuccessValuesCard extends StatelessWidget {
  const _SuccessValuesCard({required this.pledgeNo, required this.amount});
  final String pledgeNo;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
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
                  fontSize: 16, color: FlowColors.textOnNavyMuted)),
          const SizedBox(height: 4),
          Text('#$pledgeNo',
              style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.goldRich)),
          const SizedBox(height: 18),
          const Text('Amount Disbursed',
              style: TextStyle(
                  fontSize: 16, color: FlowColors.textOnNavyMuted)),
          const SizedBox(height: 4),
          Text(money(amount),
              style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.goldRich)),
        ],
      ),
    );
  }
}
