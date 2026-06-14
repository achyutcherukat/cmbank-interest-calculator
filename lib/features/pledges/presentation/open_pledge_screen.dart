import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../features/calculator/data/interest_calculator.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/shared_split_payment_widget.dart';
import '../data/payment_model.dart';
import '../data/pledge_item_model.dart';
import '../data/pledge_model.dart';
import '../data/pledge_repository.dart';

// ─── Open Pledge Screen ───────────────────────────────────────────────────────

class OpenPledgeScreen extends StatefulWidget {
  const OpenPledgeScreen({super.key});

  @override
  State<OpenPledgeScreen> createState() => _OpenPledgeScreenState();
}

class _OpenPledgeScreenState extends State<OpenPledgeScreen> {
  final _searchController = TextEditingController();
  List<PledgeModel> _recentPledges = [];
  bool _notFound = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final pledges = await PledgeRepository.instance.getOpenPledges(limit: 10);
    if (mounted) {
      setState(() {
        _recentPledges = pledges;
        _loading = false;
      });
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
    ).then((_) => _loadRecent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Open Pledge'),
      ),
      backgroundColor: FlowColors.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRecent,
              child: ListView(
                padding: const EdgeInsets.all(16),
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
                            color: FlowColors.red,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const FlowSectionTitle('Recent Open Pledges'),
                  if (_recentPledges.isEmpty)
                    const FlowCard(
                      child: Text('No open pledges.',
                          style: TextStyle(color: Colors.black54)),
                    )
                  else
                    ..._recentPledges.map(
                      (p) => GestureDetector(
                        onTap: () => _openDetail(p),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                                color: FlowColors.primaryLight, width: 1.5),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x0A000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Pledge ${p.pledgeNumber}',
                                        style: const TextStyle(
                                            color: FlowColors.primary,
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 3),
                                    Text(
                                        '${isoToDisplay(p.pledgeDate)}  ·  ${money(p.loanAmount)}',
                                        style: const TextStyle(
                                            fontSize: 14,
                                            color: FlowColors.medText)),
                                    if (p.customerName.isNotEmpty)
                                      Text(p.customerName,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black45)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios,
                                  color: Colors.black38, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ─── Pledge Detail Screen ─────────────────────────────────────────────────────

class PledgeDetailScreen extends StatefulWidget {
  const PledgeDetailScreen({super.key, required this.pledgeId});
  final int pledgeId;

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
      MaterialPageRoute(builder: (_) => ClosePledgeScreen(pledge: p)),
    );
    if (mounted) Navigator.pop(context);
  }

  void _goRenew(PledgeModel p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _RenewSelectionScreen(pledge: p)),
    );
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
    final today = DateTime.now();
    final actualDays = today.difference(fromDate).inDays;
    final effectiveDays = InterestCalculator.effectiveDays(fromDate, today);
    final calc = InterestCalculator.calculate(
      principal: p.loanAmount,
      fromDate: fromDate,
      toDate: today,
      ratePercent: p.interestRate,
    );
    final minApplied = actualDays < 7 || calc.note.isNotEmpty;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatusBadge(
                  text: p.status.toUpperCase(),
                  color: p.status == 'open'
                      ? FlowColors.green
                      : FlowColors.medText,
                  backgroundColor: p.status == 'open'
                      ? FlowColors.greenLight
                      : const Color(0xFFEEEEEE)),
              Text('$actualDays days elapsed',
                  style: const TextStyle(color: Colors.black54)),
            ],
          ),
          if (minApplied)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '* Interest calculated using minimum 7 days / ₹50 where applicable.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
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
                      _items[i].itemType != 'other')
                    DetailRow(
                        label: 'Type', value: _items[i].itemType),
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
                        isLast: _items[i].photoPaths.isEmpty),
                  if (_items[i].photoPaths.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: _items[i]
                            .photoPaths
                            .where((ph) => File(ph).existsSync())
                            .map((ph) => _photoThumb(ph))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),

          // Customer Details
          () {
            final idProofPhotos = _customer != null
                ? _parsePhotoPaths(
                        _customer!['id_proof_photo_paths'] as String?)
                    .where((ph) => File(ph).existsSync())
                    .toList()
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
                              .map((ph) => _photoThumb(ph, 'ID Proof'))
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
              header: 'Interest as of Today',
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
                label: const Text('RENEW',
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
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _photoThumb(String path, [String? label]) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => _PhotoViewScreen(file: File(path))),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(path),
              height: 80,
              width: 100,
              fit: BoxFit.cover,
            ),
          ),
        ),
        if (label != null && label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ],
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
  const ClosePledgeScreen({super.key, required this.pledge});
  final PledgeModel pledge;

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
      toDate: DateTime.now(),
      ratePercent: widget.pledge.interestRate,
    );
    _interest = calc.interest;
    _total = calc.total;
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
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Closure',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: Text(
          'Close pledge ${widget.pledge.pledgeNumber}?\n\nTotal collected: ${money(_total)}',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(fontSize: 18, color: Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: FlowColors.primary,
              foregroundColor: FlowColors.textOnNavyLarge,
              side: const BorderSide(color: FlowColors.borderOnNavy, width: 0.8),
            ),
            child: const Text('CLOSE',
                style: TextStyle(fontSize: 18, color: FlowColors.textOnNavyLarge)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final payState = _payKey.currentState;
      final cashAmt = payState?.cashAmount ?? _total;
      final upiAmt = payState?.upiAmount ?? 0;
      final payMode = payState?.mode ?? 'cash';

      final now = DateTime.now();
      final payment = PaymentModel(
        pledgeId: widget.pledge.id!,
        paymentDate: now.toIso8601String(),
        amount: _total,
        cashAmount: cashAmt,
        upiAmount: upiAmt,
        interestAmount: _interest,
        principalAmount: widget.pledge.loanAmount,
        paymentType: 'closure',
        paymentMode: payMode,
        createdAt: now.toIso8601String(),
      );

      await PledgeRepository.instance.closePledge(widget.pledge.id!, payment);

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
      return _DoneScreen(
        title: 'Pledge Closed',
        message: 'Pledge $_donePledgeNo successfully closed.',
        detail: 'Total collected: ${money(_doneTotal ?? 0)}',
      );
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
          FlowCard(
            backgroundColor: FlowColors.greenLight,
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

class _RenewSelectionScreen extends StatelessWidget {
  const _RenewSelectionScreen({required this.pledge});
  final PledgeModel pledge;

  @override
  Widget build(BuildContext context) {
    final from = DateTime.tryParse(pledge.pledgeDate) ?? DateTime.now();
    final calc = InterestCalculator.calculate(
      principal: pledge.loanAmount,
      fromDate: from,
      toDate: DateTime.now(),
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
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _navBtn(
            context,
            icon: Icons.trending_up,
            title: 'Increase Loan',
            subtitle: 'Increase the loan amount on this pledge',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _IncreaseLoanScreen(
                  pledge: pledge,
                  interest: calc.interest,
                  total: calc.total,
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
  });
  final PledgeModel pledge;
  final double interest;
  final double total;

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
    _amtCtrl =
        TextEditingController(text: widget.pledge.loanAmount.round().toString());
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
          onAccept: () async {
            PaymentModel? payment;
            if (_sub == 'pay') {
              final now = DateTime.now();
              payment = PaymentModel(
                pledgeId: widget.pledge.id!,
                paymentDate: now.toIso8601String(),
                amount: widget.interest,
                cashAmount: cashAmt,
                upiAmount: upiAmt,
                interestAmount: widget.interest,
                principalAmount: 0.0,
                paymentType: 'renewal',
                paymentMode: payMode,
                createdAt: now.toIso8601String(),
              );
            }
            return PledgeRepository.instance.renewPledge(
              widget.pledge.id!, newAmt, payment,
              totalInterestPaid: widget.interest,
              totalAmountCollected: widget.total,
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
          _pledgeSummaryCard(widget.pledge, widget.interest, widget.total),
          const SizedBox(height: 16),
          _subOptionCard(
            selected: _sub == 'pay',
            title: 'Pay Interest & Renew',
            description:
                'Customer pays interest now, new pledge at same or updated principal',
            onTap: () => setState(() {
              _sub = 'pay';
              _amtCtrl.text = widget.pledge.loanAmount.round().toString();
            }),
          ),
          _subOptionCard(
            selected: _sub == 'capitalise',
            title: 'Capitalise Interest',
            description:
                'Interest added to principal, no payment needed from customer',
            onTap: () => setState(() {
              _sub = 'capitalise';
              _amtCtrl.text =
                  (widget.pledge.loanAmount + widget.interest).round().toString();
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
  });
  final PledgeModel pledge;
  final double interest;
  final double total;

  @override
  State<_PartPaymentScreen> createState() => __PartPaymentScreenState();
}

class __PartPaymentScreenState extends State<_PartPaymentScreen> {
  String _sub = 'separate';
  final _amtCtrl = TextEditingController();
  final _payKey = GlobalKey<SharedSplitPaymentWidgetState>();

  double get _ppAmt => double.tryParse(_amtCtrl.text) ?? 0;
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
          onAccept: () async {
            final now = DateTime.now();
            final payNotes = _sub == 'separate'
                ? 'Part payment — principal reduced by ${money(ppAmt)}'
                : ppPrincipalPaid > 0
                    ? 'Part payment fixed — principal reduced by ${money(ppPrincipalPaid)}'
                    : 'Part payment fixed — unpaid interest ${money(unpaidInt)} added to new principal';
            final payment = PaymentModel(
              pledgeId: widget.pledge.id!,
              paymentDate: now.toIso8601String(),
              amount: ppTotalPay,
              cashAmount: cashAmt,
              upiAmount: upiAmt,
              interestAmount: intPaid,
              principalAmount: ppPrincipalPaid,
              paymentType: 'renewal',
              paymentMode: payMode,
              notes: payNotes,
              createdAt: now.toIso8601String(),
            );
            return PledgeRepository.instance.renewPledge(
              widget.pledge.id!, ppNewAmt, payment,
              totalInterestPaid: widget.interest,
              totalAmountCollected: widget.total,
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
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
  });
  final PledgeModel pledge;
  final double interest;
  final double total;

  @override
  State<_IncreaseLoanScreen> createState() => __IncreaseLoanScreenState();
}

class __IncreaseLoanScreenState extends State<_IncreaseLoanScreen> {
  late TextEditingController _amtCtrl;
  String _intSub = 'pay';
  final _payKey = GlobalKey<SharedSplitPaymentWidgetState>();

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
          title: 'Increase Loan Summary',
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
          successTitle: 'Loan Increased',
          successMessage: 'New pledge — ${money(ilFinal)}',
          onAccept: () => PledgeRepository.instance.renewPledge(
            widget.pledge.id!, ilFinal, null,
            disburseLoan: nd > 0,
            loanDisbursement: nd > 0 ? nd : 0,
            disbursementMode: nd > 0 ? payMode : 'cash',
            totalInterestPaid: widget.interest,
            totalAmountCollected: widget.total,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxPossible = widget.pledge.netWeight * widget.pledge.pledgeRate;
    final nd = _netDisburse;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Increase Loan'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                      value: '${money(widget.pledge.pledgeRate)}/g'),
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
            padding: const EdgeInsets.only(bottom: 14),
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
  });

  final String title;
  final _SummaryHighlight highlight;
  final List<_SummarySection> sections;
  final Future<String> Function() onAccept;
  final String successTitle;
  final String successMessage;

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
  });

  final String title;
  final String message;
  final String newPledgeNo;

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
        child: Padding(
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
              const SizedBox(height: 10),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 6),
              Text('New Pledge: #$newPledgeNo',
                  style: const TextStyle(
                      fontSize: 16,
                      color: FlowColors.primary,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
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
                height: 56,
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

// ─── Done Screen ──────────────────────────────────────────────────────────────

class _DoneScreen extends StatelessWidget {
  const _DoneScreen({
    required this.title,
    required this.message,
    required this.detail,
  });

  final String title;
  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Text(title),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle,
                  color: FlowColors.green, size: 72),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      fontSize: 24,
                      color: FlowColors.green,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 4),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.black54)),
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
