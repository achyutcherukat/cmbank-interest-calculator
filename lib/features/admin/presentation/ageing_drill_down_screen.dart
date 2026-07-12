import 'package:flutter/material.dart';

import '../../../features/pledges/presentation/open_pledge_screen.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../data/admin_repository.dart';

class AgeingDrillDownScreen extends StatefulWidget {
  const AgeingDrillDownScreen({
    super.key,
    required this.bucket,
    required this.label,
  });

  final String bucket;
  final String label;

  @override
  State<AgeingDrillDownScreen> createState() =>
      _AgeingDrillDownScreenState();
}

class _AgeingDrillDownScreenState extends State<AgeingDrillDownScreen> {
  List<AgeingPledge> _pledges = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pledges =
          await AdminRepository.instance.getAgeingPledges(widget.bucket);
      if (mounted) {
        setState(() {
          _pledges = pledges;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bucketColors = {
      '0': FlowColors.green,
      '1': FlowColors.gold,
      '2': FlowColors.orange,
      '3': FlowColors.red,
    };
    final color = bucketColors[widget.bucket] ?? FlowColors.primary;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Text(widget.label,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pledges.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 64, color: color.withAlpha(80)),
                      const SizedBox(height: 14),
                      Text('No pledges in this bracket',
                          style: TextStyle(fontSize: 18, color: color)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Summary banner
                    Container(
                      width: double.infinity,
                      color: color.withAlpha(20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Text(
                        '${_pledges.length} pledges — sorted oldest first',
                        style: TextStyle(
                            fontSize: 14,
                            color: color,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40)
                            .withNavBarInset(context),
                        itemCount: _pledges.length,
                        itemBuilder: (ctx, i) => _PledgeCard(
                          pledge: _pledges[i],
                          color: color,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PledgeDetailScreen(pledgeId: _pledges[i].id),
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

// ─── Pledge Card ──────────────────────────────────────────────────────────────

class _PledgeCard extends StatelessWidget {
  const _PledgeCard({
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
            BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 6,
                offset: Offset(0, 2))
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
                const Icon(Icons.chevron_right,
                    color: Colors.black38, size: 20),
              ],
            ),
            if (pledge.customerName != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.person, size: 14, color: Colors.black45),
                  const SizedBox(width: 4),
                  Text(pledge.customerName!,
                      style: const TextStyle(
                          fontSize: 14, color: FlowColors.medText)),
                ],
              ),
            ],
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 10),
            Row(
              children: [
                _amtCol('Pledge Date', isoToDisplay(pledge.pledgeDate),
                    isAmount: false),
                _amtCol('Loan Amount', money(pledge.loanAmount)),
                _amtCol('Interest Due', money(pledge.interestDue),
                    color: color),
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
          Text(
            value,
            style: TextStyle(
              fontSize: isAmount ? 14 : 13,
              fontWeight:
                  isAmount ? FontWeight.bold : FontWeight.normal,
              color: color ?? FlowColors.darkText,
            ),
          ),
        ],
      ),
    );
  }
}
