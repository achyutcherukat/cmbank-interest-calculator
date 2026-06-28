import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';

import '../../../features/admin/data/admin_repository.dart';
import '../../../features/calculator/data/interest_calculator.dart';
import '../../../features/pledges/data/pledge_model.dart';
import '../../../features/pledges/presentation/closed_pledges_screen.dart';
import '../../../features/pledges/presentation/open_pledge_screen.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/restorable_photo_thumb.dart';
import '../../../core/services/photo_sync_repository.dart';
import '../data/customer_repository.dart';
import 'add_edit_customer_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final int customerId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  CustomerWithStats? _customer;
  List<AgeingPledge> _openPledges = [];
  List<PledgeModel> _closedPledges = [];
  double _outstanding = 0.0;
  bool _loading = true;
  List<String> _idProofPhotoPaths = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadPhotos();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final row =
        await CustomerRepository.instance.getCustomerById(widget.customerId);
    if (row == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final phone = row['phone'] as String? ?? '';
    final pledges = await CustomerRepository.instance
        .getPledgesForCustomer(widget.customerId, phone);
    final outstanding = await CustomerRepository.instance
        .getTotalOutstanding(widget.customerId, phone);

    final today = DateTime.now();

    final openRaw = pledges.where((p) => p.status == 'open').toList()
      ..sort((a, b) => b.pledgeDate.compareTo(a.pledgeDate));

    final closedSorted = pledges.where((p) => p.status != 'open').toList()
      ..sort((a, b) {
        final ad = a.closureDate ?? '';
        final bd = b.closureDate ?? '';
        return bd.compareTo(ad);
      });

    final openComputed = openRaw.map((p) {
      final from = DateTime.tryParse(p.pledgeDate) ?? today;
      final daysOld = today.difference(from).inDays;
      final calc = InterestCalculator.calculate(
        principal: p.loanAmount,
        fromDate: from,
        toDate: today,
        ratePercent: p.interestRate,
      );
      return AgeingPledge(
        id: p.id ?? 0,
        pledgeNumber: p.pledgeNumber,
        pledgeDate: p.pledgeDate,
        loanAmount: p.loanAmount,
        interestRate: p.interestRate,
        interestDue: calc.interest,
        totalDue: calc.total,
        daysOld: daysOld,
      );
    }).toList();

    if (mounted) {
      setState(() {
        _customer = CustomerWithStats.fromMap(
          row,
          totalPledges: pledges.length,
          activePledges: openRaw.length,
        );
        _openPledges = openComputed;
        _closedPledges = closedSorted;
        _outstanding = outstanding;
        _loading = false;
      });
    }
  }

  Future<void> _loadPhotos() async {
    final photos = await PhotoSyncRepository.instance
        .getByCustomer(widget.customerId);
    if (mounted) {
      setState(() {
        _idProofPhotoPaths = photos.map((e) => e.localPath).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Customer Details',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      ),
      bottomNavigationBar: !_loading && _customer != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddEditCustomerScreen(
                              customerId: widget.customerId),
                        ),
                      );
                      _load();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlowColors.primary,
                      foregroundColor: FlowColors.textOnNavyLarge,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.edit, size: 22),
                    label: const Text('EDIT CUSTOMER',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _customer == null
              ? const Center(child: Text('Customer not found'))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final c = _customer!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        _summaryCard(c),
        _infoCard(c),
        _pledgeHistorySection(),
      ],
    );
  }

  // ─── Summary Card ─────────────────────────────────────────────────────────

  Widget _summaryCard(CustomerWithStats c) {
    return FlowCard(
      backgroundColor: FlowColors.accent,
      borderColor: FlowColors.primaryLight,
      header: 'ACCOUNT SUMMARY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _summaryTile(
                  icon: Icons.lock_open,
                  label: 'Active Pledges',
                  value: '${c.activePledges}',
                  color: c.activePledges > 0
                      ? FlowColors.green
                      : FlowColors.medText,
                ),
              ),
              Container(
                  width: 1, height: 56, color: FlowColors.primaryLight),
              const SizedBox(width: 16),
              Expanded(
                child: _summaryTile(
                  icon: Icons.currency_rupee,
                  label: 'Outstanding',
                  value: _outstanding > 0 ? money(_outstanding) : '—',
                  color: _outstanding > 0
                      ? FlowColors.orange
                      : FlowColors.medText,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              const Icon(Icons.history, size: 16, color: Colors.black45),
              const SizedBox(width: 6),
              Text(
                'Total pledges all time: ${c.totalPledges}',
                style: const TextStyle(
                    fontSize: 15, color: FlowColors.medText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  void _showPhoneOptions(BuildContext context, String phone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomPad = MediaQuery.of(ctx).viewPadding.bottom;
        return Container(
          decoration: const BoxDecoration(
            color: CMBColors.navy,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border:
                Border(top: BorderSide(color: CMBColors.borderOnNavy, width: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CMBColors.borderOnNavy,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: CMBColors.textOnNavyMuted,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const Divider(color: CMBColors.borderOnNavy, height: 1),
              ListTile(
                leading: const Icon(Icons.call_outlined,
                    color: CMBColors.goldRich),
                title: const Text('Call',
                    style: TextStyle(color: CMBColors.textOnNavyLarge)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await launchUrl(Uri.parse('tel:$phone'));
                },
              ),
              ListTile(
                leading: const Icon(Icons.message_outlined,
                    color: CMBColors.textOnNavyMuted),
                title: const Text('Send Message',
                    style: TextStyle(color: CMBColors.textOnNavyMuted)),
                onTap: () => Navigator.pop(ctx),
              ),
              SizedBox(height: bottomPad + 8),
            ],
          ),
        );
      },
    );
  }

  // ─── Info Card ────────────────────────────────────────────────────────────

  Widget _infoCard(CustomerWithStats c) {
    final photos = _idProofPhotoPaths;
    return FlowCard(
      header: 'CUSTOMER INFORMATION',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailRow(label: 'Name', value: c.name.isNotEmpty ? c.name : '—'),
          DetailRow(
              label: 'Phone',
              value: c.phone.isNotEmpty ? c.phone : '—',
              onTap: c.phone.isNotEmpty
                  ? () => _showPhoneOptions(context, c.phone)
                  : null),
          DetailRow(
              label: 'Address',
              value: () {
                final addr = formatCustomerAddress(
                  address: c.address,
                  district: c.district,
                  state: c.state,
                  pinCode: c.pinCode,
                );
                return addr.isNotEmpty ? addr : '—';
              }()),
          DetailRow(
              label: 'ID Proof Type',
              value: (c.idProofType?.isNotEmpty == true &&
                      c.idProofType != 'None')
                  ? c.idProofType!
                  : '—'),
          DetailRow(
              label: 'ID Number',
              value: (c.idProofNumber?.isNotEmpty == true)
                  ? c.idProofNumber!
                  : '—',
              isLast: photos.isEmpty),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('ID Proof Photos',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.primary)),
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => RestorablePhotoThumb(
                  localPath: photos[i],
                  width: 90,
                  height: 90,
                  onView: (p) => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => _FullScreenPhoto(file: File(p))),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Pledge History ───────────────────────────────────────────────────────

  Widget _pledgeHistorySection() {
    final hasAny = _openPledges.isNotEmpty || _closedPledges.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowSectionTitle('Pledge History'),
        if (!hasAny)
          FlowCard(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.info_outline, color: Colors.black38, size: 18),
                    SizedBox(width: 8),
                    Text('No pledges found for this customer',
                        style: TextStyle(fontSize: 15, color: Colors.black45)),
                  ],
                ),
              ),
            ),
          )
        else ...[
          if (_openPledges.isNotEmpty) ...[
            const FlowSectionTitle('Open Pledges'),
            ..._openPledges.map((p) {
              final color = _ageColor(p.daysOld);
              return _OpenPledgeCard(
                pledge: p,
                color: color,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PledgeDetailScreen(pledgeId: p.id),
                    ),
                  );
                  _load();
                },
              );
            }),
          ],
          if (_closedPledges.isNotEmpty) ...[
            const FlowSectionTitle('Closed Pledges'),
            ..._closedPledges.map((p) => _ClosedPledgeCard(
                  pledge: p,
                  statusLabel: _closedStatusLabel(p.renewType),
                  statusColor: _closedStatusColor(p.renewType),
                  statusBg: _closedStatusBg(p.renewType),
                  onTap: () async {
                    if (p.id == null) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ClosedPledgeDetailScreen(pledgeId: p.id!),
                      ),
                    );
                    _load();
                  },
                )),
          ],
        ],
      ],
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Color _ageColor(int daysOld) {
  if (daysOld <= 180) return FlowColors.green;
  if (daysOld <= 365) return FlowColors.gold;
  if (daysOld <= 730) return FlowColors.orange;
  return FlowColors.red;
}

String _closedStatusLabel(String? renewType) {
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

Color _closedStatusColor(String? renewType) =>
    renewType == null ? FlowColors.red : FlowColors.orange;

Color _closedStatusBg(String? renewType) =>
    renewType == null ? FlowColors.redLight : FlowColors.orangeLight;

// ─── Open Pledge Card ─────────────────────────────────────────────────────────

class _OpenPledgeCard extends StatelessWidget {
  const _OpenPledgeCard({
    required this.pledge,
    required this.color,
    required this.onTap,
  });

  final AgeingPledge pledge;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(100), width: 1.5),
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text('#${pledge.pledgeNumber}',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: FlowColors.darkText)),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withAlpha(30),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(pledge.ageLabel,
                            style: TextStyle(
                                fontSize: 12,
                                color: color,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.black38, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 10),
            Row(
              children: [
                _amtCol('Pledge Date', isoToDisplay(pledge.pledgeDate),
                    isAmount: false),
                _amtCol('Loan Amount', money(pledge.loanAmount)),
                _amtCol('Interest Due', money(pledge.interestDue), color: color),
                _amtCol('Total Due', money(pledge.totalDue),
                    color: FlowColors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _amtCol(String label, String value,
      {bool isAmount = true, Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.black45)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                fontSize: isAmount ? 14 : 13,
                fontWeight: isAmount ? FontWeight.bold : FontWeight.normal,
                color: color ?? FlowColors.darkText,
              )),
        ],
      ),
    );
  }
}

// ─── Closed Pledge Card ───────────────────────────────────────────────────────

class _ClosedPledgeCard extends StatelessWidget {
  const _ClosedPledgeCard({
    required this.pledge,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBg,
    required this.onTap,
  });

  final PledgeModel pledge;
  final String statusLabel;
  final Color statusColor;
  final Color statusBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: FlowColors.primaryLight, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))
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
                      Text('Pledge ${pledge.pledgeNumber}',
                          style: const TextStyle(
                              color: FlowColors.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      if (pledge.source == 'migrated') ...[
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
                    'Closed: ${isoToDisplay(pledge.closureDate)}  ·  ${money(pledge.loanAmount)}',
                    style: const TextStyle(fontSize: 13, color: FlowColors.medText),
                  ),
                  Text('Collected: ${money(pledge.totalAmountCollected)}',
                      style:
                          const TextStyle(fontSize: 13, color: Colors.black45)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusBadge(
              text: statusLabel,
              color: statusColor,
              backgroundColor: statusBg,
              borderColor: statusColor,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Full Screen Photo ────────────────────────────────────────────────────────

class _FullScreenPhoto extends StatelessWidget {
  const _FullScreenPhoto({required this.file});

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
