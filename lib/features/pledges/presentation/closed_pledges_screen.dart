import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/restorable_photo_thumb.dart';
import '../../accounts/data/bank_account_model.dart';
import '../../accounts/data/bank_account_repository.dart';
import '../data/payment_model.dart';
import '../data/pledge_item_model.dart';
import '../data/pledge_model.dart';
import '../../../core/services/photo_sync_repository.dart';
import '../data/pledge_repository.dart';
import 'open_pledge_screen.dart';

// ─── Closed Pledges List Screen ───────────────────────────────────────────────

class ClosedPledgesScreen extends StatefulWidget {
  const ClosedPledgesScreen({super.key});

  @override
  State<ClosedPledgesScreen> createState() => _ClosedPledgesScreenState();
}

class _ClosedPledgesScreenState extends State<ClosedPledgesScreen> {
  final _searchController = TextEditingController();
  List<PledgeModel> _recentClosed = [];
  bool _loading = true;
  bool _notFound = false;

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
    final pledges =
        await PledgeRepository.instance.getClosedPledges(limit: 20);
    if (mounted) {
      setState(() {
        _recentClosed = pledges;
        _loading = false;
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final pledge =
        await PledgeRepository.instance.getPledgeByNumber(query);
    if (!mounted) return;
    if (pledge == null || pledge.status == 'open') {
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
          builder: (_) =>
              ClosedPledgeDetailScreen(pledgeId: pledge.id!)),
    );
  }

  String _statusLabel(String? renewType) {
    switch (renewType) {
      case 'RENEWED':
        return 'RENEWED';
      case 'PART_PAYMENT':
        return 'PART PAYMENT';
      case 'LOAN_INCREASE':
        return 'LOAN TOP-UP';
      default:
        return 'RELEASED';
    }
  }

  Color _statusColor(String? renewType) {
    return renewType == null ? FlowColors.red : FlowColors.orange;
  }

  Color _statusBg(String? renewType) {
    return renewType == null ? FlowColors.redLight : FlowColors.orangeLight;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Closed Loans'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRecent,
              child: ListView(
                padding: const EdgeInsets.all(20),
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
                        'No closed loan found for that number.',
                        style: TextStyle(
                            color: FlowColors.red,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const FlowSectionTitle('Recent Closed Loans'),
                  if (_recentClosed.isEmpty)
                    const FlowCard(
                      child: Text('No closed loans yet.',
                          style: TextStyle(color: Colors.black54)),
                    )
                  else
                    ..._recentClosed.map((p) => _pledgeCard(p)),
                ],
              ),
            ),
    );
  }

  Widget _pledgeCard(PledgeModel p) {
    return GestureDetector(
      onTap: () => _openDetail(p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border:
              Border.all(color: FlowColors.primaryLight, width: 1.5),
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
                  Row(
                    children: [
                      Text('Pledge ${p.pledgeNumber}',
                          style: const TextStyle(
                              color: FlowColors.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      if (p.source == 'migrated') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: FlowColors.goldLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Migrated',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: FlowColors.gold,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Closed: ${isoToDisplay(p.closureDate)}  ·  ${money(p.loanAmount)}',
                    style: const TextStyle(
                        fontSize: 13, color: FlowColors.medText),
                  ),
                  Text('Collected: ${money(p.totalAmountCollected)}',
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black45)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusBadge(
              text: _statusLabel(p.renewType),
              color: _statusColor(p.renewType),
              backgroundColor: _statusBg(p.renewType),
              borderColor: _statusColor(p.renewType),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chain Entry ──────────────────────────────────────────────────────────────

class _ClChainEntry {
  const _ClChainEntry(this.pledgeNumber, this.pledgeId, this.isCurrent, this.status);
  final String pledgeNumber;
  final int pledgeId;
  final bool isCurrent;
  final String status;
}

// ─── Closed Pledge Detail Screen ──────────────────────────────────────────────

class ClosedPledgeDetailScreen extends StatefulWidget {
  const ClosedPledgeDetailScreen({super.key, required this.pledgeId});
  final int pledgeId;

  @override
  State<ClosedPledgeDetailScreen> createState() =>
      _ClosedPledgeDetailScreenState();
}

class _ClosedPledgeDetailScreenState
    extends State<ClosedPledgeDetailScreen> {
  PledgeModel? _pledge;
  List<PledgeItemModel> _items = [];
  List<PaymentModel> _payments = [];
  List<BankAccount> _allAccounts = [];
  Map<String, dynamic>? _customer;
  List<_ClChainEntry> _chain = [];
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

    final items = await PledgeRepository.instance
        .getItemsForPledge(widget.pledgeId);
    final payments = await PledgeRepository.instance
        .getPaymentsForPledge(widget.pledgeId);

    Map<String, dynamic>? customer;
    if (pledge.customerId != null) {
      customer = await PledgeRepository.instance
          .getCustomerById(pledge.customerId!);
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

  Future<List<_ClChainEntry>> _buildChain(PledgeModel p) async {
    final chain = <_ClChainEntry>[];

    PledgeModel? cur = p;
    while (cur != null) {
      chain.insert(
          0, _ClChainEntry(cur.pledgeNumber, cur.id!, cur.id == p.id, cur.status));
      if (cur.renewalParentId == null) break;
      cur = await PledgeRepository.instance
          .getPledgeById(cur.renewalParentId!);
    }

    int limit = 10;
    PledgeModel? succ =
        await PledgeRepository.instance.getSuccessorPledge(p.id!);
    while (succ != null && limit-- > 0) {
      chain.add(_ClChainEntry(succ.pledgeNumber, succ.id!, false, succ.status));
      succ = await PledgeRepository.instance
          .getSuccessorPledge(succ.id!);
    }

    return chain;
  }


  String _statusLabel(String? renewType) {
    switch (renewType) {
      case 'RENEWED':
        return 'RENEWED';
      case 'PART_PAYMENT':
        return 'PART PAYMENT';
      case 'LOAN_INCREASE':
        return 'LOAN TOP-UP';
      default:
        return 'RELEASED';
    }
  }

  Color _statusColor(String? renewType) {
    return renewType == null ? FlowColors.red : FlowColors.orange;
  }

  Color _statusBg(String? renewType) {
    return renewType == null ? FlowColors.redLight : FlowColors.orangeLight;
  }

  String _paymentTypeLabel(String type) {
    switch (type) {
      case 'LOAN_DISBURSED':
        return 'Loan Disbursed';
      case 'LOAN_FULL_CLOSURE':
        return 'Closure';
      case 'RENEWAL_INTEREST_PAID':
        return 'Renewal Interest';
      case 'PART_PAYMENT_RECEIVED':
        return 'Part Payment';
      case 'LOAN_INCREASE_DISBURSED':
        return 'Loan Top-Up';
      case 'EXPENSE':
        return 'Expense';
      case 'ADJUSTMENT':
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
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status row ─────────────────────────────────────────────────────
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
          const SizedBox(height: 14),

          // ── Pledge Details ─────────────────────────────────────────────────
          FlowCard(
            header: 'Pledge Details',
            child: Column(
              children: [
                DetailRow(
                    label: 'Pledge No.', value: p.pledgeNumber),
                DetailRow(
                    label: 'Pledge Date',
                    value: isoToDisplay(p.pledgeDate)),
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

          // ── Financial Summary ──────────────────────────────────────────────
          FlowCard(
            backgroundColor: FlowColors.accent,
            header: 'Financial Summary',
            child: Column(
              children: [
                DetailRow(
                    label: 'Loan Amount', value: money(p.loanAmount)),
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

          // ── Gold Details ───────────────────────────────────────────────────
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
                        value:
                            '${p.grossWeight.toStringAsFixed(2)} g'),
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
                        value: p.goldRate > 0
                            ? '${money(p.goldRate)}/g'
                            : '—',
                        isLast: true),
                ],
              ),
            ),

          // ── Customer Details ───────────────────────────────────────────────
          if (p.customerName.isNotEmpty || _customer != null)
            FlowCard(
              header: 'Customer Details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.customerName.isNotEmpty)
                    DetailRow(label: 'Name', value: p.customerName),
                  if (p.customerPhone != null &&
                      p.customerPhone!.isNotEmpty)
                    DetailRow(
                        label: 'Phone', value: p.customerPhone!),
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
                    if ((_customer!['id_proof_type'] as String?)
                            ?.isNotEmpty ==
                        true)
                      DetailRow(
                          label: 'ID Proof Type',
                          value: _customer!['id_proof_type'] as String),
                    if ((_customer!['id_proof_number'] as String?)
                            ?.isNotEmpty ==
                        true)
                      DetailRow(
                          label: 'ID Proof No.',
                          value:
                              _customer!['id_proof_number'] as String,
                          isLast: true),
                  ],
                  // ID proof photos
                  if (_customer != null) ...[
                    Builder(builder: (_) {
                      final paths = _idProofPhotoPaths;
                      if (paths.isEmpty) return const SizedBox.shrink();
                      return Padding(
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
                              children: paths
                                  .map((path) => RestorablePhotoThumb(
                                        localPath: path,
                                        width: 100,
                                        height: 80,
                                        onView: (resolved) => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  _ClosedPhotoViewScreen(
                                                      file: File(resolved))),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),

          // ── Item Details ───────────────────────────────────────────────────
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
                          label: 'Item Types',
                          value: _items[i].itemType),
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
                    if (_items[i].notes != null &&
                        _items[i].notes!.isNotEmpty)
                      DetailRow(
                          label: 'Notes',
                          value: _items[i].notes!,
                          isLast: true),
                  ],
                ),
              ),

          // ── Gold Photos ────────────────────────────────────────────────────
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
                                builder: (_) => _ClosedPhotoViewScreen(
                                    file: File(resolved))),
                          ),
                        ))
                    .toList(),
              ),
            ),

          // ── Payment Breakdown ─────────────────────────────────────────────
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
                        label: 'Total',
                        value: money(_payments[i].amount)),
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

          // ── Renewal Chain ─────────────────────────────────────────────────
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
                              padding:
                                  EdgeInsets.symmetric(horizontal: 4),
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
                                            ? PledgeDetailScreen(pledgeId: _chain[i].pledgeId)
                                            : ClosedPledgeDetailScreen(pledgeId: _chain[i].pledgeId),
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
                ],
              ),
            ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

}

// ─── Photo Fullscreen Viewer ──────────────────────────────────────────────────

class _ClosedPhotoViewScreen extends StatelessWidget {
  const _ClosedPhotoViewScreen({required this.file});
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
