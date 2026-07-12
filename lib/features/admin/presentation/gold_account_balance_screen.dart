import 'package:flutter/material.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../data/admin_repository.dart';

/// Drill-down for the gold-account ledger: a daily table of
/// Date | Opening | Money In | Money Out | Closing, newest first.
class GoldAccountBalanceScreen extends StatefulWidget {
  const GoldAccountBalanceScreen({super.key});

  @override
  State<GoldAccountBalanceScreen> createState() =>
      _GoldAccountBalanceScreenState();
}

class _GoldAccountBalanceScreenState extends State<GoldAccountBalanceScreen> {
  static const _pageSize = 90;

  List<GoldAccountDay> _days = [];
  bool _loading = true;
  int _visible = _pageSize;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final days = await AdminRepository.instance.getGoldAccountDays();
      if (mounted) {
        setState(() {
          _days = days;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleDays =
        _days.length > _visible ? _days.sublist(0, _visible) : _days;
    final hasMore = _days.length > _visible;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Gold Account Balance',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _days.isEmpty
              ? const Center(
                  child: Text('No account activity yet.',
                      style: TextStyle(fontSize: 18, color: FlowColors.medText)),
                )
              : Column(
                  children: [
                    _headerRow(),
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.zero.withNavBarInset(context),
                        itemCount: visibleDays.length + (hasMore ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == visibleDays.length) {
                            return _loadMoreButton();
                          }
                          return _dayRow(visibleDays[i], i.isEven);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _headerRow() {
    return Container(
      color: FlowColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: const [
          _HeaderCell('Date', flex: 3, align: TextAlign.left),
          _HeaderCell('Opening', flex: 3),
          _HeaderCell('In', flex: 3),
          _HeaderCell('Out', flex: 3),
          _HeaderCell('Closing', flex: 3),
        ],
      ),
    );
  }

  Widget _dayRow(GoldAccountDay d, bool even) {
    return Container(
      color: even ? Colors.white : FlowColors.accent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(isoToDisplay(d.date),
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: FlowColors.darkText)),
            ),
          ),
          _amtCell(d.opening, 3, FlowColors.darkText),
          _amtCell(d.moneyIn, 3, FlowColors.green),
          _amtCell(d.moneyOut, 3, FlowColors.red),
          _amtCell(d.closing, 3, FlowColors.primary, bold: true),
        ],
      ),
    );
  }

  Widget _amtCell(double value, int flex, Color color, {bool bold = false}) {
    return Expanded(
      flex: flex,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          money(value),
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color),
        ),
      ),
    );
  }

  Widget _loadMoreButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _visible += _pageSize),
          icon: const Icon(Icons.expand_more, color: FlowColors.primary),
          label: const Text('LOAD MORE',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.primary)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: FlowColors.primary, width: 1.5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label,
      {required this.flex, this.align = TextAlign.right});

  final String label;
  final int flex;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: FlowColors.goldRich),
      ),
    );
  }
}
