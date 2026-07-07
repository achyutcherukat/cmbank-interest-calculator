import 'package:flutter/material.dart';

import '../../../features/pledges/data/pledge_model.dart';
import '../../../features/pledges/presentation/open_pledge_screen.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../data/gold_stock_repository.dart';

class GoldOutDrillDownScreen extends StatefulWidget {
  const GoldOutDrillDownScreen({
    super.key,
    required this.date,
    required this.displayDate,
  });

  final String date;
  final String displayDate;

  @override
  State<GoldOutDrillDownScreen> createState() => _GoldOutDrillDownScreenState();
}

class _GoldOutDrillDownScreenState extends State<GoldOutDrillDownScreen> {
  List<GoldPledgeEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries =
          await GoldStockRepository.instance.getGoldOutPledges(widget.date);
      if (mounted) setState(() { _entries = entries; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _totalNetWeight =>
      _entries.fold(0.0, (s, e) => s + e.netWeight);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.red,
        foregroundColor: Colors.white,
        title: Text(
          'Gold OUT — ${widget.displayDate}',
          style: const TextStyle(
              fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary header
                Container(
                  width: double.infinity,
                  color: FlowColors.redLight,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.remove_circle,
                          color: FlowColors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${_totalNetWeight.toStringAsFixed(2)} g released  •  ${_entries.length} pledge${_entries.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: FlowColors.red),
                      ),
                    ],
                  ),
                ),
                // List
                Expanded(
                  child: _entries.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inventory_2_outlined,
                                  size: 60,
                                  color: FlowColors.red.withAlpha(80)),
                              const SizedBox(height: 14),
                              const Text('No gold released on this day',
                                  style: TextStyle(
                                      fontSize: 17, color: Colors.black45)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 12, 16, 40),
                          itemCount: _entries.length + 1,
                          itemBuilder: (_, i) {
                            if (i == _entries.length) {
                              return _OutTotalsCard(entries: _entries);
                            }
                            final e = _entries[i];
                            return _GoldOutPledgeCard(
                              entry: e,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ClosedPledgeDetailScreen(
                                    pledgeId: e.pledgeId,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ─── Pledge card ──────────────────────────────────────────────────────────────

class _GoldOutPledgeCard extends StatelessWidget {
  const _GoldOutPledgeCard({
    required this.entry,
    required this.onTap,
  });

  final GoldPledgeEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final interest = _roundUp5(entry.interest ?? 0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: FlowColors.red.withAlpha(80), width: 1.5),
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
            // Header: pledge number + closure label + purity badges + chevron
            Row(
              children: [
                Text(
                  '#${entry.pledgeNumber}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.darkText),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEEEEE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    renewalLabel(entry.renewType, entry.renewSubtype),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: FlowColors.medText),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 3,
                    children: entry.purities
                        .map((p) => _badge(p))
                        .toList(),
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: Colors.black38, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 8),
            // Single stats row: Items | Principal | Interest | Gross Wt | Net Wt
            IntrinsicHeight(
              child: Row(
                children: [
                  _statCol('Items', '${entry.itemCount}'),
                  _divider(),
                  _statCol('Principal', money(entry.principal)),
                  _divider(),
                  _statCol('Interest', money(interest.toDouble())),
                  _divider(),
                  _statCol('Gross Wt',
                      '${entry.grossWeight.toStringAsFixed(2)} g'),
                  _divider(),
                  _statCol('Net Wt',
                      '${entry.netWeight.toStringAsFixed(2)} g'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCol(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: FlowColors.medText,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.darkText)),
        ],
      ),
    );
  }

  Widget _divider() => const VerticalDivider(
        width: 1,
        thickness: 1,
        color: Color(0xFFEEEEEE),
      );

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: FlowColors.goldLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FlowColors.gold.withAlpha(80)),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: FlowColors.gold)),
    );
  }
}

// ─── Totals row card ──────────────────────────────────────────────────────────

class _OutTotalsCard extends StatelessWidget {
  const _OutTotalsCard({required this.entries});

  final List<GoldPledgeEntry> entries;

  @override
  Widget build(BuildContext context) {
    final totalItems = entries.fold(0, (s, e) => s + e.itemCount);
    final totalPrincipal = entries.fold(0.0, (s, e) => s + e.principal);
    final totalInterest =
        entries.fold(0, (s, e) => s + _roundUp5(e.interest ?? 0));
    final totalNet = entries.fold(0.0, (s, e) => s + e.netWeight);
    final totalGross = entries.fold(0.0, (s, e) => s + e.grossWeight);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: FlowColors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TOTAL',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.textOnNavySmall,
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0x33FFFFFF)),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              children: [
                _statCol('Items', '$totalItems'),
                _divider(),
                _statCol('Principal', money(totalPrincipal)),
                _divider(),
                _statCol('Interest', money(totalInterest.toDouble())),
                _divider(),
                _statCol('Gross Wt', '${totalGross.toStringAsFixed(2)} g'),
                _divider(),
                _statCol('Net Wt', '${totalNet.toStringAsFixed(2)} g'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCol(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: FlowColors.textOnNavySmall,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.textOnNavyLarge)),
        ],
      ),
    );
  }

  Widget _divider() => const VerticalDivider(
        width: 1,
        thickness: 1,
        color: Color(0x33FFFFFF),
      );
}

// ─── Interest rounding ────────────────────────────────────────────────────────

int _roundUp5(double v) {
  final i = v.ceil();
  final rem = i % 5;
  return rem == 0 ? i : i + (5 - rem);
}
