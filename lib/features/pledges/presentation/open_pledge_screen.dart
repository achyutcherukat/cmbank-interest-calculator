import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme.dart';
import '../../../features/accounts/data/bank_account_model.dart';
import '../../../features/accounts/data/bank_account_repository.dart';
import '../../../features/accounts/data/daily_balance_repository.dart';
import '../../../features/calculator/data/interest_calculator.dart';
import '../../../features/gold_stock/data/gold_rates_repository.dart';
import '../../admin/data/purity_types_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/restorable_photo_thumb.dart';
import '../../../shared/widgets/restricted_action.dart';
import '../../../shared/widgets/shared_split_payment_widget.dart';
import '../../../core/services/photo_sync_repository.dart';
import '../data/payment_model.dart';
import '../data/pledge_item_model.dart';
import '../data/pledge_model.dart';
import '../data/pledge_repository.dart';
import '../pledge_form_print_actions.dart';
import '../../../shared/widgets/shared_item_details_step.dart';
import '../../customers/presentation/customer_detail_screen.dart';
import 'load_existing_pledge_screen.dart';
import 'new_pledge_screen.dart';

// ─── Open Pledge Screen ───────────────────────────────────────────────────────

class OpenPledgeScreen extends StatefulWidget {
  const OpenPledgeScreen({super.key});

  @override
  State<OpenPledgeScreen> createState() => _OpenPledgeScreenState();
}

class _OpenPledgeScreenState extends State<OpenPledgeScreen> {
  static const _pageSize = 20;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final List<PledgeModel> _pledges = [];
  bool _notFound = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    setState(() => _loading = true);
    final page =
        await PledgeRepository.instance.getOpenPledges(limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _pledges
        ..clear()
        ..addAll(page);
      _hasMore = page.length == _pageSize;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final page = await PledgeRepository.instance
        .getOpenPledges(limit: _pageSize, offset: _pledges.length);
    if (!mounted) return;
    setState(() {
      _pledges.addAll(page);
      _hasMore = page.length == _pageSize;
      _loadingMore = false;
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final pledge = await PledgeRepository.instance.getPledgeByNumber(query);
    if (!mounted) return;
    if (pledge == null || pledge.status != 'open') {
      setState(() => _notFound = true);
      return;
    }
    setState(() => _notFound = false);
    _openDetail(pledge);
  }

  void _openDetail(PledgeModel pledge) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PledgeDetailScreen(pledgeId: pledge.id!)),
    ).then((_) => _loadFirstPage());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Active Loans'),
      ),
      backgroundColor: FlowColors.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFirstPage,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16).withNavBarInset(context),
                itemCount: 1 + _pledges.length + 1,
                itemBuilder: (ctx, index) {
                  if (index == 0) return _searchHeader();
                  final listIndex = index - 1;
                  if (listIndex < _pledges.length) {
                    return _pledgeCard(_pledges[listIndex]);
                  }
                  return _footer();
                },
              ),
            ),
    );
  }

  Widget _searchHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowSectionTitle('Search by Pledge Number'),
        TextField(
          controller: _searchController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Pledge Number',
            hintText: 'e.g. 3201',
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _search,
            icon: const Icon(Icons.manage_search),
            label: const Text('SEARCH'),
          ),
        ),
        if (_notFound) ...[
          const SizedBox(height: 10),
          const FlowCard(
            backgroundColor: FlowColors.redLight,
            borderColor: FlowColors.red,
            child: Text(
              'No open pledge found for that number.',
              style: TextStyle(
                  color: FlowColors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
        const SizedBox(height: 18),
        const FlowSectionTitle('Open Pledges'),
        if (_pledges.isEmpty)
          const FlowCard(
            child: Text('No open pledges.',
                style: TextStyle(color: Colors.black54)),
          ),
      ],
    );
  }

  Widget _footer() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    return const SizedBox(height: 8);
  }

  Widget _pledgeCard(PledgeModel p) {
    return GestureDetector(
      onTap: () => _openDetail(p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: FlowColors.primaryLight, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Pledge ${p.pledgeNumber}',
                          style: const TextStyle(
                              color: FlowColors.primary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      const StatusBadge(
                        text: 'ACTIVE',
                        color: CMBColors.successGreen,
                        backgroundColor: FlowColors.greenLight,
                        borderColor: CMBColors.successGreen,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                      '${isoToDisplay(p.pledgeDate)}  ·  ${money(p.loanAmount)}',
                      style: const TextStyle(
                          fontSize: 15, color: FlowColors.medText)),
                  if (p.customerName.isNotEmpty)
                    Text(p.customerName,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black45)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.black38, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── Pledge Detail Screen ─────────────────────────────────────────────────────

class PledgeDetailScreen extends StatefulWidget {
  const PledgeDetailScreen({
    super.key,
    required this.pledgeId,
    this.contextDate,
    this.hideActions = false,
    this.editEntryContext = false,
    this.editReason,
  });
  final int pledgeId;

  /// When set (backdated daily-accounts flow), interest is calculated up to
  /// this date instead of today and a navy context-date banner is shown.
  final DateTime? contextDate;

  /// When true, hides the Close Pledge and Renew buttons (used when navigating
  /// from Money OUT drill-down so staff can view details without taking action).
  final bool hideActions;

  /// When true, shows the EDIT PLEDGE button. Only set from AdminArea flows.
  final bool editEntryContext;

  /// The admin-supplied reason for the edit, passed through to the wizard.
  final String? editReason;

  @override
  State<PledgeDetailScreen> createState() => _PledgeDetailScreenState();
}

class _PledgeDetailScreenState extends State<PledgeDetailScreen> {
  PledgeModel? _pledge;
  List<PledgeItemModel> _items = [];
  Map<String, dynamic>? _customer;
  bool _loading = true;
  List<_ChainEntry> _chain = [];
  List<String> _goldPhotoPaths = [];
  List<String> _idProofPhotoPaths = [];
  bool _pledgeDayLocked = false;
  bool _addingPhoto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pledge =
        await PledgeRepository.instance.getPledgeById(widget.pledgeId);
    final items =
        await PledgeRepository.instance.getItemsForPledge(widget.pledgeId);

    Map<String, dynamic>? customer;

    if (pledge != null && pledge.customerId != null) {
      customer = await PledgeRepository.instance
          .getCustomerById(pledge.customerId!);
    }

    final chain = pledge != null ? await _buildChain(pledge) : <_ChainEntry>[];

    final goldPhotos = pledge != null
        ? await PhotoSyncRepository.instance
            .getByPledge(pledge.id!, PhotoType.gold)
        : <PhotoSyncEntry>[];
    final idProofPhotos = pledge?.customerId != null
        ? await PhotoSyncRepository.instance
            .getByCustomer(pledge!.customerId!)
        : <PhotoSyncEntry>[];

    final pledgeDayLocked = pledge != null
        ? await DailyBalanceRepository.instance.isDateLocked(pledge.pledgeDate)
        : false;

    if (mounted) {
      setState(() {
        _pledge = pledge;
        _items = items;
        _customer = customer;
        _chain = chain;
        _goldPhotoPaths = goldPhotos.map((e) => e.localPath).toList();
        _idProofPhotoPaths = idProofPhotos.map((e) => e.localPath).toList();
        _pledgeDayLocked = pledgeDayLocked;
        _loading = false;
      });
    }
  }

  Future<void> _addGoldPhoto() async {
    final pledge = _pledge;
    if (pledge == null) return;
    setState(() => _addingPhoto = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked == null || !mounted) return;

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Photo',
            toolbarColor: CMBColors.navy,
            toolbarWidgetColor: CMBColors.goldRich,
            lockAspectRatio: false,
            hideBottomControls: true,
          ),
          IOSUiSettings(title: 'Crop Photo'),
        ],
      );
      if (cropped == null || !mounted) return;

      final docsDir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${docsDir.path}/pledge_photos');
      await destDir.create(recursive: true);

      final ts = DateTime.now().millisecondsSinceEpoch;
      final prefix = pledge.pledgeNumber.isNotEmpty
          ? pledge.pledgeNumber
          : 'pledge';
      final dest = File('${destDir.path}/${prefix}_item_$ts.jpg');
      await File(cropped.path).copy(dest.path);

      await PhotoSyncRepository.instance.insertPhoto(
        pledgeId: pledge.id!,
        photoType: PhotoType.gold,
        localPath: dest.path,
      );

      if (mounted) {
        setState(() => _goldPhotoPaths = [..._goldPhotoPaths, dest.path]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not take photo: $e'),
          backgroundColor: CMBColors.warningRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _addingPhoto = false);
    }
  }

  Future<List<_ChainEntry>> _buildChain(PledgeModel p) async {
    final chain = <_ChainEntry>[];

    // Walk up to find ancestors
    PledgeModel? cur = p;
    while (cur != null) {
      chain.insert(
          0, _ChainEntry(cur.pledgeNumber, cur.id!, cur.id == p.id, cur.status));
      if (cur.renewalParentId == null) break;
      cur = await PledgeRepository.instance.getPledgeById(cur.renewalParentId!);
    }

    // Walk down to find successors (up to 10 to avoid infinite loop)
    int limit = 10;
    PledgeModel? succ =
        await PledgeRepository.instance.getSuccessorPledge(p.id!);
    while (succ != null && limit-- > 0) {
      chain.add(_ChainEntry(succ.pledgeNumber, succ.id!, false, succ.status));
      succ = await PledgeRepository.instance.getSuccessorPledge(succ.id!);
    }

    return chain;
  }

  Future<void> _goClose(PledgeModel p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClosePledgeScreen(
          pledge: p,
          contextDate: widget.contextDate,
        ),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  void _goRenew(PledgeModel p) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RenewSelectionScreen(
          pledge: p,
          contextDate: widget.contextDate,
        ),
      ),
    );
  }

  Future<void> _goEdit(PledgeModel p) async {
    final items = _items;
    final customer = _customer;
    final reason = widget.editReason ?? '';

    Widget wizard;
    if (p.source == 'migrated') {
      wizard = LoadExistingPledgeScreen(
        editMode: true,
        existingPledge: p,
        existingItems: items,
        existingCustomerRow: customer,
        editReason: reason,
      );
    } else {
      wizard = NewPledgeScreen(
        editMode: true,
        existingPledge: p,
        existingItems: items,
        existingCustomerRow: customer,
        editReason: reason,
      );
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => wizard),
    );

    if (mounted) {
      // Replace this editEntryContext detail screen with a fresh normal view
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PledgeDetailScreen(pledgeId: p.id!),
        ),
      );
    }
  }

  void _showInterestPreview(
      PledgeModel p, DateTime fromDate, DateTime today) {
    const offsets = [0, 1, 7, 30];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Interest Preview',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              p.renewalParentId != null
                  ? '* Minimum ₹20 applied where applicable.'
                  : '* Minimum 7 days & ₹50 applied where applicable.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            ...offsets.map((extra) {
              final targetDate = today.add(Duration(days: extra));
              final calc = InterestCalculator.calculate(
                principal: p.loanAmount,
                fromDate: fromDate,
                toDate: targetDate,
                ratePercent: p.interestRate,
                isRenewalPledge: p.renewalParentId != null,
              );
              final days = InterestCalculator.effectiveDays(fromDate, targetDate,
                  isRenewalPledge: p.renewalParentId != null);
              final label = extra == 0
                  ? 'Today'
                  : extra == 1
                      ? 'Tomorrow'
                      : '+$extra Days';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$label ($days d)',
                        style: const TextStyle(
                            fontSize: 15, color: Colors.black54)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Int: ${money(calc.interest)}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        Text('Total: ${money(calc.total)}',
                            style: const TextStyle(
                                fontSize: 14, color: FlowColors.primary)),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE',
                style: TextStyle(fontSize: 17, color: FlowColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    final p = _pledge;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(
            backgroundColor: FlowColors.primary,
            foregroundColor: FlowColors.goldRich,
            title: const Text('Pledge')),
        body: const Center(child: Text('Pledge not found.')),
      );
    }

    final fromDate = DateTime.tryParse(p.pledgeDate) ?? DateTime.now();
    // "today" is the as-of date: the context date when set, else the real today.
    final today = widget.contextDate ?? DateTime.now();
    final actualDays = today.difference(fromDate).inDays;
    final effectiveDays = InterestCalculator.effectiveDays(fromDate, today,
        isRenewalPledge: p.renewalParentId != null);
    final calc = InterestCalculator.calculate(
      principal: p.loanAmount,
      fromDate: fromDate,
      toDate: today,
      ratePercent: p.interestRate,
      isRenewalPledge: p.renewalParentId != null,
    );
    final asOfLabel = widget.contextDate != null
        ? 'Interest as of ${formatDmy(widget.contextDate!)}'
        : 'Interest as of Today';

    final totalGross = _items.fold<double>(0, (s, it) => s + it.grossWeight);
    final totalNet = _items.fold<double>(0, (s, it) => s + it.netWeight);
    final goldPhotos = _goldPhotoPaths;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Text('Pledge ${p.pledgeNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print Pledge Form',
            onPressed: () => showPledgeFormPrintOptions(context,
                pledgeId: p.id!, pledgeNo: p.pledgeNumber),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).withNavBarInset(context),
        children: [
          if (widget.contextDate != null)
            ContextDateBanner(
                label: 'Context Date', date: widget.contextDate!),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  StatusBadge(
                      text: p.status == 'open' ? 'ACTIVE' : p.status.toUpperCase(),
                      color: p.status == 'open'
                          ? FlowColors.green
                          : FlowColors.medText,
                      backgroundColor: p.status == 'open'
                          ? FlowColors.greenLight
                          : const Color(0xFFEEEEEE),
                      borderColor: p.status == 'open'
                          ? FlowColors.green
                          : FlowColors.medText),
                  if (p.source == 'migrated') ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: FlowColors.goldLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Migrated',
                          style: TextStyle(
                              fontSize: 13,
                              color: FlowColors.gold,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
              Text('$actualDays days elapsed',
                  style: const TextStyle(color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 14),

          // Pledge details
          FlowCard(
            header: 'Pledge Details',
            child: Column(
              children: [
                DetailRow(label: 'Pledge No.', value: p.pledgeNumber),
                DetailRow(
                    label: 'Pledge Date', value: isoToDisplay(p.pledgeDate)),
                DetailRow(label: 'Loan Amount', value: money(p.loanAmount)),
                DetailRow(
                    label: 'Interest Rate',
                    value: '${p.interestRate.toStringAsFixed(0)}% p.a.',
                    isLast: true),
              ],
            ),
          ),

          // Notes (e.g. items released during a Part Release)
          if (p.notes?.isNotEmpty == true)
            FlowCard(
              header: 'Notes',
              child: Text(p.notes!, style: const TextStyle(fontSize: 15)),
            ),

          // Item Details (one card per item)
          for (int i = 0; i < _items.length; i++)
            FlowCard(
              header: _items.length == 1 ? 'Item Details' : 'Item List ${i + 1}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_items[i].itemType.isNotEmpty &&
                      _items[i].itemType != 'Other')
                    DetailRow(
                        label: 'Item Types', value: _items[i].itemType),
                  DetailRow(
                      label: 'Total Quantity', value: '${_items[i].quantity}'),
                  if (_items[i].grossWeight > 0)
                    DetailRow(
                        label: 'Gross Weight',
                        value:
                            '${_items[i].grossWeight.toStringAsFixed(2)} g'),
                  if (_items[i].netWeight > 0)
                    DetailRow(
                        label: 'Net Weight',
                        value:
                            '${_items[i].netWeight.toStringAsFixed(2)} g'),
                  if (_items[i].purity.isNotEmpty)
                    DetailRow(label: 'Purity', value: _items[i].purity),
                  if (_items[i].notes?.isNotEmpty == true)
                    DetailRow(
                        label: 'Notes',
                        value: _items[i].notes!,
                        isLast: true),
                ],
              ),
            ),

          // Gold Details — totals + photos (photos stored at pledge level)
          FlowCard(
            header: 'Gold Details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DetailRow(
                    label: 'Total Gross Weight',
                    value: '${totalGross.toStringAsFixed(2)} g'),
                DetailRow(
                    label: 'Total Net Weight',
                    value: '${totalNet.toStringAsFixed(2)} g',
                    isLast: goldPhotos.isEmpty && _pledgeDayLocked),
                if (goldPhotos.isNotEmpty || !_pledgeDayLocked) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ...goldPhotos.map((ph) => RestorablePhotoThumb(
                            localPath: ph,
                            width: 100,
                            height: 80,
                            onView: (p) => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      _PhotoViewScreen(file: File(p))),
                            ),
                          )),
                      if (!_pledgeDayLocked)
                        RestrictedAction(
                          child: _AddPhotoButton(
                            onTap: _addingPhoto ? null : _addGoldPhoto,
                            loading: _addingPhoto,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Customer Details
          () {
            final idProofPhotos = _idProofPhotoPaths;
            final addr = _customer != null
                ? formatCustomerAddress(
                    address: _customer!['address'] as String?,
                    district: _customer!['district'] as String?,
                    state: _customer!['state'] as String?,
                    pinCode: _customer!['pin_code'] as String?,
                  )
                : '';
            final idType =
                (_customer?['id_proof_type'] as String?) ?? '';
            final idNum =
                (_customer?['id_proof_number'] as String?) ?? '';
            return FlowCard(
              header: 'Customer Details',
              onTap: _customer != null
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomerDetailScreen(
                            customerId: _customer!['id'] as int,
                          ),
                        ),
                      )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_customer != null) ...[
                    if ((_customer!['name'] as String?)?.isNotEmpty == true)
                      DetailRow(
                          label: 'Name',
                          value: _customer!['name'] as String),
                    if ((_customer!['phone'] as String?)?.isNotEmpty == true)
                      DetailRow(
                          label: 'Phone',
                          value: _customer!['phone'] as String),
                    if (addr.isNotEmpty)
                      DetailRow(label: 'Address', value: addr),
                    if (idType.isNotEmpty && idType != 'None')
                      DetailRow(
                          label: 'ID Proof',
                          value: idNum.isNotEmpty
                              ? '$idType  •  $idNum'
                              : idType),
                    if (idProofPhotos.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: idProofPhotos
                              .map((ph) => RestorablePhotoThumb(
                                    localPath: ph,
                                    width: 100,
                                    height: 80,
                                    label: 'ID Proof',
                                    onView: (p) => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              _PhotoViewScreen(file: File(p))),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                  ] else ...[
                    if (p.customerName.isNotEmpty)
                      DetailRow(label: 'Name', value: p.customerName),
                    if (p.customerPhone?.isNotEmpty == true)
                      DetailRow(label: 'Phone', value: p.customerPhone!),
                    if (p.customerAddress?.isNotEmpty == true)
                      DetailRow(
                          label: 'Address',
                          value: p.customerAddress!,
                          isLast: true),
                  ],
                ],
              ),
            );
          }(),

          // Renewal chain (show if chain has multiple entries)
          if (_chain.length > 1)
            FlowCard(
              backgroundColor: FlowColors.accent,
              header: 'Renewal Chain',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < _chain.length; i++) ...[
                          if (i > 0)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(Icons.arrow_forward,
                                  size: 14, color: Colors.black38),
                            ),
                          GestureDetector(
                            onTap: _chain[i].isCurrent
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            _chain[i].status == 'open'
                                                ? PledgeDetailScreen(
                                                    pledgeId:
                                                        _chain[i].pledgeId)
                                                : ClosedPledgeDetailScreen(
                                                    pledgeId:
                                                        _chain[i].pledgeId),
                                      ),
                                    ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _chain[i].isCurrent
                                    ? FlowColors.primary
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _chain[i].isCurrent
                                      ? FlowColors.primary
                                      : FlowColors.primaryLight,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                '#${_chain[i].pledgeNumber}',
                                style: TextStyle(
                                  color: _chain[i].isCurrent
                                      ? FlowColors.textOnNavySmall
                                      : FlowColors.primary,
                                  fontWeight: _chain[i].isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

          if (p.status == 'open') ...[
            FlowCard(
              backgroundColor: FlowColors.greenLight,
              header: asOfLabel,
              child: Column(
                children: [
                  DetailRow(
                      label: 'Days (effective)',
                      value: '$effectiveDays days'),
                  DetailRow(
                      label: 'Interest Due',
                      value: money(calc.interest)),
                  DetailRow(
                      label: 'Total Due',
                      value: money(p.loanAmount + calc.interest),
                      isLast: true),
                ],
              ),
            ),

            OutlinedButton.icon(
              onPressed: () => _showInterestPreview(p, fromDate, today),
              icon: const Icon(Icons.calculate),
              label: const Text('VIEW INTEREST PREVIEW',
                  style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),

            if (!widget.hideActions) ...[
              RestrictedAction(
                child: SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: () => _goClose(p),
                  icon: const Icon(Icons.check_circle, size: 26),
                  label: const Text('CLOSE PLEDGE',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlowColors.primary,
                    foregroundColor: FlowColors.textOnNavyLarge,
                    side: const BorderSide(color: FlowColors.borderOnNavy, width: 0.8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
              ),
              ),
              const SizedBox(height: 12),
              RestrictedAction(
                child: SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: () => _goRenew(p),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlowColors.primary,
                    foregroundColor: FlowColors.textOnNavyLarge,
                    side: const BorderSide(color: FlowColors.borderOnNavy, width: 0.8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.autorenew, size: 26),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: const Text('RENEW / PART PAYMENT/ TOP-UP',
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ),
            ],
            if (widget.editEntryContext) ...[
              const SizedBox(height: 12),
              RestrictedAction(
                child: SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: () => _goEdit(p),
                  icon: const Icon(Icons.edit_note, size: 26),
                  label: const Text('EDIT PLEDGE',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CMBColors.warningOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
              ),
              ),
            ],
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

}

// ─── Interest Editor Sheet ────────────────────────────────────────────────────

class _InterestEditorSheet extends StatefulWidget {
  const _InterestEditorSheet({
    required this.calculatedInterest,
    required this.currentOverride,
    required this.onApply,
    required this.onReset,
  });

  final double calculatedInterest;
  final double? currentOverride;
  final void Function(double) onApply;
  final void Function() onReset;

  @override
  State<_InterestEditorSheet> createState() => _InterestEditorSheetState();
}

class _InterestEditorSheetState extends State<_InterestEditorSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: (widget.currentOverride ?? widget.calculatedInterest)
          .round()
          .toString(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28)
              .withNavBarInset(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Edit Interest Amount',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Calculated: ${money(widget.calculatedInterest)}',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Interest Amount',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.currentOverride != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onReset();
                        },
                        child: const Text('Reset to Calculated'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: FlowColors.primary,
                          foregroundColor: FlowColors.goldRich),
                      onPressed: () {
                        final v = double.tryParse(_ctrl.text) ?? 0;
                        Navigator.pop(context);
                        widget.onApply(v);
                      },
                      child: const Text('Apply'),
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

// ─── Chain Entry ──────────────────────────────────────────────────────────────

class _ChainEntry {
  const _ChainEntry(this.pledgeNumber, this.pledgeId, this.isCurrent, this.status);
  final String pledgeNumber;
  final int pledgeId;
  final bool isCurrent;
  final String status;
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

// ─── Closed Pledge Detail Screen ──────────────────────────────────────────────

class ClosedPledgeDetailScreen extends StatefulWidget {
  const ClosedPledgeDetailScreen({super.key, required this.pledgeId});
  final int pledgeId;

  @override
  State<ClosedPledgeDetailScreen> createState() =>
      _ClosedPledgeDetailScreenState();
}

class _ClosedPledgeDetailScreenState extends State<ClosedPledgeDetailScreen> {
  PledgeModel? _pledge;
  List<PledgeItemModel> _items = [];
  List<PaymentModel> _payments = [];
  List<BankAccount> _allAccounts = [];
  Map<String, dynamic>? _customer;
  List<_ChainEntry> _chain = [];
  bool _loading = true;
  List<String> _goldPhotoPaths = [];
  List<String> _idProofPhotoPaths = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pledge =
        await PledgeRepository.instance.getPledgeById(widget.pledgeId);
    if (pledge == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final items =
        await PledgeRepository.instance.getItemsForPledge(widget.pledgeId);
    final payments =
        await PledgeRepository.instance.getPaymentsForPledge(widget.pledgeId);

    Map<String, dynamic>? customer;
    if (pledge.customerId != null) {
      customer =
          await PledgeRepository.instance.getCustomerById(pledge.customerId!);
    }

    final chain = await _buildChain(pledge);
    final allAccounts = await BankAccountRepository.instance.getAll();

    final goldPhotos = await PhotoSyncRepository.instance
        .getByPledge(pledge.id!, PhotoType.gold);
    final idProofPhotos = pledge.customerId != null
        ? await PhotoSyncRepository.instance.getByCustomer(pledge.customerId!)
        : <PhotoSyncEntry>[];

    if (mounted) {
      setState(() {
        _pledge = pledge;
        _items = items;
        _payments = payments;
        _allAccounts = allAccounts;
        _customer = customer;
        _chain = chain;
        _goldPhotoPaths = goldPhotos.map((e) => e.localPath).toList();
        _idProofPhotoPaths = idProofPhotos.map((e) => e.localPath).toList();
        _loading = false;
      });
    }
  }

  String _bankLabel(int? id) {
    if (id == null) return 'Bank';
    final name = _allAccounts
        .cast<BankAccount?>()
        .firstWhere((a) => a?.id == id, orElse: () => null)
        ?.name;
    return name != null ? 'Bank ($name)' : 'Bank';
  }

  Future<List<_ChainEntry>> _buildChain(PledgeModel p) async {
    final chain = <_ChainEntry>[];
    PledgeModel? cur = p;
    while (cur != null) {
      chain.insert(
          0, _ChainEntry(cur.pledgeNumber, cur.id!, cur.id == p.id, cur.status));
      if (cur.renewalParentId == null) break;
      cur = await PledgeRepository.instance.getPledgeById(cur.renewalParentId!);
    }
    int limit = 10;
    PledgeModel? succ =
        await PledgeRepository.instance.getSuccessorPledge(p.id!);
    while (succ != null && limit-- > 0) {
      chain.add(_ChainEntry(succ.pledgeNumber, succ.id!, false, succ.status));
      succ = await PledgeRepository.instance.getSuccessorPledge(succ.id!);
    }
    return chain;
  }

  String _statusLabel(String? renewType) {
    switch (renewType) {
      case RenewType.renewed:
        return 'RENEWED';
      case RenewType.partPayment:
        return 'PART PAYMENT';
      case RenewType.loanIncrease:
        return 'LOAN TOP-UP';
      default:
        return 'RELEASED';
    }
  }

  Color _statusColor(String? renewType) =>
      renewType == null ? FlowColors.red : FlowColors.orange;

  Color _statusBg(String? renewType) =>
      renewType == null ? FlowColors.redLight : FlowColors.orangeLight;

  String _paymentTypeLabel(String type) {
    switch (type) {
      case PaymentType.loanDisbursed:
        return 'Loan Disbursed';
      case PaymentType.loanFullClosure:
        return 'Closure';
      case PaymentType.renewalInterestPaid:
        return 'Renewal Interest';
      case PaymentType.partPaymentReceived:
        return 'Part Payment';
      case PaymentType.loanIncreaseDisbursed:
        return 'Loan Top-Up';
      case PaymentType.expense:
        return 'Expense';
      case PaymentType.adjustment:
        return 'Adjustment';
      default:
        return type;
    }
  }

  String _paymentModeLabel(PaymentModel p) {
    if (p.cashAmount > 0 && p.bankAmount > 0) return 'SPLIT';
    if (p.bankAmount > 0) return 'BANK';
    return 'CASH';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          backgroundColor: FlowColors.bg,
          body: Center(child: CircularProgressIndicator()));
    }
    final p = _pledge;
    if (p == null) {
      return Scaffold(
        backgroundColor: FlowColors.bg,
        appBar: AppBar(
            backgroundColor: FlowColors.primary,
            foregroundColor: FlowColors.goldRich,
            title: const Text('Pledge')),
        body: const Center(child: Text('Pledge not found.')),
      );
    }

    final daysHeld = p.closureDate != null && p.pledgeDate.isNotEmpty
        ? (DateTime.tryParse(p.closureDate!)
                    ?.difference(
                        DateTime.tryParse(p.pledgeDate) ?? DateTime.now())
                    .inDays ??
                0)
            .abs()
        : 0;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Text('Pledge ${p.pledgeNumber}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).withNavBarInset(context),
        children: [
          // Status row
          Row(
            children: [
              StatusBadge(
                text: _statusLabel(p.renewType),
                color: _statusColor(p.renewType),
                backgroundColor: _statusBg(p.renewType),
                borderColor: _statusColor(p.renewType),
              ),
              if (p.status == 'closed') ...[
                const SizedBox(width: 8),
                StatusBadge(
                  text: 'CLOSED',
                  color: FlowColors.red,
                  backgroundColor: FlowColors.redLight,
                  borderColor: FlowColors.red,
                ),
              ],
              if (p.source == 'migrated') ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: FlowColors.goldLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Migrated',
                      style: TextStyle(
                          fontSize: 13,
                          color: FlowColors.gold,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Pledge Details
          FlowCard(
            header: 'Pledge Details',
            child: Column(
              children: [
                DetailRow(label: 'Pledge No.', value: p.pledgeNumber),
                DetailRow(
                    label: 'Pledge Date', value: isoToDisplay(p.pledgeDate)),
                DetailRow(
                    label: 'Closure Date',
                    value: isoToDisplay(p.closureDate)),
                if (p.renewType != null)
                  DetailRow(
                      label: 'Type',
                      value: renewalLabel(p.renewType, p.renewSubtype)),
                DetailRow(
                    label: 'Days Held',
                    value: '$daysHeld days',
                    isLast: true),
              ],
            ),
          ),

          // Notes (e.g. items released during a Part Release)
          if (p.notes?.isNotEmpty == true)
            FlowCard(
              header: 'Notes',
              child: Text(p.notes!, style: const TextStyle(fontSize: 15)),
            ),

          // Financial Summary
          FlowCard(
            backgroundColor: FlowColors.accent,
            header: 'Financial Summary',
            child: Column(
              children: [
                DetailRow(label: 'Loan Amount', value: money(p.loanAmount)),
                DetailRow(
                    label: 'Interest Rate',
                    value: '${p.interestRate.toStringAsFixed(0)}% p.a.'),
                DetailRow(
                    label: 'Interest Paid',
                    value: money(p.totalInterestPaid)),
                DetailRow(
                    label: 'Total Collected',
                    value: money(p.totalAmountCollected),
                    isLast: true),
              ],
            ),
          ),

          // Gold Details
          if (p.grossWeight > 0 ||
              p.netWeight > 0 ||
              p.pledgeRate > 0 ||
              p.purity.isNotEmpty)
            FlowCard(
              header: 'Gold Details',
              child: Column(
                children: [
                  if (p.grossWeight > 0)
                    DetailRow(
                        label: 'Gross Weight',
                        value: '${p.grossWeight.toStringAsFixed(2)} g'),
                  if (p.netWeight > 0)
                    DetailRow(
                        label: 'Net Weight',
                        value: '${p.netWeight.toStringAsFixed(2)} g'),
                  if (p.purity.isNotEmpty)
                    DetailRow(label: 'Purity', value: p.purity),
                  if (p.pledgeRate > 0)
                    DetailRow(
                        label: 'Pledge Rate',
                        value: '${money(p.pledgeRate)}/g'),
                  if (p.actualItemValue > 0)
                    DetailRow(
                        label: 'Item Value',
                        value: money(p.actualItemValue),
                        isLast: true)
                  else
                    DetailRow(
                        label: 'Gold Rate',
                        value:
                            p.goldRate > 0 ? '${money(p.goldRate)}/g' : '—',
                        isLast: true),
                ],
              ),
            ),

          // Customer Details
          if (p.customerName.isNotEmpty || _customer != null)
            FlowCard(
              header: 'Customer Details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.customerName.isNotEmpty)
                    DetailRow(label: 'Name', value: p.customerName),
                  if (p.customerPhone != null && p.customerPhone!.isNotEmpty)
                    DetailRow(label: 'Phone', value: p.customerPhone!),
                  () {
                    final addr = _customer != null
                        ? formatCustomerAddress(
                            address: _customer!['address'] as String?,
                            district: _customer!['district'] as String?,
                            state: _customer!['state'] as String?,
                            pinCode: _customer!['pin_code'] as String?,
                          )
                        : (p.customerAddress ?? '');
                    if (addr.isEmpty) return const SizedBox.shrink();
                    return DetailRow(label: 'Address', value: addr);
                  }(),
                  if (_customer != null) ...[
                    if ((_customer!['id_proof_type'] as String?)?.isNotEmpty ==
                        true)
                      DetailRow(
                          label: 'ID Proof Type',
                          value: _customer!['id_proof_type'] as String),
                    if ((_customer!['id_proof_number'] as String?)?.isNotEmpty ==
                        true)
                      DetailRow(
                          label: 'ID Proof No.',
                          value: _customer!['id_proof_number'] as String,
                          isLast: true),
                    if (_idProofPhotoPaths.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ID Proof Photos',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _idProofPhotoPaths
                                  .map((path) => RestorablePhotoThumb(
                                        localPath: path,
                                        width: 100,
                                        height: 80,
                                        onView: (resolved) => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) => _PhotoViewScreen(
                                                  file: File(resolved))),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),

          // Item Details
          if (_items.isNotEmpty)
            for (int i = 0; i < _items.length; i++)
              FlowCard(
                header: _items.length == 1
                    ? 'Item Details'
                    : 'Item List ${i + 1} of ${_items.length}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_items[i].itemType.isNotEmpty &&
                        _items[i].itemType != 'Other')
                      DetailRow(
                          label: 'Item Types', value: _items[i].itemType),
                    DetailRow(
                        label: 'Total Quantity',
                        value: '${_items[i].quantity}'),
                    if (_items[i].grossWeight > 0)
                      DetailRow(
                          label: 'Gross Weight',
                          value:
                              '${_items[i].grossWeight.toStringAsFixed(2)} g'),
                    DetailRow(
                        label: 'Net Weight',
                        value:
                            '${_items[i].netWeight.toStringAsFixed(2)} g'),
                    DetailRow(
                        label: 'Purity',
                        value: _items[i].purity.isEmpty
                            ? 'Not specified'
                            : _items[i].purity),
                    if (_items[i].notes != null && _items[i].notes!.isNotEmpty)
                      DetailRow(
                          label: 'Notes',
                          value: _items[i].notes!,
                          isLast: true),
                  ],
                ),
              ),

          // Gold Photos
          if (_goldPhotoPaths.isNotEmpty)
            FlowCard(
              header: 'Gold Photos',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _goldPhotoPaths
                    .map((ph) => RestorablePhotoThumb(
                          localPath: ph,
                          width: 100,
                          height: 80,
                          onView: (resolved) => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    _PhotoViewScreen(file: File(resolved))),
                          ),
                        ))
                    .toList(),
              ),
            ),

          // Payment Breakdown
          if (_payments.isNotEmpty)
            FlowCard(
              backgroundColor: FlowColors.greenLight,
              borderColor: FlowColors.green,
              child: Column(
                children: [
                  const FlowCardTitle('Payment Breakdown'),
                  for (int i = 0; i < _payments.length; i++) ...[
                    if (i > 0) const Divider(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_paymentTypeLabel(_payments[i].paymentType)} · ${isoToDisplay(_payments[i].paymentDate.length >= 10 ? _payments[i].paymentDate.substring(0, 10) : _payments[i].paymentDate)}',
                        style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(height: 6),
                    DetailRow(
                        label: 'Total', value: money(_payments[i].amount)),
                    if (_payments[i].cashAmount > 0)
                      DetailRow(
                          label: 'Cash',
                          value: money(_payments[i].cashAmount)),
                    if (_payments[i].bankAmount > 0)
                      DetailRow(
                          label: _bankLabel(_payments[i].bankAccountId),
                          value: money(_payments[i].bankAmount)),
                    DetailRow(
                        label: 'Mode',
                        value: _paymentModeLabel(_payments[i]),
                        isLast: i == _payments.length - 1),
                  ],
                ],
              ),
            ),

          // Renewal Chain
          if (_chain.length > 1)
            FlowCard(
              backgroundColor: FlowColors.accent,
              header: 'Renewal Chain',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (int i = 0; i < _chain.length; i++) ...[
                      if (i > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.arrow_forward,
                              size: 14, color: Colors.black38),
                        ),
                      GestureDetector(
                        onTap: _chain[i].isCurrent
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _chain[i].status == 'open'
                                        ? PledgeDetailScreen(
                                            pledgeId: _chain[i].pledgeId)
                                        : ClosedPledgeDetailScreen(
                                            pledgeId: _chain[i].pledgeId),
                                  ),
                                ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _chain[i].isCurrent
                                ? FlowColors.primary
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _chain[i].isCurrent
                                  ? FlowColors.primary
                                  : FlowColors.primaryLight,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            '#${_chain[i].pledgeNumber}',
                            style: TextStyle(
                              color: _chain[i].isCurrent
                                  ? Colors.white
                                  : FlowColors.primary,
                              fontWeight: _chain[i].isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── Add Photo Button ─────────────────────────────────────────────────────────

class _AddPhotoButton extends StatelessWidget {
  const _AddPhotoButton({this.onTap, this.loading = false});
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 80,
        decoration: BoxDecoration(
          border: Border.all(
            color: CMBColors.navy.withValues(alpha: 0.35),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(8),
          color: CMBColors.warmWhite,
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_outlined,
                      color: CMBColors.navy, size: 26),
                  SizedBox(height: 4),
                  Text(
                    'Add Photo',
                    style: TextStyle(
                      fontSize: 11,
                      color: CMBColors.navy,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Close Pledge Screen ──────────────────────────────────────────────────────

class ClosePledgeScreen extends StatefulWidget {
  const ClosePledgeScreen({
    super.key,
    required this.pledge,
    this.contextDate,
    this.initialInterest,
  });
  final PledgeModel pledge;

  /// Backdated closure date. When set, interest is computed up to this date and
  /// all DB writes (closure_date, closed_at, payment_date, gold OUT) use it.
  final DateTime? contextDate;

  /// Pre-set interest override from the detail screen. When null, interest is
  /// calculated fresh from [InterestCalculator].
  final double? initialInterest;

  @override
  State<ClosePledgeScreen> createState() => _ClosePledgeScreenState();
}

class _ClosePledgeScreenState extends State<ClosePledgeScreen> {
  final _payKey = GlobalKey<SharedSplitPaymentWidgetState>();
  bool _isSaving = false;
  String? _donePledgeNo;
  double? _doneTotal;
  List<BankAccount> _bankAccounts = const [];

  late final double _interest;
  late final double _minInterest;
  double? _customInterest;

  @override
  void initState() {
    super.initState();
    final from =
        DateTime.tryParse(widget.pledge.pledgeDate) ?? DateTime.now();
    final calc = InterestCalculator.calculate(
      principal: widget.pledge.loanAmount,
      fromDate: from,
      toDate: widget.contextDate ?? DateTime.now(),
      ratePercent: widget.pledge.interestRate,
      isRenewalPledge: widget.pledge.renewalParentId != null,
    );
    _minInterest = calc.interest;
    _interest = widget.initialInterest ?? calc.interest;
    _loadBankAccounts();
  }

  Future<void> _loadBankAccounts() async {
    final accounts = await BankAccountRepository.instance.getActive();
    if (mounted) setState(() => _bankAccounts = accounts);
  }

  String? get _contextIso =>
      widget.contextDate?.toIso8601String().substring(0, 10);

  Widget _amtRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 15, color: FlowColors.medText)),
        Text(value,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: FlowColors.darkText)),
      ],
    );
  }

  Future<void> _showInterestEditor() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _InterestEditorSheet(
        calculatedInterest: _interest,
        currentOverride: _customInterest,
        onApply: (v) {
          if (v > 0) setState(() => _customInterest = v);
        },
        onReset: () => setState(() => _customInterest = null),
      ),
    );
  }

  Future<void> _confirmClose() async {
    final effectiveInterest = _customInterest ?? _interest;
    final effectiveTotal = widget.pledge.loanAmount + effectiveInterest;

    final payErr = _payKey.currentState?.validate();
    if (payErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(payErr), backgroundColor: Colors.red),
      );
      return;
    }

    // Below-minimum interest warning (non-blocking — staff can override)
    if (effectiveInterest < _minInterest) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            'Interest Below Standard Minimum',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: FlowColors.orange),
          ),
          content: Text(
            'The interest (${money(effectiveInterest)}) is below the standard minimum '
            '(${money(_minInterest)}). Confirm this is a deliberate discount?',
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
      if (!mounted || proceed != true) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                color: FlowColors.primary,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 16),
              child: const Row(
                children: [
                  Icon(Icons.lock, color: FlowColors.goldRich, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Confirm Closure',
                    style: TextStyle(
                      color: FlowColors.goldRich,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            // ── Body ────────────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pledge #${widget.pledge.pledgeNumber}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: FlowColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFEEEEEE)),
                  const SizedBox(height: 12),
                  _amtRow('Principal',
                      money(widget.pledge.loanAmount)),
                  const SizedBox(height: 8),
                  _amtRow('Interest', money(effectiveInterest)),
                  const SizedBox(height: 12),
                  const Divider(
                      height: 1,
                      thickness: 1.5,
                      color: FlowColors.primaryLight),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL DUE',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: FlowColors.medText,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        money(effectiveTotal),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: FlowColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            // ── Buttons ─────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border(
                    top: BorderSide(
                        color: Color(0xFFEEEEEE), width: 1)),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(
                              color: Color(0xFFCCCCCC)),
                        ),
                      ),
                      child: const Text('CANCEL',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          )),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FlowColors.primary,
                        foregroundColor: FlowColors.textOnNavyLarge,
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(
                            color: FlowColors.borderOnNavy,
                            width: 0.8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('CONFIRM CLOSE',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final payState = _payKey.currentState;
      final cashAmt = payState?.cashAmount ?? effectiveTotal;
      final bankAmt = payState?.bankAmount ?? 0;

      await PledgeRepository.instance.closePledge(
        pledgeId: widget.pledge.id!,
        totalInterestPaid: effectiveInterest,
        totalAmountCollected: effectiveTotal,
        cashAmount: cashAmt,
        bankAmount: bankAmt,
        bankAccountId: payState?.bankAccountId,
        contextDate: _contextIso,
      );

      if (mounted) {
        setState(() {
          _donePledgeNo = widget.pledge.pledgeNumber;
          _doneTotal = effectiveTotal;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error closing pledge: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_donePledgeNo != null) {
      return _CloseSuccessScreen(
          pledgeNo: _donePledgeNo!, amount: _doneTotal ?? 0);
    }

    final effectiveInterest = _customInterest ?? _interest;
    final effectiveTotal = widget.pledge.loanAmount + effectiveInterest;
    final isOverridden = _customInterest != null;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Close Pledge'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).withNavBarInset(context),
        children: [
          if (widget.contextDate != null)
            ContextDateBanner(
                label: 'Closure Date', date: widget.contextDate!),
          FlowCard(
            backgroundColor:
                isOverridden ? FlowColors.orangeLight : FlowColors.goldLight,
            header: isOverridden ? 'Closure Summary (Custom)' : 'Closure Summary',
            child: Column(
              children: [
                DetailRow(
                    label: 'Principal',
                    value: money(widget.pledge.loanAmount)),
                RestrictedAction(
                  child: GestureDetector(
                    onTap: _showInterestEditor,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Interest',
                              style: TextStyle(
                                  fontSize: 17, color: FlowColors.medText)),
                          Row(children: [
                            Text(
                              money(effectiveInterest),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isOverridden
                                    ? FlowColors.orange
                                    : FlowColors.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.edit,
                                size: 15,
                                color: isOverridden
                                    ? FlowColors.orange
                                    : Colors.black38),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
                DetailRow(
                    label: 'Total Due',
                    value: money(effectiveTotal),
                    isLast: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const FlowSectionTitle('Payment Mode'),
          SharedSplitPaymentWidget(
            key: _payKey,
            total: effectiveTotal,
            totalLabel: 'Total Due',
            bankAccounts: _bankAccounts,
          ),
          const SizedBox(height: 20),
          RestrictedAction(
            child: SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _confirmClose,
              icon: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: FlowColors.textOnNavyLarge),
                    )
                  : const Icon(Icons.check_circle),
              label: Text(_isSaving ? 'CLOSING…' : 'CONFIRM CLOSURE',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.primary,
                  foregroundColor: FlowColors.textOnNavyLarge,
                  side: const BorderSide(color: FlowColors.borderOnNavy, width: 0.8)),
            ),
          ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

}

// ─── Renewal Flow — Shared Helpers ───────────────────────────────────────────

Widget _pledgeSummaryCard(PledgeModel pledge, double interest, double total) {
  return FlowCard(
    backgroundColor: FlowColors.accent,
    header: 'Current Pledge',
    child: Column(
      children: [
        DetailRow(label: 'Pledge No.', value: '#${pledge.pledgeNumber}'),
        DetailRow(label: 'Date', value: isoToDisplay(pledge.pledgeDate)),
        if (pledge.customerName.isNotEmpty)
          DetailRow(label: 'Customer', value: pledge.customerName),
        DetailRow(label: 'Loan Amount', value: money(pledge.loanAmount)),
        DetailRow(label: 'Interest Today', value: money(interest)),
        DetailRow(label: 'Total Due', value: money(total), isLast: true),
      ],
    ),
  );
}

Widget _subOptionCard({
  required bool selected,
  required String title,
  required String description,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected ? FlowColors.primary : Colors.white,
        border: Border.all(
          color: selected ? FlowColors.goldRich : FlowColors.primary,
          width: selected ? 2 : 1.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: selected ? FlowColors.goldRich : FlowColors.primary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: selected ? FlowColors.goldRich : FlowColors.darkText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected
                        ? FlowColors.goldRich.withValues(alpha: 0.75)
                        : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _renewProceedBtn(VoidCallback onTap) {
  return Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 20),
    child: SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.arrow_forward),
        label: const Text('PROCEED TO SUMMARY',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      ),
    ),
  );
}

// ─── Renew Selection Screen ───────────────────────────────────────────────────

class RenewSelectionScreen extends StatefulWidget {
  const RenewSelectionScreen({
    super.key,
    required this.pledge,
    this.contextDate,
    this.overrideInterest,
  });
  final PledgeModel pledge;

  /// Backdated renewal date. When set, interest is computed up to this date and
  /// all renewal DB writes (old closure, new start, payments, gold) use it.
  final DateTime? contextDate;

  /// Pre-set interest override (currently unused — editing happens on this screen).
  final double? overrideInterest;

  @override
  State<RenewSelectionScreen> createState() => _RenewSelectionScreenState();
}

class _RenewSelectionScreenState extends State<RenewSelectionScreen> {
  late final double _calculatedInterest;
  double? _customInterest;

  @override
  void initState() {
    super.initState();
    final from =
        DateTime.tryParse(widget.pledge.pledgeDate) ?? DateTime.now();
    final calc = InterestCalculator.calculate(
      principal: widget.pledge.loanAmount,
      fromDate: from,
      toDate: widget.contextDate ?? DateTime.now(),
      ratePercent: widget.pledge.interestRate,
      isRenewalPledge: widget.pledge.renewalParentId != null,
    );
    _calculatedInterest = calc.interest;
    _customInterest = widget.overrideInterest;
  }

  Future<void> _showInterestEditor() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _InterestEditorSheet(
        calculatedInterest: _calculatedInterest,
        currentOverride: _customInterest,
        onApply: (v) {
          if (v > 0) setState(() => _customInterest = v);
        },
        onReset: () => setState(() => _customInterest = null),
      ),
    );
  }

  Widget _pledgeSummaryCardEditable(
      PledgeModel pledge, double interest, double total, bool isOverridden) {
    return FlowCard(
      backgroundColor:
          isOverridden ? FlowColors.orangeLight : FlowColors.accent,
      header: isOverridden ? 'Current Pledge (Custom)' : 'Current Pledge',
      child: Column(
        children: [
          DetailRow(label: 'Pledge No.', value: '#${pledge.pledgeNumber}'),
          DetailRow(label: 'Date', value: isoToDisplay(pledge.pledgeDate)),
          if (pledge.customerName.isNotEmpty)
            DetailRow(label: 'Customer', value: pledge.customerName),
          DetailRow(label: 'Loan Amount', value: money(pledge.loanAmount)),
          RestrictedAction(
            child: GestureDetector(
              onTap: _showInterestEditor,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Interest Today',
                        style: TextStyle(
                            fontSize: 17, color: FlowColors.medText)),
                    Row(children: [
                      Text(
                        money(interest),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isOverridden
                              ? FlowColors.orange
                              : FlowColors.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.edit,
                          size: 15,
                          color: isOverridden
                              ? FlowColors.orange
                              : Colors.black38),
                    ]),
                  ],
                ),
              ),
            ),
          ),
          DetailRow(label: 'Total Due', value: money(total), isLast: true),
        ],
      ),
    );
  }

  Widget _navBtn({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: FlowColors.primary,
          side: const BorderSide(color: FlowColors.goldRich, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(double.infinity, 64),
          alignment: Alignment.centerLeft,
        ),
        child: Row(
          children: [
            Icon(icon, color: FlowColors.goldRich, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: FlowColors.goldRich)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13,
                          color: FlowColors.goldRich.withValues(alpha: 0.75))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: FlowColors.goldRich, size: 28),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayInterest = _customInterest ?? _calculatedInterest;
    final displayTotal = widget.pledge.loanAmount + displayInterest;
    final isOverridden = _customInterest != null;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Renew Pledge'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).withNavBarInset(context),
        children: [
          if (widget.contextDate != null)
            ContextDateBanner(
                label: 'Renewal Date', date: widget.contextDate!),
          _pledgeSummaryCardEditable(
              widget.pledge, displayInterest, displayTotal, isOverridden),
          const SizedBox(height: 20),
          _navBtn(
            icon: Icons.currency_rupee,
            title: 'Renew Pledge',
            subtitle: 'Pay interest & renew or capitalise interest',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _RenewPledgeScreen(
                  pledge: widget.pledge,
                  interest: displayInterest,
                  total: displayTotal,
                  contextDate: widget.contextDate,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _navBtn(
            icon: Icons.payments,
            title: 'Part Payment',
            subtitle: 'Make a partial payment on this pledge',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _PartPaymentScreen(
                  pledge: widget.pledge,
                  interest: displayInterest,
                  total: displayTotal,
                  contextDate: widget.contextDate,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _navBtn(
            icon: Icons.trending_up,
            title: 'Loan Top-Up',
            subtitle: 'Increase the loan amount on this pledge',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _IncreaseLoanScreen(
                  pledge: widget.pledge,
                  interest: displayInterest,
                  total: displayTotal,
                  contextDate: widget.contextDate,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Renew Pledge Screen ──────────────────────────────────────────────────────

class _RenewPledgeScreen extends StatefulWidget {
  const _RenewPledgeScreen({
    required this.pledge,
    required this.interest,
    required this.total,
    this.contextDate,
  });
  final PledgeModel pledge;
  final double interest;
  final double total;
  final DateTime? contextDate;

  @override
  State<_RenewPledgeScreen> createState() => __RenewPledgeScreenState();
}

class __RenewPledgeScreenState extends State<_RenewPledgeScreen> {
  String _sub = 'pay';
  late TextEditingController _amtCtrl;
  final _payKey = GlobalKey<SharedSplitPaymentWidgetState>();
  List<BankAccount> _bankAccounts = const [];
  List<PledgeItemModel> _pledgeItems = [];

  @override
  void initState() {
    super.initState();
    _amtCtrl = TextEditingController(
        text: formatIndian(widget.pledge.loanAmount.round().toString()));
    _loadBankAccounts();
    _loadPledgeItems();
  }

  Future<void> _loadBankAccounts() async {
    final accounts = await BankAccountRepository.instance.getActive();
    if (mounted) setState(() => _bankAccounts = accounts);
  }

  Future<void> _loadPledgeItems() async {
    if (widget.pledge.id == null) return;
    final items = await PledgeRepository.instance.getItemsForPledge(widget.pledge.id!);
    if (mounted) setState(() => _pledgeItems = items);
  }

  String _bankLabel(int? id) {
    if (id == null) return 'Bank';
    final match = _bankAccounts.cast<BankAccount?>()
        .firstWhere((a) => a?.id == id, orElse: () => null);
    return match != null ? 'Bank (${match.name})' : 'Bank';
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    super.dispose();
  }

  void _proceed() {
    if (_sub == 'pay') {
      final err = _payKey.currentState?.validate();
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
        return;
      }
    }
    final newAmt = double.tryParse(_amtCtrl.text.replaceAll(',', '')) ??
        widget.pledge.loanAmount;

    final payState = _payKey.currentState;
    final cashAmt = payState?.cashAmount ?? widget.interest;
    final bankAmt = payState?.bankAmount ?? 0;
    final payMode = payState?.mode ?? 'cash';
    final bankAccountId = payState?.bankAccountId;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RenewalSummaryScreen(
          title: 'Renewal Summary',
          highlight: _sub == 'pay'
              ? _SummaryHighlight(
                  'COLLECT ${money(widget.interest)} FROM CUSTOMER',
                  FlowColors.green,
                  Colors.white)
              : const _SummaryHighlight(
                  'NO PAYMENT REQUIRED',
                  Color(0xFFEEEEEE),
                  FlowColors.darkText),
          sections: [
            _SummarySection('Renewal Details', [
              _SR('Renewal Type',
                  _sub == 'pay' ? 'Pay Interest & Renew' : 'Capitalise Interest'),
              _SR('Old Pledge', '#${widget.pledge.pledgeNumber}'),
              _SR('Old Amount', money(widget.pledge.loanAmount)),
              _SR('Interest Accrued', money(widget.interest)),
              _SR('New Pledge Amount', money(newAmt)),
            ]),
            if (_sub == 'pay')
              _SummarySection('Payment Details', [
                _SR('Customer Pays', money(widget.interest)),
                _SR('Payment Mode', payMode == 'bank'
                    ? _bankLabel(bankAccountId).toUpperCase()
                    : payMode.toUpperCase()),
                if (payMode == 'split') ...[
                  _SR('Cash', money(cashAmt)),
                  _SR(_bankLabel(bankAccountId), money(bankAmt)),
                ],
              ]),
            ..._pledgeItems.asMap().entries.map((e) {
              final it = e.value;
              final label = _pledgeItems.length == 1 ? 'Item Details' : 'Item ${e.key + 1}';
              return _SummarySection(label, [
                if (it.itemType != 'Other') _SR('Type', it.itemType),
                _SR('Quantity', '${it.quantity}'),
                if (it.grossWeight > 0)
                  _SR('Gross Weight', '${it.grossWeight.toStringAsFixed(2)} g'),
                if (it.netWeight > 0)
                  _SR('Net Weight', '${it.netWeight.toStringAsFixed(2)} g'),
                if (it.purity.isNotEmpty) _SR('Purity', it.purity),
                if (it.notes != null && it.notes!.isNotEmpty) _SR('Notes', it.notes!),
              ]);
            }),
            _SummarySection('Gold Details', [
              _SR('Total Gross Weight',
                  '${widget.pledge.grossWeight.toStringAsFixed(2)} g'),
              _SR('Total Net Weight',
                  '${widget.pledge.netWeight.toStringAsFixed(2)} g'),
            ]),
            if (widget.pledge.customerName.isNotEmpty)
              _SummarySection('Customer Details', [
                _SR('Name', widget.pledge.customerName),
                if (widget.pledge.customerPhone?.isNotEmpty == true)
                  _SR('Phone', widget.pledge.customerPhone!),
              ]),
          ],
          successTitle: 'Pledge Renewed',
          successMessage: '#${widget.pledge.pledgeNumber} successfully renewed.',
          oldPledgeNo: widget.pledge.pledgeNumber,
          amount: newAmt,
          onAccept: () async {
            final ctxIso =
                widget.contextDate?.toIso8601String().substring(0, 10);
            if (_sub == 'pay') {
              return PledgeRepository.instance.renewPayInterest(
                oldPledgeId: widget.pledge.id!,
                newPrincipal: newAmt,
                interest: widget.interest,
                cashAmount: cashAmt,
                bankAmount: bankAmt,
                bankAccountId: bankAccountId,
                contextDate: ctxIso,
              );
            }
            return PledgeRepository.instance.renewCapitaliseInterest(
              oldPledgeId: widget.pledge.id!,
              newPrincipal: newAmt,
              interest: widget.interest,
              contextDate: ctxIso,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Renew Pledge'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).withNavBarInset(context),
        children: [
          if (widget.contextDate != null)
            ContextDateBanner(
                label: 'Renewal Date', date: widget.contextDate!),
          _pledgeSummaryCard(widget.pledge, widget.interest, widget.total),
          const SizedBox(height: 16),
          _subOptionCard(
            selected: _sub == 'pay',
            title: 'Pay Interest & Renew',
            description:
                'Customer pays interest now, new pledge at same or updated principal',
            onTap: () => setState(() {
              _sub = 'pay';
              _amtCtrl.text = formatIndian(widget.pledge.loanAmount.round().toString());
            }),
          ),
          _subOptionCard(
            selected: _sub == 'capitalise',
            title: 'Capitalise Interest',
            description:
                'Interest added to principal, no payment needed from customer',
            onTap: () => setState(() {
              _sub = 'capitalise';
              _amtCtrl.text = formatIndian(
                  (widget.pledge.loanAmount + widget.interest).round().toString());
            }),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextField(
              controller: _amtCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [IndianNumberFormatter()],
              style: const TextStyle(fontSize: 18),
              decoration:
                  const InputDecoration(labelText: 'New Pledge Amount (₹)'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_sub == 'pay') ...[
            const FlowSectionTitle('Payment Mode'),
            SharedSplitPaymentWidget(
              key: _payKey,
              total: widget.interest,
              totalLabel: 'Interest to Collect',
              bankAccounts: _bankAccounts,
            ),
          ],
          _renewProceedBtn(_proceed),
        ],
      ),
    );
  }
}

// ─── Part Payment Screen ──────────────────────────────────────────────────────

class _PartPaymentScreen extends StatefulWidget {
  const _PartPaymentScreen({
    required this.pledge,
    required this.interest,
    required this.total,
    this.contextDate,
  });
  final PledgeModel pledge;
  final double interest;
  final double total;
  final DateTime? contextDate;

  @override
  State<_PartPaymentScreen> createState() => __PartPaymentScreenState();
}

class __PartPaymentScreenState extends State<_PartPaymentScreen> {
  String _sub = 'separate';
  final _amtCtrl = TextEditingController();
  final _payKey = GlobalKey<SharedSplitPaymentWidgetState>();
  List<BankAccount> _bankAccounts = const [];
  List<PledgeItemModel> _pledgeItems = [];
  bool _releaseItems = false;
  final _itemReleaseKey = GlobalKey<SharedItemDetailsStepState>();
  Map<String, ({double? goldRate, double pledgeRate})> _purityRates = {};

  double get _ppAmt => double.tryParse(_amtCtrl.text.replaceAll(',', '')) ?? 0;
  double get _ppPrincipalPaid => _sub == 'separate'
      ? _ppAmt
      : (_ppAmt - widget.interest).clamp(0.0, double.infinity);
  double get _ppTotalPay =>
      _sub == 'separate' ? _ppAmt + widget.interest : _ppAmt;
  double get _ppNewAmt {
    if (_sub == 'fixed') {
      return (widget.pledge.loanAmount + widget.interest - _ppAmt)
          .clamp(0.0, double.infinity);
    }
    return (widget.pledge.loanAmount - _ppPrincipalPaid)
        .clamp(0.0, double.infinity);
  }

  @override
  void initState() {
    super.initState();
    _loadBankAccounts();
    _loadPledgeItems();
    _loadPurityRates();
  }

  Future<void> _loadBankAccounts() async {
    final accounts = await BankAccountRepository.instance.getActive();
    if (mounted) setState(() => _bankAccounts = accounts);
  }

  Future<void> _loadPledgeItems() async {
    if (widget.pledge.id == null) return;
    final items = await PledgeRepository.instance.getItemsForPledge(widget.pledge.id!);
    if (mounted) setState(() => _pledgeItems = items);
  }

  /// Current gold/pledge rate per active purity name, for the item-release
  /// step's live "Item Value" display — same lookup as new-pledge item entry.
  Future<void> _loadPurityRates() async {
    final purities = await PurityTypesRepository.instance.getAllPurityTypes();
    final ratesByPurityId =
        await GoldRatesRepository.instance.getCurrentRatesByPurity();
    final rates = {
      for (final p in purities)
        if (p.isActive && ratesByPurityId[p.id] != null)
          p.name: ratesByPurityId[p.id]!,
    };
    if (mounted) setState(() => _purityRates = rates);
  }

  /// Converts an existing pledge item to the shared item-editor's data shape,
  /// preserving its rate/value snapshot.
  ItemEntryData _toEntryData(PledgeItemModel it) => ItemEntryData(
        itemType: it.itemType,
        grossWeight: it.grossWeight,
        netWeight: it.netWeight,
        quantity: it.quantity,
        notes: it.notes,
        purity: it.purity.isEmpty ? null : it.purity,
        goldRate: it.goldRate > 0 ? it.goldRate : null,
        pledgeRate: it.pledgeRate > 0 ? it.pledgeRate : null,
        itemValue: it.itemValue > 0 ? it.itemValue : null,
      );

  /// Converts an edited/kept item back to a [PledgeItemModel] for the new
  /// pledge. `pledgeId`/`createdAt` are placeholders the repository
  /// overwrites on insert.
  PledgeItemModel _toPledgeItem(ItemEntryData e) => PledgeItemModel(
        pledgeId: widget.pledge.id!,
        itemType: e.itemType,
        quantity: e.quantity,
        grossWeight: e.grossWeight,
        netWeight: e.netWeight,
        purity: e.purity ?? '',
        pledgeRate: e.pledgeRate ?? 0,
        goldRate: e.goldRate ?? 0,
        itemValue: e.itemValue ?? 0,
        notes: e.notes,
        createdAt: DateTime.now().toIso8601String(),
      );

  String _bankLabel(int? id) {
    if (id == null) return 'Bank';
    final match = _bankAccounts.cast<BankAccount?>()
        .firstWhere((a) => a?.id == id, orElse: () => null);
    return match != null ? 'Bank (${match.name})' : 'Bank';
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red));

  /// Builds the auto-generated note describing released items, one line per
  /// item, e.g. "Necklace released (12.50 g)".
  String _buildReleaseNote(List<ItemEntryData> released) {
    final lines = released
        .map((it) =>
            '${it.itemType} released (${it.netWeight.toStringAsFixed(2)} g)')
        .join('\n');
    return 'Items released to customer:\n$lines';
  }

  void _proceed() {
    if (_ppAmt <= 0) { _snack('Enter a payment amount'); return; }
    if (_ppNewAmt <= 0) { _snack('Resulting new pledge amount cannot be zero'); return; }
    final err = _payKey.currentState?.validate();
    if (err != null) { _snack(err); return; }

    List<PledgeItemModel>? keptItems;
    List<ItemEntryData>? releasedItems;
    String? releaseNote;
    if (_releaseItems) {
      final itemState = _itemReleaseKey.currentState;
      final itemErr = itemState?.validate();
      if (itemErr != null) { _snack(itemErr); return; }
      keptItems = itemState?.getData().items.map(_toPledgeItem).toList();
      releasedItems = itemState?.getRemovedItems();
      if (releasedItems != null && releasedItems.isNotEmpty) {
        releaseNote = _buildReleaseNote(releasedItems);
      }
    }

    final payState = _payKey.currentState;
    final cashAmt = payState?.cashAmount ?? _ppTotalPay;
    final bankAmt = payState?.bankAmount ?? 0;
    final payMode = payState?.mode ?? 'cash';
    final bankAccountId = payState?.bankAccountId;
    final intPaid =
        _sub == 'separate' ? widget.interest : _ppAmt.clamp(0.0, widget.interest);
    final unpaidInt = (_sub == 'fixed' && _ppAmt < widget.interest)
        ? widget.interest - _ppAmt
        : 0.0;
    final ppNewAmt = _ppNewAmt;
    final ppTotalPay = _ppTotalPay;
    final ppPrincipalPaid = _ppPrincipalPaid;
    final ppAmt = _ppAmt;
    final newPledgeGross = keptItems != null
        ? keptItems.fold(0.0, (s, i) => s + i.grossWeight)
        : widget.pledge.grossWeight;
    final newPledgeNet = keptItems != null
        ? keptItems.fold(0.0, (s, i) => s + i.netWeight)
        : widget.pledge.netWeight;
    final displayItems = keptItems ?? _pledgeItems;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RenewalSummaryScreen(
          title: 'Part Payment Summary',
          highlight: _SummaryHighlight(
              'COLLECT ${money(ppTotalPay)} FROM CUSTOMER',
              FlowColors.green,
              Colors.white),
          sections: [
            _SummarySection('Renewal Details', [
              _SR('Old Pledge', '#${widget.pledge.pledgeNumber}'),
              _SR('Original Amount', money(widget.pledge.loanAmount)),
              _SR('Interest Accrued', money(widget.interest)),
              _SR('Amount Paid', money(ppTotalPay)),
              _SR('Paid Towards Interest', money(intPaid)),
              if (ppPrincipalPaid > 0)
                _SR('Paid Towards Principal', money(ppPrincipalPaid)),
              if (unpaidInt > 0)
                _SR('Unpaid Interest Added to Principal', money(unpaidInt)),
              _SR('New Pledge Amount', money(ppNewAmt)),
            ]),
            _SummarySection('Payment Details', [
              _SR('Total Collected', money(ppTotalPay)),
              _SR('Payment Mode', payMode == 'bank'
                  ? _bankLabel(bankAccountId).toUpperCase()
                  : payMode.toUpperCase()),
              if (payMode == 'split') ...[
                _SR('Cash', money(cashAmt)),
                _SR(_bankLabel(bankAccountId), money(bankAmt)),
              ],
            ]),
            ...displayItems.asMap().entries.map((e) {
              final it = e.value;
              final label = displayItems.length == 1 ? 'Item Details' : 'Item ${e.key + 1}';
              return _SummarySection(label, [
                if (it.itemType != 'Other') _SR('Type', it.itemType),
                _SR('Quantity', '${it.quantity}'),
                if (it.grossWeight > 0)
                  _SR('Gross Weight', '${it.grossWeight.toStringAsFixed(2)} g'),
                if (it.netWeight > 0)
                  _SR('Net Weight', '${it.netWeight.toStringAsFixed(2)} g'),
                if (it.purity.isNotEmpty) _SR('Purity', it.purity),
                if (it.notes != null && it.notes!.isNotEmpty) _SR('Notes', it.notes!),
              ]);
            }),
            if (releasedItems != null && releasedItems.isNotEmpty)
              _SummarySection('Items Released to Customer', [
                for (final it in releasedItems)
                  _SR(it.itemType, '${it.netWeight.toStringAsFixed(2)} g'),
              ]),
            _SummarySection('Gold Details', [
              _SR('Total Gross Weight', '${newPledgeGross.toStringAsFixed(2)} g'),
              _SR('Total Net Weight', '${newPledgeNet.toStringAsFixed(2)} g'),
            ]),
            if (widget.pledge.customerName.isNotEmpty)
              _SummarySection('Customer Details', [
                _SR('Name', widget.pledge.customerName),
                if (widget.pledge.customerPhone?.isNotEmpty == true)
                  _SR('Phone', widget.pledge.customerPhone!),
              ]),
          ],
          successTitle: 'Part Payment Done',
          successMessage: 'Paid ${money(ppTotalPay)}. New pledge (${money(ppNewAmt)})',
          oldPledgeNo: widget.pledge.pledgeNumber,
          amount: ppNewAmt,
          onAccept: () async {
            final ctxIso =
                widget.contextDate?.toIso8601String().substring(0, 10);
            if (_sub == 'separate') {
              return PledgeRepository.instance.partPaymentPrincipalAndInterest(
                oldPledgeId: widget.pledge.id!,
                newPrincipal: ppNewAmt,
                interest: widget.interest,
                totalPaid: ppTotalPay,
                cashAmount: cashAmt,
                bankAmount: bankAmt,
                bankAccountId: bankAccountId,
                contextDate: ctxIso,
                keptItems: keptItems,
                notesOverride: releaseNote,
              );
            }
            return PledgeRepository.instance.partPaymentFixedAmount(
              oldPledgeId: widget.pledge.id!,
              newPrincipal: ppNewAmt,
              interest: widget.interest,
              fixedAmount: ppAmt,
              cashAmount: cashAmt,
              bankAmount: bankAmt,
              bankAccountId: bankAccountId,
              contextDate: ctxIso,
              keptItems: keptItems,
              notesOverride: releaseNote,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Part Payment'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).withNavBarInset(context),
        children: [
          if (widget.contextDate != null)
            ContextDateBanner(
                label: 'Renewal Date', date: widget.contextDate!),
          _pledgeSummaryCard(widget.pledge, widget.interest, widget.total),
          const SizedBox(height: 16),
          if (_pledgeItems.isNotEmpty) ...[
            FlowCard(
              child: CheckboxListTile(
                value: _releaseItems,
                onChanged: (v) =>
                    setState(() => _releaseItems = v ?? false),
                title: const Text('Release some items to customer',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Customer takes back one or more items; the new pledge keeps only the rest'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
            if (_releaseItems) ...[
              const FlowSectionTitle('Select Items to Keep'),
              SharedItemDetailsStep(
                key: _itemReleaseKey,
                grossWeight: 0,
                netWeight: 0,
                pledgeNumber: widget.pledge.pledgeNumber,
                showPhotoSection: false,
                purityRates: _purityRates,
                initialData: ItemDetailsData(
                  items: _pledgeItems.map(_toEntryData).toList(),
                  photos: const [],
                ),
              ),
            ],
          ],
          _subOptionCard(
            selected: _sub == 'separate',
            title: 'Pay Principal + Interest',
            description:
                'Customer pays part principal plus interest accrued to today',
            onTap: () => setState(() => _sub = 'separate'),
          ),
          _subOptionCard(
            selected: _sub == 'fixed',
            title: 'Pay Fixed Amount',
            description:
                'Customer pays a fixed total amount, interest deducted first',
            onTap: () => setState(() => _sub = 'fixed'),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextField(
              controller: _amtCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [IndianNumberFormatter()],
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                labelText: _sub == 'separate'
                    ? 'Principal Portion to Pay (₹)'
                    : 'Total Payment Amount (₹)',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_ppAmt > 0) ...[
            FlowCard(
              backgroundColor: FlowColors.greenLight,
              borderColor: FlowColors.green,
              child: Column(
                children: [
                  const FlowCardTitle('Payment Breakdown'),
                  if (_sub == 'separate') ...[
                    DetailRow(
                        label: 'Principal Paid',
                        value: money(_ppPrincipalPaid)),
                    DetailRow(label: 'Interest', value: money(widget.interest)),
                    DetailRow(
                        label: 'Total to Pay', value: money(_ppTotalPay)),
                  ] else ...[
                    DetailRow(label: 'Fixed Total', value: money(_ppAmt)),
                    DetailRow(
                        label: 'Paid Towards Interest',
                        value: money(_ppAmt >= widget.interest
                            ? widget.interest
                            : _ppAmt)),
                    if (_ppAmt >= widget.interest)
                      DetailRow(
                          label: 'Paid Towards Principal',
                          value: money(_ppAmt - widget.interest)),
                    if (_ppAmt < widget.interest)
                      DetailRow(
                          label: 'Unpaid Interest Added to Principal',
                          value: money(widget.interest - _ppAmt),
                          valueColor: FlowColors.red),
                  ],
                  DetailRow(
                      label: 'New Pledge Amount',
                      value: money(_ppNewAmt),
                      valueColor: FlowColors.green,
                      isLast: true),
                ],
              ),
            ),
            const FlowSectionTitle('Payment Mode'),
            SharedSplitPaymentWidget(
              key: _payKey,
              total: _ppTotalPay,
              totalLabel: 'Total to Collect',
              bankAccounts: _bankAccounts,
            ),
          ],
          _renewProceedBtn(_proceed),
        ],
      ),
    );
  }
}

// ─── Increase Loan Screen ─────────────────────────────────────────────────────

class _IncreaseLoanScreen extends StatefulWidget {
  const _IncreaseLoanScreen({
    required this.pledge,
    required this.interest,
    required this.total,
    this.contextDate,
  });
  final PledgeModel pledge;
  final double interest;
  final double total;
  final DateTime? contextDate;

  @override
  State<_IncreaseLoanScreen> createState() => __IncreaseLoanScreenState();
}

class __IncreaseLoanScreenState extends State<_IncreaseLoanScreen> {
  late TextEditingController _amtCtrl;
  String _intSub = 'pay';
  final _payKey = GlobalKey<SharedSplitPaymentWidgetState>();
  // Current gold/pledge rate per purity name, from gold_rates (Prompt 1).
  Map<String, ({double? goldRate, double pledgeRate})> _purityRatesByName = {};
  List<BankAccount> _bankAccounts = const [];
  List<PledgeItemModel> _pledgeItems = [];

  /// Max Possible value per purity: this pledge's items grouped by purity,
  /// net weight summed within each group, each group valued at that purity's
  /// own current pledge rate (same rate lookup as before — just scoped per
  /// purity instead of applied once globally).
  List<({String purity, double netWeight, double rate, double value})>
      get _purityBreakdown {
    final netWeightByPurity = <String, double>{};
    for (final item in _pledgeItems) {
      final purity = item.purity.isNotEmpty ? item.purity : 'Unspecified';
      netWeightByPurity[purity] =
          (netWeightByPurity[purity] ?? 0) + item.netWeight;
    }
    return netWeightByPurity.entries.map((e) {
      final rate = _purityRatesByName[e.key]?.pledgeRate ?? 0;
      return (purity: e.key, netWeight: e.value, rate: rate, value: e.value * rate);
    }).toList();
  }

  double get _maxPossible =>
      _purityBreakdown.fold(0.0, (s, e) => s + e.value);

  double get _ilNewAmt =>
      double.tryParse(_amtCtrl.text.replaceAll(',', '')) ??
      widget.pledge.loanAmount;
  double get _ilFinalAmt =>
      _intSub == 'add' ? _ilNewAmt + widget.interest : _ilNewAmt;
  double get _netDisburse =>
      (_ilFinalAmt - widget.pledge.loanAmount - widget.interest)
          .round()
          .toDouble();

  @override
  void initState() {
    super.initState();
    _amtCtrl = TextEditingController(
        text: formatIndian(widget.pledge.loanAmount.round().toString()));
    _loadPurityRates();
    _loadBankAccounts();
    _loadPledgeItems();
  }

  Future<void> _loadPurityRates() async {
    final purities = await PurityTypesRepository.instance.getAllPurityTypes();
    final ratesByPurityId =
        await GoldRatesRepository.instance.getCurrentRatesByPurity();
    final map = {
      for (final p in purities)
        if (p.isActive && ratesByPurityId[p.id] != null)
          p.name: ratesByPurityId[p.id]!,
    };
    if (mounted) setState(() => _purityRatesByName = map);
  }

  Future<void> _loadBankAccounts() async {
    final accounts = await BankAccountRepository.instance.getActive();
    if (mounted) setState(() => _bankAccounts = accounts);
  }

  Future<void> _loadPledgeItems() async {
    if (widget.pledge.id == null) return;
    final items = await PledgeRepository.instance.getItemsForPledge(widget.pledge.id!);
    if (mounted) setState(() => _pledgeItems = items);
  }

  String _bankLabel(int? id) {
    if (id == null) return 'Bank';
    final match = _bankAccounts.cast<BankAccount?>()
        .firstWhere((a) => a?.id == id, orElse: () => null);
    return match != null ? 'Bank (${match.name})' : 'Bank';
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red));

  void _proceed() {
    if (_ilNewAmt <= widget.pledge.loanAmount) {
      _snack(
          'New amount must be higher than current ${money(widget.pledge.loanAmount)}');
      return;
    }
    if (_intSub == 'pay' &&
        _ilNewAmt <= widget.pledge.loanAmount + widget.interest) {
      _snack(
          'New loan amount must be greater than ${money(widget.pledge.loanAmount + widget.interest)} (principal + interest due)');
      return;
    }
    final nd = _netDisburse;
    if (nd > 0) {
      final err = _payKey.currentState?.validate();
      if (err != null) { _snack(err); return; }
    }

    final payState = _payKey.currentState;
    final cashAmt = nd > 0 ? (payState?.cashAmount ?? nd) : 0.0;
    final bankAmt = nd > 0 ? (payState?.bankAmount ?? 0) : 0.0;
    final payMode = nd > 0 ? (payState?.mode ?? 'cash') : 'cash';
    final bankAccountId = nd > 0 ? payState?.bankAccountId : null;
    final ilFinal = _ilFinalAmt;
    final ilNewAmt = _ilNewAmt;
    final intSub = _intSub;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RenewalSummaryScreen(
          title: 'Loan Top-Up Summary',
          highlight: nd > 0
              ? _SummaryHighlight(
                  'PAY ${money(nd)} TO CUSTOMER', FlowColors.red, Colors.white)
              : const _SummaryHighlight(
                  'NO PAYMENT REQUIRED',
                  Color(0xFFEEEEEE),
                  FlowColors.darkText),
          sections: [
            _SummarySection('Renewal Details', [
              _SR('Old Pledge', '#${widget.pledge.pledgeNumber}'),
              _SR('Old Loan Amount', money(widget.pledge.loanAmount)),
              _SR('New Loan Amount', money(ilNewAmt)),
              _SR('Interest Accrued', money(widget.interest)),
              if (intSub == 'add')
                _SR('Interest Added to Principal', money(widget.interest))
              else
                _SR('Interest Deducted from Disbursal', money(widget.interest)),
              _SR('New Pledge Principal', money(ilFinal)),
              if (nd > 0) _SR('Cash to Disburse', money(nd)),
            ]),
            if (nd > 0)
              _SummarySection('Payment Details', [
                _SR('Amount to Give Customer', money(nd)),
                _SR('Payment Mode', payMode == 'bank'
                    ? _bankLabel(bankAccountId).toUpperCase()
                    : payMode.toUpperCase()),
                if (payMode == 'split') ...[
                  _SR('Cash', money(cashAmt)),
                  _SR(_bankLabel(bankAccountId), money(bankAmt)),
                ],
              ]),
            ..._pledgeItems.asMap().entries.map((e) {
              final it = e.value;
              final label = _pledgeItems.length == 1 ? 'Item Details' : 'Item ${e.key + 1}';
              return _SummarySection(label, [
                if (it.itemType != 'Other') _SR('Type', it.itemType),
                _SR('Quantity', '${it.quantity}'),
                if (it.grossWeight > 0)
                  _SR('Gross Weight', '${it.grossWeight.toStringAsFixed(2)} g'),
                if (it.netWeight > 0)
                  _SR('Net Weight', '${it.netWeight.toStringAsFixed(2)} g'),
                if (it.purity.isNotEmpty) _SR('Purity', it.purity),
                if (it.notes != null && it.notes!.isNotEmpty) _SR('Notes', it.notes!),
              ]);
            }),
            _SummarySection('Gold Details', [
              _SR('Total Gross Weight',
                  '${widget.pledge.grossWeight.toStringAsFixed(2)} g'),
              _SR('Total Net Weight',
                  '${widget.pledge.netWeight.toStringAsFixed(2)} g'),
            ]),
            if (widget.pledge.customerName.isNotEmpty)
              _SummarySection('Customer Details', [
                _SR('Name', widget.pledge.customerName),
                if (widget.pledge.customerPhone?.isNotEmpty == true)
                  _SR('Phone', widget.pledge.customerPhone!),
              ]),
          ],
          successTitle: 'Loan Top-Up',
          successMessage: 'New pledge — ${money(ilFinal)}',
          oldPledgeNo: widget.pledge.pledgeNumber,
          amount: ilFinal,
          onAccept: () async {
            final ctxIso =
                widget.contextDate?.toIso8601String().substring(0, 10);
            if (intSub == 'add') {
              return PledgeRepository.instance.increaseLoanInterestCapitalised(
                oldPledgeId: widget.pledge.id!,
                newPrincipal: ilFinal,
                interest: widget.interest,
                extraCashOut: nd,
                cashAmount: cashAmt,
                bankAmount: bankAmt,
                bankAccountId: bankAccountId,
                contextDate: ctxIso,
              );
            }
            return PledgeRepository.instance.increaseLoanInterestNotCapitalised(
              oldPledgeId: widget.pledge.id!,
              newPrincipal: ilFinal,
              interest: widget.interest,
              extraCashOut: nd,
              cashAmount: cashAmt,
              bankAmount: bankAmt,
              bankAccountId: bankAccountId,
              contextDate: ctxIso,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = _purityBreakdown;
    final maxPossible = _maxPossible;
    final nd = _netDisburse;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Loan Top-Up'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).withNavBarInset(context),
        children: [
          if (widget.contextDate != null)
            ContextDateBanner(
                label: 'Renewal Date', date: widget.contextDate!),
          _pledgeSummaryCard(widget.pledge, widget.interest, widget.total),
          if (maxPossible > 0) ...[
            const SizedBox(height: 12),
            FlowCard(
              backgroundColor: FlowColors.goldLight,
              header: 'Max Possible Amount',
              child: Column(
                children: [
                  if (breakdown.length > 1)
                    ...breakdown.map((b) => DetailRow(
                        label:
                            '${b.purity} (${b.netWeight.toStringAsFixed(2)} g × ${money(b.rate)}/g)',
                        value: money(b.value)))
                  else ...[
                    DetailRow(
                        label: 'Net Weight',
                        value: breakdown.isEmpty
                            ? '0.00 g'
                            : '${breakdown.first.netWeight.toStringAsFixed(2)} g'),
                    DetailRow(
                        label: 'Pledge Rate',
                        value:
                            '${money(breakdown.isEmpty ? 0 : breakdown.first.rate)}/g'),
                  ],
                  DetailRow(
                      label: 'Max Possible',
                      value: money(maxPossible),
                      valueColor: FlowColors.gold,
                      isLast: true),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          const FlowSectionTitle('New Loan Amount'),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: TextField(
              controller: _amtCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [IndianNumberFormatter()],
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                labelText:
                    'New Loan Amount (₹)  [current: ${money(widget.pledge.loanAmount)}]',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_intSub == 'pay' &&
              _ilNewAmt > widget.pledge.loanAmount &&
              _ilNewAmt <= widget.pledge.loanAmount + widget.interest) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'Must be greater than ${money(widget.pledge.loanAmount + widget.interest)} (principal + interest due)',
                style: const TextStyle(
                    fontSize: 14, color: FlowColors.red),
              ),
            ),
          ] else
            const SizedBox(height: 14),
          if (_ilNewAmt > 0 && _ilNewAmt > widget.pledge.loanAmount) ...[
            FlowCard(
              backgroundColor: FlowColors.accent,
              child: Column(
                children: [
                  DetailRow(
                      label: 'Requested Increase',
                      value: money(_ilNewAmt - widget.pledge.loanAmount)),
                  if (_intSub == 'add')
                    DetailRow(
                        label: 'Interest Added',
                        value: money(widget.interest)),
                  DetailRow(
                      label: 'Final New Amount',
                      value: money(_ilFinalAmt),
                      valueColor: FlowColors.green,
                      isLast: true),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          const FlowSectionTitle('Interest'),
          _subOptionCard(
            selected: _intSub == 'pay',
            title: 'Pay Interest Now',
            description:
                'Interest deducted from new loan, remaining extra amount given to customer',
            onTap: () => setState(() => _intSub = 'pay'),
          ),
          _subOptionCard(
            selected: _intSub == 'add',
            title: 'Add Interest to Pledge',
            description:
                'Interest added to new pledge amount, full extra amount given to customer',
            onTap: () => setState(() => _intSub = 'add'),
          ),
          if (nd > 0) ...[
            const FlowSectionTitle('Amount to Give Customer'),
            SharedSplitPaymentWidget(
              key: _payKey,
              total: nd,
              totalLabel: 'Amount to give customer',
              bankAccounts: _bankAccounts,
              isMoneyIn: false,
            ),
          ],
          _renewProceedBtn(_proceed),
        ],
      ),
    );
  }
}

// ─── Summary Row Data Class ───────────────────────────────────────────────────

class _SR {
  const _SR(this.label, this.value);
  final String label;
  final String value;
}

// ─── Summary Highlight ────────────────────────────────────────────────────────

class _SummaryHighlight {
  const _SummaryHighlight(this.text, this.bg, this.fg);
  final String text;
  final Color bg;
  final Color fg;
}

// ─── Summary Section ─────────────────────────────────────────────────────────

class _SummarySection {
  const _SummarySection(this.title, this.rows);
  final String title;
  final List<_SR> rows;
}

// ─── Renewal Summary Screen ───────────────────────────────────────────────────

class _RenewalSummaryScreen extends StatefulWidget {
  const _RenewalSummaryScreen({
    required this.title,
    required this.highlight,
    required this.sections,
    required this.onAccept,
    required this.successTitle,
    required this.successMessage,
    this.oldPledgeNo,
    this.amount,
  });

  final String title;
  final _SummaryHighlight highlight;
  final List<_SummarySection> sections;
  final Future<String> Function() onAccept;
  final String successTitle;
  final String successMessage;
  final String? oldPledgeNo;
  final double? amount;

  @override
  State<_RenewalSummaryScreen> createState() => __RenewalSummaryScreenState();
}

class __RenewalSummaryScreenState extends State<_RenewalSummaryScreen> {
  bool _saving = false;

  Future<void> _accept() async {
    setState(() => _saving = true);
    try {
      final newPledgeNo = await widget.onAccept();
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _RenewalSuccessScreen(
              title: widget.successTitle,
              message: widget.successMessage,
              newPledgeNo: newPledgeNo,
              oldPledgeNo: widget.oldPledgeNo,
              amount: widget.amount,
            ),
          ),
        );
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Text(widget.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).withNavBarInset(context),
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: widget.highlight.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              widget.highlight.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.highlight.fg,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final section in widget.sections) ...[
            Container(
              decoration: const BoxDecoration(
                color: FlowColors.primary,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                section.title.toUpperCase(),
                style: const TextStyle(
                  color: FlowColors.goldRich,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border:
                    Border.all(color: FlowColors.primaryLight, width: 1.2),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              margin: const EdgeInsets.only(bottom: 14),
              child: Column(
                children: [
                  for (int i = 0; i < section.rows.length; i++)
                    DetailRow(
                      label: section.rows[i].label,
                      value: section.rows[i].value,
                      isLast: i == section.rows.length - 1,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          RestrictedAction(
            child: SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _accept,
              icon: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: FlowColors.textOnNavyLarge),
                    )
                  : const Icon(Icons.check_circle),
              label: Text(
                _saving ? 'SAVING…' : 'ACCEPT',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary,
                foregroundColor: FlowColors.textOnNavyLarge,
                side: const BorderSide(
                    color: FlowColors.borderOnNavy, width: 0.8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── Renewal Success Screen ───────────────────────────────────────────────────

class _RenewalSuccessScreen extends StatelessWidget {
  const _RenewalSuccessScreen({
    required this.title,
    required this.message,
    required this.newPledgeNo,
    this.oldPledgeNo,
    this.amount,
  });

  final String title;
  final String message;
  final String newPledgeNo;
  final String? oldPledgeNo;
  final double? amount;

  void _goToActiveLoans(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OpenPledgeScreen()),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToActiveLoans(context);
      },
      child: Scaffold(
        backgroundColor: FlowColors.bg,
        appBar: AppBar(
          backgroundColor: FlowColors.primary,
          foregroundColor: FlowColors.goldRich,
          title: Text(title),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24).withNavBarInset(context),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle,
                    color: FlowColors.green, size: 80),
                const SizedBox(height: 20),
                Text(title,
                    style: const TextStyle(
                        fontSize: 26,
                        color: FlowColors.green,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _RenewalSuccessCard(
                  oldPledgeNo: oldPledgeNo,
                  newPledgeNo: newPledgeNo,
                  amount: amount,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.print),
                    label: const Text('PRINT',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: FlowColors.primary, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).popUntil((route) => route.isFirst),
                    icon: const Icon(Icons.home),
                    label: const Text('GO HOME',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlowColors.primary,
                      foregroundColor: FlowColors.textOnNavyLarge,
                      side: const BorderSide(
                          color: FlowColors.borderOnNavy, width: 0.8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Close Success Screen ─────────────────────────────────────────────────────

class _CloseSuccessScreen extends StatelessWidget {
  const _CloseSuccessScreen(
      {required this.pledgeNo, required this.amount});
  final String pledgeNo;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Pledge Released'),
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
              const Text('Pledge Released!',
                  style: TextStyle(
                      fontSize: 26,
                      color: FlowColors.green,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _CloseSuccessCard(pledgeNo: pledgeNo, amount: amount),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
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

// ─── Close Success Card ───────────────────────────────────────────────────────

class _CloseSuccessCard extends StatelessWidget {
  const _CloseSuccessCard(
      {required this.pledgeNo, required this.amount});
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
                  fontSize: 15, color: FlowColors.textOnNavyMuted)),
          const SizedBox(height: 4),
          Text('#$pledgeNo',
              style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.goldRich)),
          const SizedBox(height: 18),
          const Text('Amount Collected',
              style: TextStyle(
                  fontSize: 15, color: FlowColors.textOnNavyMuted)),
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

// ─── Renewal Success Card ─────────────────────────────────────────────────────

class _RenewalSuccessCard extends StatelessWidget {
  const _RenewalSuccessCard({
    required this.newPledgeNo,
    this.oldPledgeNo,
    this.amount,
  });
  final String newPledgeNo;
  final String? oldPledgeNo;
  final double? amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
      decoration: BoxDecoration(
        color: FlowColors.primary,
        borderRadius: BorderRadius.circular(16),
        border: const Border.fromBorderSide(
            BorderSide(color: FlowColors.borderOnNavy, width: 0.8)),
      ),
      child: Column(
        children: [
          if (oldPledgeNo != null) ...[
            const Text('Old Pledge No.',
                style: TextStyle(
                    fontSize: 14, color: FlowColors.textOnNavyMuted)),
            const SizedBox(height: 2),
            Text('#$oldPledgeNo',
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.goldRich)),
            const SizedBox(height: 14),
          ],
          const Text('New Pledge No.',
              style: TextStyle(
                  fontSize: 14, color: FlowColors.textOnNavyMuted)),
          const SizedBox(height: 2),
          Text('#$newPledgeNo',
              style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.goldRich)),
          if (amount != null) ...[
            const SizedBox(height: 14),
            const Text('New Amount',
                style: TextStyle(
                    fontSize: 14, color: FlowColors.textOnNavyMuted)),
            const SizedBox(height: 2),
            Text(money(amount!),
                style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.goldRich)),
          ],
        ],
      ),
    );
  }
}
