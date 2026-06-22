import 'dart:io';

import 'package:flutter/material.dart';

import '../../../features/pledges/data/pledge_model.dart';
import '../../../features/pledges/presentation/closed_pledges_screen.dart';
import '../../../features/pledges/presentation/open_pledge_screen.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/restorable_photo_thumb.dart';
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
  List<PledgeModel> _pledges = [];
  double _outstanding = 0.0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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

    final active = pledges.where((p) => p.status == 'open').length;

    if (mounted) {
      setState(() {
        _customer = CustomerWithStats.fromMap(
          row,
          totalPledges: pledges.length,
          activePledges: active,
        );
        _pledges = pledges;
        _outstanding = outstanding;
        _loading = false;
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

  // ─── Info Card ────────────────────────────────────────────────────────────

  Widget _infoCard(CustomerWithStats c) {
    final photos = c.photoPaths;
    return FlowCard(
      header: 'CUSTOMER INFORMATION',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailRow(label: 'Name', value: c.name.isNotEmpty ? c.name : '—'),
          DetailRow(
              label: 'Phone',
              value: c.phone.isNotEmpty ? c.phone : '—'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowSectionTitle('Pledge History'),
        if (_pledges.isEmpty)
          FlowCard(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.info_outline,
                        color: Colors.black38, size: 18),
                    SizedBox(width: 8),
                    Text('No pledges found for this customer',
                        style: TextStyle(
                            fontSize: 15, color: Colors.black45)),
                  ],
                ),
              ),
            ),
          )
        else
          ..._pledges.map((p) => _PledgeHistoryCard(
                pledge: p,
                onTap: () async {
                  if (p.id == null) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => p.status == 'open'
                          ? PledgeDetailScreen(pledgeId: p.id!)
                          : ClosedPledgeDetailScreen(pledgeId: p.id!),
                    ),
                  );
                  _load();
                },
              )),
      ],
    );
  }
}

// ─── Pledge History Card ──────────────────────────────────────────────────────

class _PledgeHistoryCard extends StatelessWidget {
  const _PledgeHistoryCard({required this.pledge, required this.onTap});

  final PledgeModel pledge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (badgeText, badgeColor, badgeBg) = switch (pledge.status) {
      'open' => ('OPEN', FlowColors.green, FlowColors.greenLight),
      'renewed' => ('RENEWED', FlowColors.primaryLight, FlowColors.accent),
      'migrated' => ('MIGRATED', FlowColors.orange, FlowColors.orangeLight),
      _ => ('CLOSED', FlowColors.primary, FlowColors.accent),
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FlowColors.primaryLight, width: 1.2),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 4,
                offset: Offset(0, 1))
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${pledge.pledgeNumber}',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: FlowColors.darkText),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isoToDisplay(pledge.pledgeDate),
                    style: const TextStyle(
                        fontSize: 14, color: FlowColors.medText),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(pledge.loanAmount),
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.primary),
                ),
                const SizedBox(height: 6),
                StatusBadge(
                  text: badgeText,
                  color: badgeColor,
                  backgroundColor: badgeBg,
                ),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Colors.black38),
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
