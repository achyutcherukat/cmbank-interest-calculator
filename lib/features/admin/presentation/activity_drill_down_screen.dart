import 'package:flutter/material.dart';

import '../../../features/customers/presentation/customer_detail_screen.dart';
import '../../../features/pledges/presentation/open_pledge_screen.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../data/admin_repository.dart';

enum ActivityDrillType { newLoans, closedLoans, interestCollected, customers }

class ActivityDrillDownScreen extends StatefulWidget {
  const ActivityDrillDownScreen({
    super.key,
    required this.type,
    required this.date,
  });

  final ActivityDrillType type;
  final DateTime date;

  @override
  State<ActivityDrillDownScreen> createState() =>
      _ActivityDrillDownScreenState();
}

class _ActivityDrillDownScreenState extends State<ActivityDrillDownScreen> {
  List<ActivityPledge> _pledges = [];
  List<ActivityCustomer> _customers = [];
  bool _loading = true;

  bool get _isCustomers => widget.type == ActivityDrillType.customers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = widget.date.toIso8601String().substring(0, 10);
      if (_isCustomers) {
        final result = await AdminRepository.instance.getCustomersForDate(d);
        if (mounted) {
          setState(() {
            _customers = result;
            _loading = false;
          });
        }
      } else if (widget.type == ActivityDrillType.newLoans) {
        final result = await AdminRepository.instance.getNewPledgesForDate(d);
        if (mounted) {
          setState(() {
            _pledges = result;
            _loading = false;
          });
        }
      } else {
        final result =
            await AdminRepository.instance.getClosedPledgesForDate(d);
        if (mounted) {
          setState(() {
            _pledges = result;
            _loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _title {
    switch (widget.type) {
      case ActivityDrillType.newLoans:
        return 'New Loans';
      case ActivityDrillType.closedLoans:
        return 'Closed Loans';
      case ActivityDrillType.interestCollected:
        return 'Interest Collected';
      case ActivityDrillType.customers:
        return 'Customers';
    }
  }

  int get _count => _isCustomers ? _customers.length : _pledges.length;

  @override
  Widget build(BuildContext context) {
    final d = widget.date;
    final dateStr = '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Text(
          '$_title · $dateStr',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _count == 0
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 64,
                          color: FlowColors.primary.withAlpha(80)),
                      const SizedBox(height: 14),
                      Text(
                        'No records for this date',
                        style: TextStyle(
                            fontSize: 18,
                            color: FlowColors.primary.withAlpha(150)),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: FlowColors.primary.withAlpha(20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Text(
                        '$_count record${_count == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 14,
                            color: FlowColors.primary,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 40),
                        itemCount: _count,
                        itemBuilder: (ctx, i) => _isCustomers
                            ? _CustomerRow(
                                customer: _customers[i],
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CustomerDetailScreen(
                                        customerId: _customers[i].id),
                                  ),
                                ),
                              )
                            : _PledgeRow(
                                pledge: _pledges[i],
                                showInterest: widget.type ==
                                    ActivityDrillType.interestCollected,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        _pledges[i].status == 'open'
                                            ? PledgeDetailScreen(
                                                pledgeId: _pledges[i].id,
                                                hideActions: true)
                                            : ClosedPledgeDetailScreen(
                                                pledgeId: _pledges[i].id),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ── Pledge Row ────────────────────────────────────────────────────────────────

class _PledgeRow extends StatelessWidget {
  const _PledgeRow({
    required this.pledge,
    required this.showInterest,
    required this.onTap,
  });

  final ActivityPledge pledge;
  final bool showInterest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amount =
        showInterest ? pledge.interestPaid : pledge.principalAmount;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: FlowColors.primary.withAlpha(100), width: 1.5),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D000000),
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
                  Text(
                    '#${pledge.pledgeNumber}',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: FlowColors.darkText),
                  ),
                  if (pledge.customerName != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.person,
                            size: 13, color: Colors.black45),
                        const SizedBox(width: 4),
                        Text(
                          pledge.customerName!,
                          style: const TextStyle(
                              fontSize: 13, color: FlowColors.medText),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(amount),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.goldRich),
                ),
                const SizedBox(height: 2),
                const Icon(Icons.chevron_right,
                    color: Colors.black38, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Customer Row ──────────────────────────────────────────────────────────────

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.onTap,
  });

  final ActivityCustomer customer;
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
          border: Border.all(
              color: FlowColors.primary.withAlpha(100), width: 1.5),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D000000),
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
                  Text(
                    customer.name,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: FlowColors.darkText),
                  ),
                  if (customer.phone != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.phone,
                            size: 13, color: Colors.black45),
                        const SizedBox(width: 4),
                        Text(
                          customer.phone!,
                          style: const TextStyle(
                              fontSize: 13, color: FlowColors.medText),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Colors.black38, size: 20),
          ],
        ),
      ),
    );
  }
}
