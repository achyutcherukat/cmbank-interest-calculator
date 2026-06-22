import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../features/calculator/data/interest_calculator.dart';
import '../../../features/gold_stock/data/gold_rates_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/restorable_photo_thumb.dart';
import '../../../shared/widgets/shared_split_payment_widget.dart';
import '../data/pledge_item_model.dart';
import '../data/pledge_model.dart';
import '../data/pledge_repository.dart';
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
                padding: const EdgeInsets.all(16),
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

    if (mounted) {
      setState(() {
        _pledge = pledge;
        _items = items;
        _customer = customer;
        _chain = chain;
        _loading = false;
      });
    }
  }

  List<String> _parsePhotoPaths(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      return (jsonDecode(json) as List).cast<String>();
    } catch (_) {
      return [];
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
          builder: (_) =>
              ClosePledgeScreen(pledge: p, contextDate: widget.contextDate)),
    );
    if (mounted) Navigator.pop(context);
  }

  void _goRenew(PledgeModel p) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              RenewSelectionScreen(pledge: p, contextDate: widget.contextDate)),
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
            const Text(
              '* Minimum 7 days & ₹50 applied where applicable.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            ...offsets.map((extra) {
              final targetDate = today.add(Duration(days: extra));
              final calc = InterestCalculator.calculate(
                principal: p.loanAmount,
                fromDate: fromDate,
                toDate: targetDate,
                ratePercent: p.interestRate,
              );
              final days =
                  InterestCalculator.effectiveDays(fromDate, targetDate);
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
    final effectiveDays = InterestCalculator.effectiveDays(fromDate, today);
    final calc = InterestCalculator.calculate(
      principal: p.loanAmount,
      fromDate: fromDate,
      toDate: today,
      ratePercent: p.interestRate,
    );
    final asOfLabel = widget.contextDate != null
        ? 'Interest as of ${formatDmy(widget.contextDate!)}'
        : 'Interest as of Today';

    final totalGross = _items.fold<double>(0, (s, it) => s + it.grossWeight);
    final totalNet = _items.fold<double>(0, (s, it) => s + it.netWeight);
    final goldPhotos = p.goldPhotoPaths ?? [];

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Text('Pledge ${p.pledgeNumber}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
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

          // Item Details (one card per item)
          for (int i = 0; i < _items.length; i++)
            FlowCard(
              header: _items.length == 1 ? 'Item Details' : 'Item ${i + 1}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_items[i].itemType.isNotEmpty &&
                      _items[i].itemType != 'Other')
                    DetailRow(
                        label: 'Type', value: _items[i].itemType),
                  DetailRow(
                      label: 'Quantity', value: '${_items[i].quantity}'),
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
                    isLast: goldPhotos.isEmpty),
                if (goldPhotos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children:
                        goldPhotos
                        .map((ph) => RestorablePhotoThumb(
                              localPath: ph,
                              width: 100,
                              height: 80,
                              onView: (p) => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        _PhotoViewScreen(file: File(p))),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),

          // Customer Details
          () {
            final idProofPhotos = _customer != null
                ? _parsePhotoPaths(
                        _customer!['id_proof_photo_paths'] as String?)
                : <String>[];
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
                                        builder: (_) => PledgeDetailScreen(
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
            // Interest due today
            FlowCard(
              backgroundColor: FlowColors.greenLight,
              header: asOfLabel,
              child: Column(
                children: [
                  DetailRow(
                      label: 'Days (effective)', value: '$effectiveDays days'),
                  DetailRow(
                      label: 'Interest Due', value: money(calc.interest)),
                  DetailRow(
                      label: 'Total Due',
                      value: money(calc.total),
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
              SizedBox(
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: () => _goRenew(p),
                  icon: const Icon(Icons.autorenew, size: 26),
                  label: const Text('RENEW / PART PAYMENT/ TOP-UP',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
            ],
            if (widget.editEntryContext) ...[
              const SizedBox(height: 12),
              SizedBox(
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
            ],
          ],
          const SizedBox(height: 20),
        ],
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

// ─── Close Pledge Screen ──────────────────────────────────────────────────────

class ClosePledgeScreen extends StatefulWidget {
  const ClosePledgeScreen({super.key, required this.pledge, this.contextDate});
  final PledgeModel pledge;

  /// Backdated closure date. When set, interest is computed up to this date and
  /// all DB writes (closure_date, closed_at, payment_date, gold OUT) use it.
  final DateTime? contextDate;

  @override
  State<ClosePledgeScreen> createState() => _ClosePledgeScreenState();
}

class _ClosePledgeScreenState extends State<ClosePledgeScreen> {
  final _payKey = GlobalKey<SharedSplitPaymentWidgetState>();
  bool _isSaving = false;
  String? _donePledgeNo;
  double? _doneTotal;

  late final double _interest;
  late final double _total;

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
    );
    _interest = calc.interest;
    _total = calc.total;
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

  Future<void> _confirmClose() async {
    final payErr = _payKey.currentState?.validate();
    if (payErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(payErr), backgroundColor: Colors.red),
      );
      return;
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
                  _amtRow('Interest', money(_interest)),
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
                        money(_total),
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
      final cashAmt = payState?.cashAmount ?? _total;
      final upiAmt = payState?.upiAmount ?? 0;

      await PledgeRepository.instance.closePledge(
        pledgeId: widget.pledge.id!,
        totalInterestPaid: _interest,
        totalAmountCollected: _total,
        cashAmount: cashAmt,
        upiAmount: upiAmt,
        contextDate: _contextIso,
      );

      if (mounted) {
        setState(() {
          _donePledgeNo = widget.pledge.pledgeNumber;
          _doneTotal = _total;
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

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Close Pledge'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.contextDate != null)
            ContextDateBanner(
                label: 'Closure Date', date: widget.contextDate!),
          FlowCard(
            backgroundColor: FlowColors.goldLight,
            header: 'Closure Summary',
            child: Column(
              children: [
                DetailRow(
                    label: 'Principal',
                    value: money(widget.pledge.loanAmount)),
                DetailRow(label: 'Interest', value: money(_interest)),
                DetailRow(
                    label: 'Total Due',
                    value: money(_total),
                    isLast: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const FlowSectionTitle('Payment Mode'),
          SharedSplitPaymentWidget(
            key: _payKey,
            total: _total,
            totalLabel: 'Total Due',
          ),
          const SizedBox(height: 20),
          SizedBox(
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

class RenewSelectionScreen extends StatelessWidget {
  const RenewSelectionScreen({super.key, required this.pledge, this.contextDate});
  final PledgeModel pledge;

  /// Backdated renewal date. When set, interest is computed up to this date and
  /// all renewal DB writes (old closure, new start, payments, gold) use it.
  final DateTime? contextDate;

  @override
  Widget build(BuildContext context) {
    final from = DateTime.tryParse(pledge.pledgeDate) ?? DateTime.now();
    final calc = InterestCalculator.calculate(
      principal: pledge.loanAmount,
      fromDate: from,
      toDate: contextDate ?? DateTime.now(),
      ratePercent: pledge.interestRate,
    );

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Renew Pledge'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (contextDate != null)
            ContextDateBanner(label: 'Renewal Date', date: contextDate!),
          _pledgeSummaryCard(pledge, calc.interest, calc.total),
          const SizedBox(height: 20),
          _navBtn(
            context,
            icon: Icons.currency_rupee,
            title: 'Renew Pledge',
            subtitle: 'Pay interest & renew or capitalise interest',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _RenewPledgeScreen(
                  pledge: pledge,
                  interest: calc.interest,
                  total: calc.total,
                  contextDate: contextDate,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _navBtn(
            context,
            icon: Icons.payments,
            title: 'Part Payment',
            subtitle: 'Make a partial payment on this pledge',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _PartPaymentScreen(
                  pledge: pledge,
                  interest: calc.interest,
                  total: calc.total,
                  contextDate: contextDate,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _navBtn(
            context,
            icon: Icons.trending_up,
            title: 'Loan Top-Up',
            subtitle: 'Increase the loan amount on this pledge',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _IncreaseLoanScreen(
                  pledge: pledge,
                  interest: calc.interest,
                  total: calc.total,
                  contextDate: contextDate,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navBtn(
    BuildContext context, {
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

  @override
  void initState() {
    super.initState();
    _amtCtrl = TextEditingController(
        text: formatIndian(widget.pledge.loanAmount.round().toString()));
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
    final upiAmt = payState?.upiAmount ?? 0;
    final payMode = payState?.mode ?? 'cash';

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
                _SR('Payment Mode', payMode.toUpperCase()),
                if (payMode == 'split') ...[
                  _SR('Cash', money(cashAmt)),
                  _SR('UPI', money(upiAmt)),
                ],
              ]),
            _SummarySection('Gold Details', [
              _SR('Net Weight',
                  '${widget.pledge.netWeight.toStringAsFixed(2)} g'),
              _SR('Purity', widget.pledge.purity),
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
                upiAmount: upiAmt,
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
        padding: const EdgeInsets.all(16),
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
  void dispose() {
    _amtCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red));

  void _proceed() {
    if (_ppAmt <= 0) { _snack('Enter a payment amount'); return; }
    if (_ppNewAmt <= 0) { _snack('Resulting new pledge amount cannot be zero'); return; }
    final err = _payKey.currentState?.validate();
    if (err != null) { _snack(err); return; }

    final payState = _payKey.currentState;
    final cashAmt = payState?.cashAmount ?? _ppTotalPay;
    final upiAmt = payState?.upiAmount ?? 0;
    final payMode = payState?.mode ?? 'cash';
    final intPaid =
        _sub == 'separate' ? widget.interest : _ppAmt.clamp(0.0, widget.interest);
    final unpaidInt = (_sub == 'fixed' && _ppAmt < widget.interest)
        ? widget.interest - _ppAmt
        : 0.0;
    final ppNewAmt = _ppNewAmt;
    final ppTotalPay = _ppTotalPay;
    final ppPrincipalPaid = _ppPrincipalPaid;
    final ppAmt = _ppAmt;

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
              _SR('Payment Mode', payMode.toUpperCase()),
              if (payMode == 'split') ...[
                _SR('Cash', money(cashAmt)),
                _SR('UPI', money(upiAmt)),
              ],
            ]),
            _SummarySection('Gold Details', [
              _SR('Net Weight',
                  '${widget.pledge.netWeight.toStringAsFixed(2)} g'),
              _SR('Purity', widget.pledge.purity),
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
                upiAmount: upiAmt,
                contextDate: ctxIso,
              );
            }
            return PledgeRepository.instance.partPaymentFixedAmount(
              oldPledgeId: widget.pledge.id!,
              newPrincipal: ppNewAmt,
              interest: widget.interest,
              fixedAmount: ppAmt,
              cashAmount: cashAmt,
              upiAmount: upiAmt,
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
        title: const Text('Part Payment'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.contextDate != null)
            ContextDateBanner(
                label: 'Renewal Date', date: widget.contextDate!),
          _pledgeSummaryCard(widget.pledge, widget.interest, widget.total),
          const SizedBox(height: 16),
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
  double? _currentPledgeRate;

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
    GoldRatesRepository.instance.getCurrentRates().then((rates) {
      if (mounted && rates != null && rates.pledgeRate > 0) {
        setState(() => _currentPledgeRate = rates.pledgeRate);
      }
    });
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
    final upiAmt = nd > 0 ? (payState?.upiAmount ?? 0) : 0.0;
    final payMode = nd > 0 ? (payState?.mode ?? 'cash') : 'cash';
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
                _SR('Payment Mode', payMode.toUpperCase()),
                if (payMode == 'split') ...[
                  _SR('Cash', money(cashAmt)),
                  _SR('UPI', money(upiAmt)),
                ],
              ]),
            _SummarySection('Gold Details', [
              _SR('Net Weight',
                  '${widget.pledge.netWeight.toStringAsFixed(2)} g'),
              _SR('Purity', widget.pledge.purity),
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
                upiAmount: upiAmt,
                contextDate: ctxIso,
              );
            }
            return PledgeRepository.instance.increaseLoanInterestNotCapitalised(
              oldPledgeId: widget.pledge.id!,
              newPrincipal: ilFinal,
              interest: widget.interest,
              extraCashOut: nd,
              cashAmount: cashAmt,
              upiAmount: upiAmt,
              contextDate: ctxIso,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPledgeRate = _currentPledgeRate ?? 0;
    final maxPossible = widget.pledge.netWeight * currentPledgeRate;
    final nd = _netDisburse;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Loan Top-Up'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
                  DetailRow(
                      label: 'Net Weight',
                      value:
                          '${widget.pledge.netWeight.toStringAsFixed(2)} g'),
                  DetailRow(
                      label: 'Pledge Rate',
                      value: '${money(currentPledgeRate)}/g'),
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
        padding: const EdgeInsets.all(16),
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
          SizedBox(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Text(title),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
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
