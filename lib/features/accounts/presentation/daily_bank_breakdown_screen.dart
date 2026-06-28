import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../data/daily_account_balance_repository.dart';
import '../data/daily_account_balance_model.dart';

class DailyBankBreakdownScreen extends StatefulWidget {
  const DailyBankBreakdownScreen({super.key, required this.date});
  final DateTime date;

  @override
  State<DailyBankBreakdownScreen> createState() =>
      _DailyBankBreakdownScreenState();
}

class _DailyBankBreakdownScreenState
    extends State<DailyBankBreakdownScreen> {
  bool _loading = true;
  bool _isLocked = false;
  List<DailyAccountTotals> _totals = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _isoDate =>
      '${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}';

  String get _displayDate =>
      '${widget.date.day.toString().padLeft(2, '0')}/'
      '${widget.date.month.toString().padLeft(2, '0')}/'
      '${widget.date.year}';

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('daily_balance',
        where: 'business_date = ?', whereArgs: [_isoDate]);
    final isLocked = rows.isNotEmpty && (rows.first['is_locked'] as int?) == 1;
    final dailyBalanceId =
        rows.isNotEmpty ? rows.first['id'] as int? : null;

    final totals = await DailyAccountBalanceRepository.instance
        .getTotalsForDate(_isoDate,
            isLocked: isLocked, dailyBalanceId: dailyBalanceId);

    if (mounted) {
      setState(() {
        _isLocked = isLocked;
        _totals = totals;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CMBColors.pageBackground,
      appBar: AppBar(
        backgroundColor: CMBColors.navy,
        foregroundColor: CMBColors.goldRich,
        title: const Text('Bank Breakdown'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
                children: [
                  _headerCard(),
                  const SizedBox(height: 12),
                  if (_totals.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Text(
                          'No bank accounts configured.',
                          style: TextStyle(
                              fontSize: 16,
                              color: CMBColors.textOnLight),
                        ),
                      ),
                    )
                  else ...[
                    ..._totals.map(_buildAccountCard),
                    _buildTotalCard(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _headerCard() {
    return Container(
      decoration: BoxDecoration(
        color: CMBColors.navy,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CMBColors.borderOnNavy, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _displayDate,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: CMBColors.textOnNavyLarge),
              ),
              const SizedBox(height: 2),
              Text(
                _isLocked ? 'LOCKED — showing frozen balances' : 'LIVE — totals computed from payments',
                style: const TextStyle(
                    fontSize: 12, color: CMBColors.textOnNavyMuted),
              ),
            ],
          ),
          const Spacer(),
          Icon(
            _isLocked ? Icons.lock : Icons.lock_open,
            color: _isLocked ? CMBColors.goldRich : CMBColors.textOnNavyMuted,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(DailyAccountTotals t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E4D9), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: CMBColors.navy,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(13)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.account_balance,
                    color: CMBColors.goldRich, size: 18),
                const SizedBox(width: 8),
                Text(
                  t.bankAccount.name,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: CMBColors.textOnNavyLarge),
                ),
                if (t.bankAccount.isDefault) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: CMBColors.goldRich.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('DEFAULT',
                        style: TextStyle(
                            fontSize: 10,
                            color: CMBColors.goldRich,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _balRow('Opening', t.openingBalance),
                _balRow('Bank In', t.amountIn, color: const Color(0xFF2E7D32)),
                _balRow('Bank Out', t.amountOut, color: const Color(0xFFC62828)),
                const Divider(height: 18, thickness: 0.8),
                _balRow('Closing', t.closingBalance,
                    bold: true,
                    color: t.closingBalance >= 0
                        ? CMBColors.navy
                        : const Color(0xFFC62828)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCard() {
    final total = _totals.fold(0.0, (s, t) => s + t.closingBalance);
    return Container(
      decoration: BoxDecoration(
        color: CMBColors.navy,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CMBColors.borderOnNavy, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TOTAL CLOSING BALANCE',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: CMBColors.textOnNavyMuted,
                  letterSpacing: 1.0)),
          const SizedBox(height: 8),
          Text(
            money(total),
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: total < 0
                    ? Colors.red[200]
                    : CMBColors.textOnNavyLarge),
          ),
        ],
      ),
    );
  }

  Widget _balRow(String label, double value,
      {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: bold ? CMBColors.navy : CMBColors.textOnLight,
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.normal)),
          Text(
            money(value),
            style: TextStyle(
                fontSize: bold ? 17 : 14,
                fontWeight:
                    bold ? FontWeight.w700 : FontWeight.w500,
                color: color ?? CMBColors.textOnLight),
          ),
        ],
      ),
    );
  }
}
