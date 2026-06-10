import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../data/pledge_model.dart';
import '../data/pledge_repository.dart';

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
    if (mounted) setState(() { _recentClosed = pledges; _loading = false; });
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
          builder: (_) => ClosedPledgeDetailScreen(pledge: pledge)),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'renewed':
        return 'RENEWED';
      case 'migrated':
        return 'MIGRATED';
      default:
        return 'CLOSED';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'renewed':
        return FlowColors.orange;
      case 'migrated':
        return Colors.purple;
      default:
        return FlowColors.red;
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'renewed':
        return FlowColors.orangeLight;
      case 'migrated':
        return const Color(0xFFF3E5F5);
      default:
        return FlowColors.redLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Closed Pledges'),
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
                      icon: const Icon(Icons.search),
                      label: const Text('SEARCH'),
                    ),
                  ),
                  if (_notFound) ...[
                    const SizedBox(height: 10),
                    const FlowCard(
                      backgroundColor: FlowColors.redLight,
                      borderColor: FlowColors.red,
                      child: Text(
                        'No closed pledge found for that number.',
                        style: TextStyle(
                            color: FlowColors.red,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const FlowSectionTitle('Recent Closed Pledges'),
                  if (_recentClosed.isEmpty)
                    const FlowCard(
                      child: Text('No closed pledges yet.',
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
          border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
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
                      if (p.source == 'manual') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: FlowColors.goldLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Manual',
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
                    'Closed: ${p.closureDate ?? '—'}  ·  ${money(p.loanAmount)}',
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
              text: _statusLabel(p.status),
              color: _statusColor(p.status),
              backgroundColor: _statusBg(p.status),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Closed Pledge Detail Screen ──────────────────────────────────────────────

class ClosedPledgeDetailScreen extends StatelessWidget {
  const ClosedPledgeDetailScreen({super.key, required this.pledge});

  final PledgeModel pledge;

  String _statusLabel() {
    switch (pledge.status) {
      case 'renewed':
        return 'RENEWED';
      case 'migrated':
        return 'MIGRATED';
      default:
        return 'CLOSED';
    }
  }

  Color _statusColor() {
    switch (pledge.status) {
      case 'renewed':
        return FlowColors.orange;
      case 'migrated':
        return Colors.purple;
      default:
        return FlowColors.red;
    }
  }

  Color _statusBg() {
    switch (pledge.status) {
      case 'renewed':
        return FlowColors.orangeLight;
      case 'migrated':
        return const Color(0xFFF3E5F5);
      default:
        return FlowColors.redLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysHeld = pledge.closureDate != null && pledge.pledgeDate.isNotEmpty
        ? DateTime.tryParse(pledge.closureDate!)
                ?.difference(
                    DateTime.tryParse(pledge.pledgeDate) ?? DateTime.now())
                .inDays ??
            0
        : 0;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: Text('Pledge ${pledge.pledgeNumber}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              StatusBadge(
                text: _statusLabel(),
                color: _statusColor(),
                backgroundColor: _statusBg(),
              ),
              const SizedBox(width: 10),
              if (pledge.source == 'manual')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: FlowColors.goldLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Manual Entry',
                      style: TextStyle(
                          fontSize: 13,
                          color: FlowColors.gold,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Pledge details
          FlowCard(
            child: Column(
              children: [
                const FlowCardTitle('Pledge Details'),
                DetailRow(label: 'Pledge No.', value: pledge.pledgeNumber),
                if (pledge.customerName.isNotEmpty)
                  DetailRow(label: 'Customer', value: pledge.customerName),
                DetailRow(label: 'Pledge Date', value: pledge.pledgeDate),
                DetailRow(
                    label: 'Closure Date',
                    value: pledge.closureDate ?? '—'),
                DetailRow(
                    label: 'Days Held', value: '$daysHeld days', isLast: true),
              ],
            ),
          ),

          // Financial summary
          FlowCard(
            backgroundColor: FlowColors.accent,
            child: Column(
              children: [
                const FlowCardTitle('Financial Summary'),
                DetailRow(
                    label: 'Principal', value: money(pledge.loanAmount)),
                DetailRow(
                    label: 'Interest Paid',
                    value: money(pledge.totalInterestPaid)),
                DetailRow(
                    label: 'Total Collected',
                    value: money(pledge.totalAmountCollected),
                    isLast: true),
              ],
            ),
          ),

          // Gold details (if available)
          if (pledge.netWeight > 0)
            FlowCard(
              child: Column(
                children: [
                  DetailRow(
                      label: 'Weight',
                      value: '${pledge.netWeight.toStringAsFixed(2)} g'),
                  DetailRow(
                      label: 'Purity',
                      value: pledge.purity.isNotEmpty ? pledge.purity : '—'),
                  DetailRow(
                      label: 'Interest Rate',
                      value:
                          '${pledge.interestRate.toStringAsFixed(0)}% p.a.',
                      isLast: true),
                ],
              ),
            )
          else
            FlowCard(
              child: DetailRow(
                  label: 'Interest Rate',
                  value: '${pledge.interestRate.toStringAsFixed(0)}% p.a.',
                  isLast: true),
            ),

          // Renewal chain
          if (pledge.renewalParentId != null)
            FlowCard(
              backgroundColor: FlowColors.accent,
              child: Text(
                'Renewed from pledge #${pledge.renewalParentId}',
                style: const TextStyle(
                    color: FlowColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
