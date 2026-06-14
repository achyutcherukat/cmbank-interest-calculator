import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../features/admin/data/admin_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../data/gold_stock_repository.dart';
import 'gold_in_drill_down_screen.dart';
import 'gold_out_drill_down_screen.dart';

class GoldStockScreen extends StatefulWidget {
  const GoldStockScreen({super.key});

  @override
  State<GoldStockScreen> createState() => _GoldStockScreenState();
}

class _GoldStockScreenState extends State<GoldStockScreen> {
  late DateTime _selectedDate;
  DailyStockRecord? _record;
  List<PurityStock> _purities = [];
  double _goldRate = 0;
  bool _isAdmin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = _today;
    _isAdmin = AdminSession.isValid;
    _load();
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  bool get _canGoBack {
    final minDate = _isAdmin
        ? DateTime(2000)
        : _today.subtract(const Duration(days: 9));
    return _selectedDate.isAfter(minDate);
  }

  bool get _canGoForward => _selectedDate.isBefore(_today);

  void _prevDay() {
    if (!_canGoBack) return;
    setState(
        () => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
    _load();
  }

  void _nextDay() {
    if (!_canGoForward) return;
    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dateStr = _dateKey(_selectedDate);
      final results = await Future.wait([
        GoldStockRepository.instance.getOrCreateDayRecord(dateStr),
        GoldStockRepository.instance.getPurityBreakdown(),
        GoldStockRepository.instance.getGoldRate(),
      ]);
      if (mounted) {
        setState(() {
          _record = results[0] as DailyStockRecord;
          _purities = results[1] as List<PurityStock>;
          _goldRate = results[2] as double;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    final locked = record?.isLocked ?? false;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Gold Stock Register',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _dateNavBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      children: [
                        if (record != null) ...[
                          _dailyStockCard(record),
                          _stockValueCard(record),
                          _purityCard(),
                          if (locked && _isAdmin) _unlockCard(record),
                        ] else
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 40),
                              child: Text('No data for this date.',
                                  style: TextStyle(
                                      fontSize: 17, color: Colors.black45)),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          if (!locked && record != null) _bottomButtons(),
          if (locked && record != null) _lockedStatusBar(record),
        ],
      ),
    );
  }

  // ── Date nav bar ──────────────────────────────────────────────────────────────

  Widget _dateNavBar() {
    final isToday = _selectedDate == _today;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left,
                size: 32,
                color:
                    _canGoBack ? FlowColors.primary : Colors.black26),
            onPressed: _canGoBack ? _prevDay : null,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  isToday ? 'Today' : _weekdayLabel(_selectedDate),
                  style: TextStyle(
                    fontSize: 13,
                    color: isToday ? FlowColors.primary : FlowColors.medText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _displayDate(_selectedDate),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.darkText,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right,
                size: 32,
                color:
                    _canGoForward ? FlowColors.primary : Colors.black26),
            onPressed: _canGoForward ? _nextDay : null,
          ),
        ],
      ),
    );
  }

  String _weekdayLabel(DateTime d) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return days[d.weekday - 1];
  }

  // ── Daily Stock Card ──────────────────────────────────────────────────────────

  Widget _dailyStockCard(DailyStockRecord r) {
    final dateStr = _dateKey(_selectedDate);
    final displayDate = _displayDate(_selectedDate);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FlowColors.primary, width: 2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: FlowColors.primary,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2, color: FlowColors.goldRich, size: 20),
                const SizedBox(width: 10),
                const Text('DAILY STOCK',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: FlowColors.textOnNavySmall,
                        letterSpacing: 0.8)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _stockRow(Icons.lock_open, 'Opening Stock',
                    r.openingWeight, r.openingCount,
                    color: FlowColors.medText),
                const SizedBox(height: 2),
                const Divider(color: Color(0xFFEEEEEE)),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GoldInDrillDownScreen(
                          date: dateStr, displayDate: displayDate),
                    ),
                  ),
                  child: _stockRow(
                    Icons.add_circle,
                    'Gold IN',
                    r.goldInWeight,
                    r.goldInCount,
                    color: FlowColors.green,
                    tappable: true,
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GoldOutDrillDownScreen(
                          date: dateStr, displayDate: displayDate),
                    ),
                  ),
                  child: _stockRow(
                    Icons.remove_circle,
                    'Gold OUT',
                    r.goldOutWeight,
                    r.goldOutCount,
                    color: FlowColors.red,
                    tappable: true,
                  ),
                ),
                if (r.adjustmentWeight != 0 || r.adjustmentCount != 0) ...[
                  const SizedBox(height: 2),
                  _stockRow(
                    Icons.tune,
                    'Adjustment',
                    r.adjustmentWeight,
                    r.adjustmentCount,
                    color: FlowColors.orange,
                    signed: true,
                  ),
                ],
                const SizedBox(height: 2),
                const Divider(color: Color(0xFFEEEEEE)),
                const SizedBox(height: 4),
                _stockRow(
                  Icons.lock,
                  'Closing Stock',
                  r.closingWeight,
                  r.closingCount,
                  color: FlowColors.primary,
                  isBold: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stockRow(
    IconData icon,
    String label,
    double weight,
    int count, {
    Color color = FlowColors.darkText,
    bool tappable = false,
    bool isBold = false,
    bool signed = false,
  }) {
    final prefix = signed && weight > 0 ? '+' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isBold ? 17 : 16,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: color,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$prefix${weight.toStringAsFixed(2)} g',
                style: TextStyle(
                  fontSize: isBold ? 18 : 16,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color: color,
                ),
              ),
              Text(
                '$count item${count == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
          if (tappable)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.chevron_right, color: Colors.black38, size: 18),
            ),
        ],
      ),
    );
  }

  // ── Stock Value Card ──────────────────────────────────────────────────────────

  Widget _stockValueCard(DailyStockRecord r) {
    final estimatedValue = r.closingWeight * _goldRate;

    return FlowCard(
      backgroundColor: FlowColors.accent,
      borderColor: FlowColors.primaryLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: FlowColors.orange, size: 20),
              const SizedBox(width: 8),
              const Text('STOCK VALUE (REFERENCE ONLY)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black45,
                      letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r.closingWeight.toStringAsFixed(2)} g',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: FlowColors.darkText),
                  ),
                  const Text('Net Weight',
                      style: TextStyle(fontSize: 13, color: Colors.black54)),
                ],
              ),
              const Text('×',
                  style: TextStyle(fontSize: 22, color: Colors.black38)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _goldRate > 0
                        ? '₹${_goldRate.round()}/g'
                        : 'Rate not set',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _goldRate > 0
                            ? FlowColors.orange
                            : Colors.black38),
                  ),
                  const Text('Gold Rate',
                      style: TextStyle(fontSize: 13, color: Colors.black54)),
                ],
              ),
              const Text('=',
                  style: TextStyle(fontSize: 22, color: Colors.black38)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _goldRate > 0 ? money(estimatedValue) : '—',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: FlowColors.primary),
                  ),
                  const Text('Est. Value',
                      style: TextStyle(fontSize: 13, color: Colors.black54)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Estimated value based on current gold rate. For reference only.',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  // ── Purity Breakdown Card ─────────────────────────────────────────────────────

  Widget _purityCard() {
    if (_purities.isEmpty) {
      return FlowCard(
        header: 'PURITY BREAKDOWN (CURRENT OPEN STOCK)',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SizedBox(height: 8),
            Text('Purity data not available',
                style: TextStyle(fontSize: 16, color: Colors.black45)),
          ],
        ),
      );
    }

    return FlowCard(
      header: 'PURITY BREAKDOWN (CURRENT OPEN STOCK)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._purities.asMap().entries.map((e) {
            final p = e.value;
            final isLast = e.key == _purities.length - 1;
            return Container(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(
                        bottom: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: FlowColors.goldLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: FlowColors.gold),
                    ),
                    child: Text(
                      p.purity,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: FlowColors.orange),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('${p.count} item${p.count == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 15, color: FlowColors.medText)),
                  ),
                  Text(
                    '${p.grams.toStringAsFixed(2)} g',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: FlowColors.primary),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Unlock card (admin only) ──────────────────────────────────────────────────

  Widget _unlockCard(DailyStockRecord r) {
    return FlowCard(
      borderColor: FlowColors.orange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_open, color: FlowColors.orange, size: 20),
              const SizedBox(width: 8),
              const Text('ADMIN UNLOCK',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: FlowColors.orange,
                      letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'This day is locked. As admin, you can unlock it to allow edits.',
            style: TextStyle(fontSize: 15, color: FlowColors.medText),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.lock_open, size: 18),
              label: const Text('UNLOCK THIS DAY',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.orange,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _showUnlockDialog(r),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom buttons ────────────────────────────────────────────────────────────

  Widget _bottomButtons() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 58,
              child: OutlinedButton.icon(
                onPressed: _record == null ? null : _showAdjustSheet,
                icon: const Icon(Icons.tune),
                label: const Text('ADJUST STOCK',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FlowColors.medText,
                  side: const BorderSide(color: Colors.grey),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 58,
              child: ElevatedButton.icon(
                onPressed: _record == null ? null : _showVerifySheet,
                icon: const Icon(Icons.verified, color: FlowColors.goldRich),
                label: const Text('VERIFY STOCK',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: FlowColors.textOnNavySmall)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Locked status bar ─────────────────────────────────────────────────────────

  Widget _lockedStatusBar(DailyStockRecord r) {
    final hasDiscrepancy = r.hasDiscrepancy;
    final color = hasDiscrepancy ? FlowColors.orange : FlowColors.green;
    final bgColor = hasDiscrepancy ? FlowColors.orangeLight : FlowColors.greenLight;
    final icon = hasDiscrepancy ? Icons.warning_amber : Icons.check_circle;
    final label = hasDiscrepancy ? '🔒⚠️  Locked — Discrepancy noted' : '🔒✅  Locked — Verified';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(top: BorderSide(color: color, width: 1.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: color)),
                if (r.lockedAt != null)
                  Text(
                    'Locked at ${_formatLockedTime(r.lockedAt!)}${r.lockedBy != null ? ' by ${r.lockedBy}' : ''}',
                    style:
                        const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                if (hasDiscrepancy && r.discrepancyNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Note: ${r.discrepancyNote}',
                      style: TextStyle(fontSize: 13, color: color),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatLockedTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  // ── Bottom sheets ─────────────────────────────────────────────────────────────

  void _showAdjustSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdjustStockSheet(
        date: _dateKey(_selectedDate),
        displayDate: _displayDate(_selectedDate),
        onDone: () {
          Navigator.pop(context);
          _load();
        },
      ),
    );
  }

  void _showVerifySheet() {
    final record = _record;
    if (record == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VerifyStockSheet(
        record: record,
        isAdmin: _isAdmin,
        date: _dateKey(_selectedDate),
        displayDate: _displayDate(_selectedDate),
        onDone: () {
          Navigator.pop(context);
          _load();
        },
      ),
    );
  }

  void _showUnlockDialog(DailyStockRecord r) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlock Stock Day',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: FlowColors.orange)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This will allow edits to a locked day. Enter reason:',
                style: TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: FlowColors.orange),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(ctx);
              await GoldStockRepository.instance.unlockDay(
                date: _dateKey(_selectedDate),
                reason: reason,
                unlockedBy: 'Admin',
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Day unlocked — edits are now allowed.'),
                    backgroundColor: FlowColors.orange,
                  ),
                );
                _load();
              }
            },
            child: const Text('UNLOCK',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─── Adjust Stock Bottom Sheet ────────────────────────────────────────────────

class _AdjustStockSheet extends StatefulWidget {
  const _AdjustStockSheet({
    required this.date,
    required this.displayDate,
    required this.onDone,
  });

  final String date;
  final String displayDate;
  final VoidCallback onDone;

  @override
  State<_AdjustStockSheet> createState() => _AdjustStockSheetState();
}

class _AdjustStockSheetState extends State<_AdjustStockSheet> {
  bool _isAdd = true;
  final _weightCtrl = TextEditingController();
  final _countCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _weightCtrl.dispose();
    _countCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final weight = double.tryParse(_weightCtrl.text) ?? 0;
    final count = int.tryParse(_countCtrl.text) ?? 0;
    final reason = _reasonCtrl.text.trim();

    if (weight <= 0 && count <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter weight or item count to adjust.')),
      );
      return;
    }
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reason is required.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await GoldStockRepository.instance.adjustStock(
        date: widget.date,
        weight: weight,
        count: count,
        reason: reason,
        isAdd: _isAdd,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${_isAdd ? "Added" : "Removed"} ${weight.toStringAsFixed(2)} g, $count item${count == 1 ? '' : 's'}'),
            backgroundColor: FlowColors.green,
          ),
        );
        widget.onDone();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Adjust Stock — ${widget.displayDate}',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.darkText)),
            const SizedBox(height: 16),
            // Option cards
            Row(
              children: [
                Expanded(child: _optionCard(isAdd: true)),
                const SizedBox(width: 12),
                Expanded(child: _optionCard(isAdd: false)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _weightCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'Weight (grams)',
                prefixIcon: Icon(Icons.balance),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _countCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Item Count',
                prefixIcon: Icon(Icons.format_list_numbered),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason *',
                prefixIcon: Icon(Icons.edit_note),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                onPressed: _loading ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isAdd ? FlowColors.green : FlowColors.orange,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Text(
                        _isAdd ? 'CONFIRM — ADD STOCK' : 'CONFIRM — REMOVE STOCK',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionCard({required bool isAdd}) {
    final selected = _isAdd == isAdd;
    final color = isAdd ? FlowColors.green : FlowColors.orange;
    final bgColor = isAdd ? FlowColors.greenLight : FlowColors.orangeLight;
    final icon = isAdd ? Icons.add_circle : Icons.remove_circle;
    final label = isAdd ? 'ADD STOCK' : 'REMOVE STOCK';

    return GestureDetector(
      onTap: () => setState(() => _isAdd = isAdd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected ? bgColor : FlowColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.black26,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

// ─── Verify Stock Bottom Sheet ────────────────────────────────────────────────

class _VerifyStockSheet extends StatefulWidget {
  const _VerifyStockSheet({
    required this.record,
    required this.isAdmin,
    required this.date,
    required this.displayDate,
    required this.onDone,
  });

  final DailyStockRecord record;
  final bool isAdmin;
  final String date;
  final String displayDate;
  final VoidCallback onDone;

  @override
  State<_VerifyStockSheet> createState() => _VerifyStockSheetState();
}

class _VerifyStockSheetState extends State<_VerifyStockSheet> {
  final _weightCtrl = TextEditingController();
  final _countCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _loading = false;

  double get _expectedWeight => widget.record.closingWeight;
  int get _expectedCount => widget.record.closingCount;

  double get _actualWeight => double.tryParse(_weightCtrl.text) ?? -1;
  int get _actualCount => int.tryParse(_countCtrl.text) ?? -1;

  bool get _entered =>
      _weightCtrl.text.isNotEmpty && _countCtrl.text.isNotEmpty;

  double get _weightDiff => _entered ? _actualWeight - _expectedWeight : 0;
  int get _countDiff => _entered ? _actualCount - _expectedCount : 0;

  bool get _isMatch =>
      _entered && _weightDiff.abs() < 0.005 && _countDiff == 0;

  @override
  void dispose() {
    _weightCtrl.dispose();
    _countCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _lock() async {
    if (!_entered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter actual weight and item count.')),
      );
      return;
    }
    if (!_isMatch && _noteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a note explaining the discrepancy.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await GoldStockRepository.instance.verifyAndLock(
        date: widget.date,
        actualWeight: _actualWeight,
        actualCount: _actualCount,
        discrepancyNote: _isMatch ? null : _noteCtrl.text.trim(),
        lockedBy: widget.isAdmin ? 'Admin' : 'Staff',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isMatch
                ? '✅ Stock verified and locked!'
                : '⚠️ Stock locked with discrepancy note.'),
            backgroundColor: _isMatch ? FlowColors.green : FlowColors.orange,
          ),
        );
        widget.onDone();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weightDiffColor =
        _weightDiff.abs() < 0.005 ? FlowColors.green : FlowColors.red;
    final countDiffColor =
        _countDiff == 0 ? FlowColors.green : FlowColors.red;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Verify Stock — ${widget.displayDate}',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.darkText)),
              const SizedBox(height: 16),

              // Expected
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: FlowColors.accent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: FlowColors.primaryLight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('EXPECTED (SYSTEM)',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.black45,
                            letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _expectedTile('Weight',
                              '${_expectedWeight.toStringAsFixed(2)} g'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _expectedTile(
                              'Items', '$_expectedCount'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Actual inputs
              const Text('ACTUAL (PHYSICAL COUNT)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black45,
                      letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Actual Weight (g)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _countCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Actual Items',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Difference display
              if (_entered) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isMatch ? FlowColors.greenLight : FlowColors.redLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _isMatch ? FlowColors.green : FlowColors.red),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isMatch ? Icons.check_circle : Icons.warning_amber,
                            color: _isMatch ? FlowColors.green : FlowColors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isMatch
                                ? '✅ Stock verified! No discrepancy.'
                                : '⚠️ Difference found',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _isMatch ? FlowColors.green : FlowColors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _diffTile(
                              'Weight Diff',
                              '${_weightDiff >= 0 ? '+' : ''}${_weightDiff.toStringAsFixed(2)} g',
                              color: weightDiffColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _diffTile(
                              'Item Diff',
                              '${_countDiff >= 0 ? '+' : ''}$_countDiff',
                              color: countDiffColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Discrepancy note (shown only when mismatch)
              if (_entered && !_isMatch) ...[
                TextField(
                  controller: _noteCtrl,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Discrepancy Note *',
                    prefixIcon: Icon(Icons.edit_note),
                    border: OutlineInputBorder(),
                    helperText: 'Required when there is a discrepancy',
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Lock button
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _loading || !_entered ? null : _lock,
                  icon: Icon(
                    _isMatch ? Icons.lock : Icons.lock,
                    color: Colors.white,
                  ),
                  label: Text(
                    _isMatch ? 'LOCK STOCK' : 'LOCK ANYWAY',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isMatch ? FlowColors.green : FlowColors.orange,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expectedTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
      ],
    );
  }

  Widget _diffTile(String label, String value, {required Color color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
