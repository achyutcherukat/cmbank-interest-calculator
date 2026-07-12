import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../data/pledge_model.dart';
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
                padding: const EdgeInsets.all(20).withNavBarInset(context),
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

