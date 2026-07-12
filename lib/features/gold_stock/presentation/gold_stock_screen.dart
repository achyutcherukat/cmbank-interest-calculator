import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/non_business_day_service.dart';
import '../../../core/services/print_service.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../stock/stock_print_report.dart';
import '../../../features/admin/data/admin_repository.dart';
import '../../../features/auth/data/auth_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../../shared/widgets/restricted_action.dart';
import '../data/gold_stock_repository.dart';
import 'adjust_stock_screen.dart';
import 'gold_in_drill_down_screen.dart';
import 'gold_out_drill_down_screen.dart';

class GoldStockScreen extends StatefulWidget {
  const GoldStockScreen({super.key, this.initialDate});

  /// Date to open on, e.g. when linked from a specific Cash Book day.
  /// Defaults to today when omitted.
  final DateTime? initialDate;

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
  String? _firstStockDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? _today;
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
    if (_firstStockDate == null) return false;
    final first = DateTime.parse(_firstStockDate!);
    return _selectedDate.isAfter(first);
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

  // ─── Print / Save PDF (locked days only) ────────────────────────────────────

  void _showPrintSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            Text('Stock Register — ${_displayDate(_selectedDate)}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.primary)),
            ListTile(
              leading: const Icon(Icons.print, color: FlowColors.primary),
              title: const Text('Print'),
              onTap: () {
                Navigator.pop(ctx);
                _runPrint(save: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt, color: FlowColors.primary),
              title: const Text('Save as PDF'),
              onTap: () {
                Navigator.pop(ctx);
                _runPrint(save: true);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _runPrint({required bool save}) async {
    final dateStr = _dateKey(_selectedDate);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final doc = await StockPrintReport.generate(dateStr);
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading
      if (save) {
        await PrintService.saveAsPdf(
          pdf: doc,
          fileName: 'StockRegister_${_fileStamp(_selectedDate)}.pdf',
          context: context,
        );
      } else {
        await PrintService.printDocument(
          pdf: doc,
          documentName: 'Stock Register ${_displayDate(_selectedDate)}',
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate report: $e')),
      );
    }
  }

  String _fileStamp(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.year}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dateStr = _dateKey(_selectedDate);
      final results = await Future.wait([
        GoldStockRepository.instance.getOrCreateDayRecord(dateStr),
        GoldStockRepository.instance.getPurityBreakdown(),
        GoldStockRepository.instance.getGoldRate(),
        // Canonical boundary: reads from app_use_start_date setting;
        // falls back to MIN(stock_date) for installs predating this setting.
        AppSettingsRepository().getString('app_use_start_date'),
      ]);
      final String? firstDate = (results[3] as String?) ??
          await GoldStockRepository.instance.getFirstStockDate();
      if (mounted) {
        setState(() {
          _record = results[0] as DailyStockRecord;
          _purities = results[1] as List<PurityStock>;
          _goldRate = results[2] as double;
          _firstStockDate = firstDate;
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
        title: const Text('Stock Register',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        actions: [
          // Print / Save PDF — only for locked days (hidden otherwise to avoid
          // confusion for unlocked/today-not-yet-verified days).
          if (locked)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Print / Save PDF',
              onPressed: _showPrintSheet,
            ),
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
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24)
                          .withNavBarInset(context),
                      children: [
                        if (record != null) ...[
                          _dailyStockCard(record),
                          _stockValueCard(record),
                          _purityCard(),
                          if (locked) _unlockCard(record),
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
                    r.openingGrossWeight, r.openingWeight,
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
                    r.goldInGrossWeight,
                    r.goldInWeight,
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
                    r.goldOutGrossWeight,
                    r.goldOutWeight,
                    color: FlowColors.red,
                    tappable: true,
                  ),
                ),
                if (r.adjustmentWeight != 0) ...[
                  const SizedBox(height: 2),
                  _stockRow(
                    Icons.tune,
                    'Adjustment',
                    0.0,
                    r.adjustmentWeight,
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
                  r.closingGrossWeight,
                  r.closingWeight,
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
    double grossWeight,
    double netWeight, {
    Color color = FlowColors.darkText,
    bool tappable = false,
    bool isBold = false,
    bool signed = false,
  }) {
    final prefix = signed && netWeight > 0 ? '+' : '';
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
                'Gw: $prefix${grossWeight.toStringAsFixed(2)} g',
                style: TextStyle(
                  fontSize: isBold ? 16 : 14,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color: color,
                ),
              ),
              Text(
                'Nw: $prefix${netWeight.toStringAsFixed(2)} g',
                style: TextStyle(
                  fontSize: isBold ? 16 : 14,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color: color,
                ),
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
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${r.closingWeight.toStringAsFixed(2)} g',
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: FlowColors.darkText),
                      ),
                    ),
                    const Text('Net Weight',
                        style: TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                ),
              ),
              const Text('×',
                  style: TextStyle(fontSize: 22, color: Colors.black38)),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _goldRate > 0
                            ? '${money(_goldRate)}/g'
                            : 'Rate not set',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _goldRate > 0
                                ? FlowColors.orange
                                : Colors.black38),
                      ),
                    ),
                    const Text('Gold Rate',
                        style: TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                ),
              ),
              const Text('=',
                  style: TextStyle(fontSize: 22, color: Colors.black38)),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _goldRate > 0 ? money(estimatedValue) : '—',
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: FlowColors.primary),
                      ),
                    ),
                    const Text('Est. Value',
                        style: TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                ),
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

  // ── Unlock button (admin only) ───────────────────────────────────────────────

  Widget _unlockCard(DailyStockRecord r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RestrictedAction(
        child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          onPressed: () => _showUnlockDialog(r),
          icon: const Icon(Icons.lock_open, size: 20),
          label: const Text('UNLOCK STOCK (ADMIN)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: FlowColors.red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      ),
    );
  }

  // ── Bottom buttons ────────────────────────────────────────────────────────────

  Widget _bottomButtons() {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RestrictedAction(
              child: SizedBox(
                height: 50,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showAdjustStock,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('ADJUST STOCK',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlowColors.orangeLight,
                    foregroundColor: FlowColors.orange,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            RestrictedAction(
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _record == null ? null : _checkPrevDayAndVerify,
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
      ),
    );
  }

  Future<void> _showAdjustStock() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdjustStockScreen(
          dateStr: _dateKey(_selectedDate),
          displayDate: _displayDate(_selectedDate),
        ),
      ),
    );
    if (result == true && mounted) _load();
  }

  // ── Locked status bar ─────────────────────────────────────────────────────────

  Widget _lockedStatusBar(DailyStockRecord r) {
    final hasDiscrepancy = r.hasDiscrepancy;
    final color = hasDiscrepancy ? FlowColors.orange : FlowColors.green;
    final bgColor = hasDiscrepancy ? FlowColors.orangeLight : FlowColors.greenLight;
    final icon = hasDiscrepancy ? Icons.warning_amber : Icons.check_circle;
    final label = hasDiscrepancy ? '🔒⚠️  Locked — Discrepancy noted' : '🔒✅  Locked — Verified';

    return SafeArea(
      top: false,
      child: Container(
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
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black54),
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

  Future<void> _checkPrevDayAndVerify() async {
    final prevDate = _selectedDate.subtract(const Duration(days: 1));
    final prevIso = _dateKey(prevDate);

    // Before the first stock date → this is the very first stock day → allow.
    if (_firstStockDate == null || prevIso.compareTo(_firstStockDate!) < 0) {
      _showVerifySheet();
      return;
    }

    final prevRecord =
        await GoldStockRepository.instance.getForDate(prevIso);
    if (!mounted) return;

    // No row (never opened) or already locked → allow.
    // For Sundays with no row: also auto-close the cashbook side so the user
    // doesn't hit a cashbook block when closing the day later.
    if (prevRecord == null || prevRecord.isLocked) {
      if (prevRecord == null) {
        await NonBusinessDayService.autoCloseIfNonBusinessDay(prevIso);
        if (!mounted) return;
      }
      _showVerifySheet();
      return;
    }

    // Previous day exists but is unverified — auto-close if Sunday, else block.
    final isClosed =
        await NonBusinessDayService.autoCloseIfNonBusinessDay(prevIso);
    if (!mounted) return;
    if (isClosed) {
      _showVerifySheet();
      return;
    }
    _showPrevDayBlockedDialog(prevDate, prevIso);
  }

  void _showPrevDayBlockedDialog(DateTime prevDate, String prevIso) {
    final prevDisplay = _displayDate(prevDate);
    final curDisplay = _displayDate(_selectedDate);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Stock Not Verified',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: FlowColors.red),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cannot verify stock for $curDisplay. Stock for the previous day has not been verified yet. Please verify that day first.',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedDate = prevDate);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: FlowColors.orangeLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: FlowColors.orange),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today,
                          color: FlowColors.orange, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        prevDisplay,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: FlowColors.orange),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward,
                          color: FlowColors.orange, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(
                    fontSize: 16, color: FlowColors.primary)),
          ),
        ],
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
    final pinCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String? error;
    bool unlocking = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Unlock Stock — Admin Only',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.red)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FlowNoticeBox(
                  text: 'Unlocking allows edits. This action will be logged.',
                  color: FlowColors.orange,
                  backgroundColor: FlowColors.orangeLight,
                  icon: Icons.warning_amber,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  obscureText: true,
                  maxLength: 6,
                  decoration: const InputDecoration(
                      labelText: 'Admin PIN *',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Reason for unlock *',
                      border: OutlineInputBorder()),
                  maxLines: 2,
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 14)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.red,
                  foregroundColor: Colors.white),
              onPressed: unlocking
                  ? null
                  : () async {
                      if (pinCtrl.text.trim().isEmpty) {
                        setD(() => error = 'Enter admin PIN.');
                        return;
                      }
                      if (reasonCtrl.text.trim().isEmpty) {
                        setD(() => error = 'Reason is required.');
                        return;
                      }
                      final pinOk = await AuthRepository()
                          .verifyAdminPin(pinCtrl.text.trim());
                      if (!pinOk) {
                        setD(() => error = 'Incorrect PIN.');
                        return;
                      }
                      setD(() => unlocking = true);

                      final reason = reasonCtrl.text.trim();
                      await GoldStockRepository.instance.unlockDay(
                        date: _dateKey(_selectedDate),
                        reason: reason,
                      );

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _load();
                    },
              child: unlocking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('UNLOCK',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
            ),
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
  final _grossWeightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _loading = false;

  double get _expectedGrossWeight => widget.record.closingGrossWeight;
  double get _expectedWeight => widget.record.closingWeight;

  double get _actualGrossWeight =>
      double.tryParse(_grossWeightCtrl.text) ?? -1;
  double get _actualWeight => double.tryParse(_weightCtrl.text) ?? -1;

  bool get _entered =>
      _grossWeightCtrl.text.isNotEmpty && _weightCtrl.text.isNotEmpty;

  double get _grossDiff =>
      _entered ? _actualGrossWeight - _expectedGrossWeight : 0;
  double get _weightDiff => _entered ? _actualWeight - _expectedWeight : 0;

  bool get _isMatch =>
      _entered && _grossDiff.abs() < 0.005 && _weightDiff.abs() < 0.005;

  @override
  void initState() {
    super.initState();
    _grossWeightCtrl.text = widget.record.closingGrossWeight.toStringAsFixed(2);
    _weightCtrl.text = widget.record.closingWeight.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _grossWeightCtrl.dispose();
    _weightCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _lock() async {
    if (!_entered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter actual gross and net weight.')),
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
        actualGrossWeight: _actualGrossWeight,
        actualWeight: _actualWeight,
        discrepancyNote: _isMatch ? null : _noteCtrl.text.trim(),
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
    final grossDiffColor =
        _grossDiff.abs() < 0.005 ? FlowColors.green : FlowColors.red;
    final weightDiffColor =
        _weightDiff.abs() < 0.005 ? FlowColors.green : FlowColors.red;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28)
            .withNavBarInset(context),
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
                          child: _expectedTile('Gross Wt',
                              '${_expectedGrossWeight.toStringAsFixed(2)} g'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _expectedTile('Net Wt',
                              '${_expectedWeight.toStringAsFixed(2)} g'),
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
                      controller: _grossWeightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Actual Gross Wt (g)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                        labelText: 'Actual Net Wt (g)',
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
                              'Gross Diff',
                              '${_grossDiff >= 0 ? '+' : ''}${_grossDiff.toStringAsFixed(2)} g',
                              color: grossDiffColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _diffTile(
                              'Net Diff',
                              '${_weightDiff >= 0 ? '+' : ''}${_weightDiff.toStringAsFixed(2)} g',
                              color: weightDiffColor,
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
              RestrictedAction(
                child: SizedBox(
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
