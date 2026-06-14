import 'package:flutter/material.dart';

import '../../../features/pledges/presentation/closed_pledges_screen.dart';
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
  State<GoldOutDrillDownScreen> createState() =>
      _GoldOutDrillDownScreenState();
}

class _GoldOutDrillDownScreenState extends State<GoldOutDrillDownScreen> {
  List<GoldMovementEntry> _entries = [];
  bool _loading = true;
  String _selectedPurity = 'ALL';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries =
          await GoldStockRepository.instance.getGoldOutEntries(widget.date);
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _purities {
    final seen = <String>{};
    for (final e in _entries) {
      if (e.purity.isNotEmpty) seen.add(e.purity);
    }
    return seen.toList()..sort();
  }

  List<GoldMovementEntry> get _filtered {
    if (_selectedPurity == 'ALL') return _entries;
    return _entries.where((e) => e.purity == _selectedPurity).toList();
  }

  double get _totalWeight =>
      _filtered.fold(0.0, (sum, e) => sum + e.netWeight);

  @override
  Widget build(BuildContext context) {
    final tabs = ['ALL', ..._purities];
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.red,
        foregroundColor: Colors.white,
        title: Text('Gold OUT — ${widget.displayDate}',
            style:
                const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  color: FlowColors.redLight,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.remove_circle,
                          color: FlowColors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${_totalWeight.toStringAsFixed(2)} g released  •  ${filtered.length} item${filtered.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: FlowColors.red),
                      ),
                    ],
                  ),
                ),
                // Filter tabs
                if (tabs.length > 1)
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: tabs.map((t) {
                          final active = _selectedPurity == t;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedPurity = t),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: active
                                      ? FlowColors.red
                                      : FlowColors.bg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: active
                                          ? FlowColors.red
                                          : FlowColors.primaryLight),
                                ),
                                child: Text(
                                  t,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: active
                                        ? Colors.white
                                        : FlowColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                // List
                Expanded(
                  child: filtered.isEmpty
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
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _OutEntryCard(
                            entry: filtered[i],
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ClosedPledgeDetailScreen(
                                    pledgeId: filtered[i].pledgeId),
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

// ─── Gold OUT entry card ──────────────────────────────────────────────────────

class _OutEntryCard extends StatelessWidget {
  const _OutEntryCard({
    required this.entry,
    required this.onTap,
  });

  final GoldMovementEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRenewed = entry.closureType == 'RENEWED';
    final badgeColor =
        isRenewed ? FlowColors.primaryLight : FlowColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
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
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('#${entry.pledgeNumber}',
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: FlowColors.darkText)),
                      const SizedBox(width: 8),
                      if (entry.purity.isNotEmpty)
                        _badge(entry.purity, FlowColors.gold,
                            FlowColors.goldLight),
                      if (entry.closureType != null) ...[
                        const SizedBox(width: 6),
                        _badge(entry.closureType!, badgeColor,
                            FlowColors.accent),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _capitalize(entry.itemType),
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
                  '${entry.netWeight.toStringAsFixed(2)} g',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.red),
                ),
                Text(
                  entry.time,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.black45),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                color: Colors.black38, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withAlpha(80)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor)),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
