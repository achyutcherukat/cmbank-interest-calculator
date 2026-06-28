import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../auth/data/auth_repository.dart';
import '../../../shared/widgets/pledge_id_search_popup.dart';
import '../../admin/data/audit_log_repository.dart';
import '../../gold_stock/data/gold_stock_repository.dart';
import '../../pledges/data/payment_model.dart';
import '../../pledges/data/payments_repository.dart';
import '../../pledges/data/pledge_model.dart';
import '../../pledges/data/pledge_repository.dart';
import '../../pledges/presentation/closed_pledges_screen.dart';
import '../../pledges/presentation/load_existing_pledge_screen.dart';
import '../../pledges/presentation/new_pledge_screen.dart';
import '../../pledges/presentation/open_pledge_screen.dart';
import '../../../shared/widgets/shared_split_payment_widget.dart';
import '../data/bank_account_repository.dart';
import 'adjust_balance_screen.dart';
import '../data/daily_balance_repository.dart';
import '../data/day_reconciliation_repository.dart';
import 'daily_bank_breakdown_screen.dart';

// ─── Main Screen ──────────────────────────────────────────────────────────────

class DailyAccountsScreen extends StatefulWidget {
  const DailyAccountsScreen({super.key});

  @override
  State<DailyAccountsScreen> createState() => _DailyAccountsScreenState();
}

class _DailyAccountsScreenState extends State<DailyAccountsScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  bool _isLocked = false;

  /// Canonical app start date (from app_use_start_date setting).
  /// Used to restrict date navigation and unlocked-day counting.
  String? _firstRecordDate;

  /// Previous days (ISO) that still have unlocked daily_balance rows. Only
  /// populated while viewing today; drives the warning banner and lock guard.
  List<String> _unlockedPrevDays = [];

  double _openingCash = 0;
  double _openingUpi = 0;

  List<Map<String, dynamic>> _inTxns = [];
  List<Map<String, dynamic>> _outTxns = [];
  Map<int, String> _bankAccountNames = {};

  // Computed totals. Each row carries split cash/upi amounts; adjustments are
  // ordinary payment rows (direction in/out) and fold in here automatically.
  double get _cashIn =>
      _inTxns.fold(0.0, (s, t) => s + (t['cash'] as num).toDouble());
  double get _upiIn =>
      _inTxns.fold(0.0, (s, t) => s + (t['upi'] as num).toDouble());
  double get _cashOut =>
      _outTxns.fold(0.0, (s, t) => s + (t['cash'] as num).toDouble());
  double get _upiOut =>
      _outTxns.fold(0.0, (s, t) => s + (t['upi'] as num).toDouble());

  double get _closingCash => _openingCash + _cashIn - _cashOut;
  double get _closingUpi => _openingUpi + _upiIn - _upiOut;

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  /// False when _selectedDate is already at the app's first record date.
  bool get _canGoBack {
    if (_firstRecordDate == null) return true;
    final parts = _firstRecordDate!.split('-');
    if (parts.length != 3) return true;
    final firstDt = DateTime(
        int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    return !(_selectedDate.year == firstDt.year &&
        _selectedDate.month == firstDt.month &&
        _selectedDate.day == firstDt.day);
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final dateStr = _iso(_selectedDate);

    // Opening balance + lock status.
    final record = await DailyBalanceRepository.instance.getForDate(dateStr);
    final isLocked = record?.isLocked ?? false;

    double openingCash, openingUpi;
    if (isLocked && record != null) {
      openingCash = record.openingCash;
      openingUpi = record.openingUpi;
    } else {
      final totals =
          await DailyBalanceRepository.instance.calculateTotalsForDate(dateStr);
      openingCash = totals.openingCash;
      openingUpi = totals.openingUpi;
    }

    // Money IN / OUT rows from the payments ledger (adjustments included).
    final inPayments =
        await PaymentsRepository.instance.getPaymentsInForDate(dateStr);
    final outPayments =
        await PaymentsRepository.instance.getPaymentsOutForDate(dateStr);

    // Resolve pledge details for linked rows (cached per pledge).
    final ids = <int>{
      for (final p in inPayments)
        if (p.pledgeId != null) p.pledgeId!,
      for (final p in outPayments)
        if (p.pledgeId != null) p.pledgeId!,
    };
    final pledgeCache = <int, PledgeModel?>{};
    for (final id in ids) {
      pledgeCache[id] = await PledgeRepository.instance.getPledgeById(id);
    }

    final allAccounts = await BankAccountRepository.instance.getAll();
    _bankAccountNames = {
      for (final a in allAccounts) if (a.id != null) a.id!: a.name,
    };

    final inMapped = inPayments
        .map((p) =>
            _mapPayment(p, p.pledgeId == null ? null : pledgeCache[p.pledgeId]))
        .toList();
    final outMapped = outPayments
        .map((p) =>
            _mapPayment(p, p.pledgeId == null ? null : pledgeCache[p.pledgeId]))
        .toList();

    // Canonical app start date — restricts navigation and unlocked-day
    // counting. Reads directly from the setting written at first-launch setup;
    // falls back to MIN(business_date) only for installs predating this setting.
    String? firstDate =
        await AppSettingsRepository().getString('app_use_start_date');
    firstDate ??= await DailyBalanceRepository.instance.getFirstRecordDate();

    // Unclosed previous days — only queried on today's screen.
    // Counts both days with no daily_balance row (never closed) and days with
    // is_locked = 0 (admin-unlocked). Requires firstDate so we don't walk
    // the entire calendar back to year zero.
    List<String> unlockedPrev = <String>[];
    if (_isToday && firstDate != null) {
      unlockedPrev = await DailyBalanceRepository.instance
          .getUnclosedDaysBefore(_iso(DateTime.now()), fromDate: firstDate);
    }

    if (mounted) {
      setState(() {
        _openingCash = openingCash;
        _openingUpi = openingUpi;
        _inTxns = inMapped;
        _outTxns = outMapped;
        _isLocked = isLocked;
        _firstRecordDate = firstDate;
        _unlockedPrevDays = unlockedPrev;
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _mapPayment(PaymentModel p, PledgeModel? pledge) {
    return {
      'id': p.id,
      'amount': p.amount,
      'cash': p.cashAmount,
      'upi': p.bankAmount,
      'bank_account_name': p.bankAccountId != null
          ? _bankAccountNames[p.bankAccountId]
          : null,
      'payment_type': p.paymentType,
      'sub_category': p.subCategory,
      'direction': p.direction,
      'notes': p.notes,
      'pledge_id': p.pledgeId,
      'pledge_no': pledge?.pledgeNumber ?? '',
      'pledge_status': pledge?.status ?? '',
      'customer_name': pledge?.customerName ?? '',
    };
  }

  void _changeDate(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    _loadData();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Cash Book'),
        actions: [
          if (_isLocked)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Icon(Icons.lock, color: Colors.greenAccent),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildDateNav(),
          if (_isLocked) _buildLockedBanner(),
          if (_isToday && _unlockedPrevDays.isNotEmpty)
            _buildUnlockedPrevBanner(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildOpeningCard(),
                        const SizedBox(height: 12),
                        _buildInOutRow(),
                        const SizedBox(height: 12),
                        _buildClosingCard(),
                        const SizedBox(height: 22),
                        if (!_isLocked) ...[
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 54,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AdjustBalanceScreen(
                                              date: _selectedDate),
                                        ),
                                      );
                                      _loadData();
                                    },
                                    icon: const Icon(Icons.tune, size: 18),
                                    label: const Text('ADJUST BALANCE',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: FlowColors.primaryLight,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 54,
                                  child: ElevatedButton.icon(
                                    onPressed: _showAddExpense,
                                    icon: const Icon(Icons.receipt_long,
                                        size: 18),
                                    label: const Text('ADD EXPENSE',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: FlowColors.primaryLight,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildActionBtn(
                            label: 'VERIFY & CLOSE DAY',
                            icon: Icons.lock_outline,
                            color: FlowColors.primary,
                            foregroundColor: FlowColors.textOnNavyLarge,
                            borderSide: const BorderSide(
                                color: FlowColors.borderOnNavy, width: 0.8),
                            onTap: _showReconcile,
                          ),
                          // Backdated-entry actions: only on a past unlocked day.
                          if (!_isToday) ...[
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 54,
                                    child: OutlinedButton.icon(
                                      onPressed: _addOpenPledgeForDay,
                                      icon: const Icon(
                                          Icons.add_circle_outline,
                                          size: 18,
                                          color: FlowColors.primary),
                                      label: const Text('ADD OPEN PLEDGE',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: FlowColors.primary)),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: FlowColors.primary,
                                            width: 1.5),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SizedBox(
                                    height: 54,
                                    child: OutlinedButton.icon(
                                      onPressed: _recordClosureForDay,
                                      icon: const Icon(Icons.lock,
                                          size: 18,
                                          color: FlowColors.primary),
                                      label: const Text('RECORD CLOSURE',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: FlowColors.primary)),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: FlowColors.primary,
                                            width: 1.5),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ] else
                          _buildActionBtn(
                            label: 'UNLOCK DAY (ADMIN)',
                            icon: Icons.lock_open,
                            color: FlowColors.red,
                            onTap: _showUnlock,
                          ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─── Date Navigator ───────────────────────────────────────────────────────

  Widget _buildDateNav() {
    final pastUnlocked = !_isToday && !_isLocked;
    final label = _isToday
        ? 'Today  ${_fmt(_selectedDate)}'
        : pastUnlocked
            ? '⚠ ${_fmt(_selectedDate)} (Unlocked)'
            : _fmt(_selectedDate);
    final labelColor = pastUnlocked ? FlowColors.orange : FlowColors.primary;
    return Container(
      color: FlowColors.accent,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left,
                size: 32,
                color: _canGoBack ? FlowColors.primary : Colors.black26),
            onPressed: _canGoBack ? () => _changeDate(-1) : null,
          ),
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: labelColor)),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right,
                size: 32,
                color: _isToday ? Colors.black26 : FlowColors.primary),
            onPressed: _isToday ? null : () => _changeDate(1),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    DateTime firstDate = DateTime(2020);
    if (_firstRecordDate != null) {
      final parts = _firstRecordDate!.split('-');
      if (parts.length == 3) {
        firstDate = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: firstDate,
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: FlowColors.primary,
              onPrimary: Colors.white,
              onSurface: Colors.black),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadData();
    }
  }

  // ─── Cards ────────────────────────────────────────────────────────────────

  Widget _buildLockedBanner() {
    return Container(
      width: double.infinity,
      color: FlowColors.green,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: const Row(
        children: [
          Icon(Icons.lock, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Text('Day is locked — no edits allowed',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildOpeningCard() {
    return FlowCard(
      backgroundColor: FlowColors.accent,
      borderColor: FlowColors.primaryLight,
      header: 'Opening Balance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: _miniBalance('CASH', _openingCash, Icons.payments)),
              const SizedBox(width: 16),
              Expanded(
                  child: _miniBalance(
                      'Bank', _openingUpi, Icons.account_balance)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInOutRow() {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            title: 'MONEY IN',
            cash: _cashIn,
            upi: _upiIn,
            icon: Icons.arrow_downward,
            color: FlowColors.green,
            bgColor: FlowColors.greenLight,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => _MoneyInScreen(
                      date: _fmt(_selectedDate), txns: _inTxns)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            title: 'MONEY OUT',
            cash: _cashOut,
            upi: _upiOut,
            icon: Icons.arrow_upward,
            color: FlowColors.red,
            bgColor: FlowColors.redLight,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => _MoneyOutScreen(
                      date: _fmt(_selectedDate), txns: _outTxns)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String title,
    required double cash,
    required double upi,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 1.5),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 8,
                offset: Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                          letterSpacing: 0.8)),
                ),
                Icon(Icons.chevron_right, color: color, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(money(cash + upi),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const SizedBox(height: 6),
            _modeRow('Cash', cash, color),
            const SizedBox(height: 2),
            _modeRow('Bank', upi, color),
          ],
        ),
      ),
    );
  }

  Widget _buildClosingCard() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => DailyBankBreakdownScreen(date: _selectedDate)),
      ).then((_) => _loadData()),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: FlowColors.primary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CLOSING BALANCE',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: FlowColors.textOnNavyMuted,
                    letterSpacing: 1.0)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: _closingItem('CASH', _closingCash, Icons.payments)),
                Container(
                    width: 1,
                    height: 50,
                    color: FlowColors.borderOnNavy,
                    margin: const EdgeInsets.symmetric(horizontal: 12)),
                Expanded(
                    child: _closingItem(
                        'Bank', _closingUpi, Icons.account_balance)),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: FlowColors.borderOnNavy, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL',
                    style: TextStyle(
                        fontSize: 14,
                        color: FlowColors.textOnNavySmall,
                        fontWeight: FontWeight.w600)),
                Text(money(_closingCash + _closingUpi),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: FlowColors.textOnNavyLarge)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _closingItem(String label, double amount, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: FlowColors.goldRich, size: 13),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 11, color: FlowColors.textOnNavySmall)),
        ]),
        const SizedBox(height: 4),
        Text(money(amount),
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: amount < 0 ? Colors.red[200] : FlowColors.textOnNavyLarge)),
      ],
    );
  }

  Widget _buildActionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    Color foregroundColor = Colors.white,
    BorderSide? borderSide,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: foregroundColor,
          side: borderSide,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _miniBalance(String label, double amount, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: FlowColors.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600)),
            Text(money(amount),
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.primary)),
          ],
        ),
      ],
    );
  }

  Widget _modeRow(String label, double amount, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                TextStyle(fontSize: 12, color: color.withAlpha(180))),
        Text(money(amount),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color)),
      ],
    );
  }

  // ─── Add Expense ──────────────────────────────────────────────────────────

  Future<void> _showAddExpense() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'expense_categories',
      columns: ['name'],
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
    final cats = rows.map((r) => r['name'] as String).toList();
    final accounts = await BankAccountRepository.instance.getActive();

    if (!mounted) return;

    final payKey = GlobalKey<SharedSplitPaymentWidgetState>();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? selectedCat;
    double expTotal = 0;
    String? error;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 16),
                  const Text('Add Expense',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: FlowColors.primary)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [IndianNumberFormatter()],
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹) *',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final parsed =
                          double.tryParse(v.replaceAll(',', '')) ?? 0;
                      setBS(() {
                        expTotal = parsed;
                        if (error != null) error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCat,
                    decoration: const InputDecoration(
                        labelText: 'Category *',
                        border: OutlineInputBorder()),
                    items: cats
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setBS(() => selectedCat = v),
                  ),
                  const SizedBox(height: 16),
                  SharedSplitPaymentWidget(
                    key: payKey,
                    total: expTotal,
                    totalLabel: 'Expense Amount',
                    bankAccounts: accounts,
                    isMoneyIn: false,
                    showTotalBanner: false,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 14)),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel',
                              style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: FlowColors.orange,
                              foregroundColor: Colors.white),
                          onPressed: saving
                              ? null
                              : () async {
                                  final amt = int.tryParse(
                                      amountCtrl.text.replaceAll(',', '').trim());
                                  if (amt == null || amt <= 0) {
                                    setBS(() =>
                                        error = 'Enter a valid amount.');
                                    return;
                                  }
                                  if (selectedCat == null) {
                                    setBS(() =>
                                        error = 'Select a category.');
                                    return;
                                  }
                                  final payState = payKey.currentState;
                                  final payErr = payState?.validate();
                                  if (payErr != null) {
                                    setBS(() => error = payErr);
                                    return;
                                  }
                                  final cashAmt =
                                      payState?.cashAmount ?? amt.toDouble();
                                  final bankAmt = payState?.bankAmount ?? 0;
                                  final bankAccId = payState?.bankAccountId;
                                  setBS(() => saving = true);
                                  final catLabel = selectedCat!;
                                  final notes = notesCtrl.text.trim();
                                  await PaymentsRepository.instance
                                      .createExpense(
                                    amt.toDouble(),
                                    cashAmt,
                                    bankAmt,
                                    catLabel,
                                    _iso(_selectedDate),
                                    bankAccountId: bankAccId,
                                    notes: notes.isEmpty ? null : notes,
                                  );
                                  await AuditLogRepository.instance.log(
                                    actionCategory:
                                        AuditCategory.dayManagement,
                                    action: 'EXPENSE_ADDED',
                                    entityType: 'payments',
                                    entityId: _iso(_selectedDate),
                                    reason: catLabel,
                                  );
                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                  _loadData();
                                },
                          child: saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Text('SAVE',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  // ─── Reconcile & Lock ─────────────────────────────────────────────────────

  void _showReconcile() {
    _checkPrevDayAndLock();
  }

  /// Generic guard: a day can only be locked when the immediately preceding
  /// day is already locked (or predates the app's first-ever record).
  Future<void> _checkPrevDayAndLock() async {
    final prevDate = _selectedDate.subtract(const Duration(days: 1));
    final prevIso = _iso(prevDate);

    // No records exist at all → app's very first close. Nothing to enforce.
    if (_firstRecordDate == null) {
      _navigateToReconcile();
      return;
    }

    // prevDate is before the first-ever record → locking the first day. Allow.
    if (prevIso.compareTo(_firstRecordDate!) < 0) {
      _navigateToReconcile();
      return;
    }

    final prevRecord =
        await DailyBalanceRepository.instance.getForDate(prevIso);
    if (!mounted) return;

    // Block when prevDate was never closed (null = no row) OR was admin-unlocked.
    if (prevRecord == null || !prevRecord.isLocked) {
      _showPrevDayBlockedDialog(prevDate, prevIso);
      return;
    }

    if (!mounted) return;
    _navigateToReconcile();
  }

  void _showPrevDayBlockedDialog(DateTime prevDate, String prevIso) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Cannot Lock ${_fmt(_selectedDate)}',
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: FlowColors.orange),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The previous day ${_fmt(prevDate)} has unlocked entries. '
                'Please verify and close that day first.',
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _goToDay(prevIso);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: FlowColors.orangeLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: FlowColors.orange),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_busy,
                          color: FlowColors.orange, size: 18),
                      const SizedBox(width: 10),
                      Text(_fmt(prevDate),
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: FlowColors.darkText)),
                      const Spacer(),
                      const Icon(Icons.chevron_right,
                          color: FlowColors.orange, size: 18),
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
            child: const Text('DISMISS',
                style: TextStyle(fontSize: 16, color: FlowColors.primary)),
          ),
        ],
      ),
    );
  }

  void _navigateToReconcile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ReconcileScreen(
          dateStr: _iso(_selectedDate),
          displayDate: _fmt(_selectedDate),
          openingCash: _openingCash,
          openingUpi: _openingUpi,
          cashIn: _cashIn,
          upiIn: _upiIn,
          cashOut: _cashOut,
          upiOut: _upiOut,
          expectedCash: _closingCash,
          expectedUpi: _closingUpi,
          onLocked: () {
            Navigator.pop(context);
            _loadData();
          },
        ),
      ),
    );
  }

  // ─── Unlocked previous days (banner + dialog + navigation) ─────────────────

  String _isoFmt(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  void _goToDay(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return;
    final d = DateTime(
        int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    setState(() => _selectedDate = d);
    _loadData();
  }

  Widget _buildUnlockedPrevBanner() {
    return GestureDetector(
      onTap: () => _showUnlockedDaysDialog(
        title: 'Unlocked Previous Days',
        intro: 'These previous days still have unlocked entries. '
            'Tap a day to review and lock it:',
      ),
      child: Container(
        width: double.infinity,
        color: FlowColors.orangeLight,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.warning_amber,
                color: FlowColors.orange, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_unlockedPrevDays.length} day(s) need to be verified and closed.',
                style: const TextStyle(
                    color: FlowColors.orange,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.chevron_right, color: FlowColors.orange, size: 20),
          ],
        ),
      ),
    );
  }

  void _showUnlockedDaysDialog({required String title, required String intro}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: FlowColors.orange)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(intro,
                  style: const TextStyle(fontSize: 14, color: Colors.black54)),
              const SizedBox(height: 12),
              ..._unlockedPrevDays.map((iso) => InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _goToDay(iso);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: FlowColors.orangeLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: FlowColors.orange),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event_busy,
                              color: FlowColors.orange, size: 18),
                          const SizedBox(width: 10),
                          Text(_isoFmt(iso),
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: FlowColors.darkText)),
                          const Spacer(),
                          const Icon(Icons.chevron_right,
                              color: FlowColors.orange, size: 18),
                        ],
                      ),
                    ),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('DISMISS',
                style: TextStyle(fontSize: 16, color: FlowColors.primary)),
          ),
        ],
      ),
    );
  }

  // ─── Backdated entry actions (past unlocked day) ───────────────────────────

  void _showGoldLockError() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gold Stock Locked',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: FlowColors.red)),
        content: Text(
          'Gold stock for ${_fmt(_selectedDate)} is locked. Please ask admin '
          'to unlock the gold stock register for this date before adding '
          'entries.',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(fontSize: 16, color: FlowColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<bool> _goldStockBlocked() async {
    final locked =
        await GoldStockRepository.instance.isDateLocked(_iso(_selectedDate));
    if (!mounted) return true;
    if (locked) {
      _showGoldLockError();
      return true;
    }
    return false;
  }

  Future<void> _addOpenPledgeForDay() async {
    if (await _goldStockBlocked()) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => NewPledgeScreen(contextDate: _selectedDate)),
    );
    if (mounted) _loadData();
  }

  Future<void> _recordClosureForDay() async {
    if (await _goldStockBlocked()) return;
    if (!mounted) return;
    final ctxDate = _selectedDate;
    showPledgeIdSearchPopup(
      context,
      contextDate: ctxDate,
      onPledgeFound: (pledge) async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PledgeDetailScreen(pledgeId: pledge.id!, contextDate: ctxDate),
          ),
        );
        if (mounted) _loadData();
      },
      onPledgeNotFound: (pledgeId) async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LoadExistingPledgeScreen(
              prefilledPledgeId: pledgeId,
              openDateEditable: true,
              closeDate: ctxDate,
              closeDateEditable: false,
              sourceContext: 'daily_accounts',
              contextDate: ctxDate,
            ),
          ),
        );
        if (mounted) _loadData();
      },
    );
  }

  // ─── Unlock Day ───────────────────────────────────────────────────────────

  void _showUnlock() {
    final pinCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String? error;
    bool unlocking = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Unlock Day — Admin Only',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.red)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FlowNoticeBox(
                  text:
                      'Unlocking allows edits. This action will be logged.',
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

                      final dateStr = _iso(_selectedDate);
                      final reason = reasonCtrl.text.trim();

                      await DailyBalanceRepository.instance.unlockDay(dateStr);
                      await DayReconciliationRepository.instance
                          .unlockReconciliation(date: dateStr, reason: reason);
                      await AuditLogRepository.instance.log(
                        actionCategory: AuditCategory.dayManagement,
                        action: 'DAY_UNLOCKED',
                        entityType: 'daily_balance',
                        entityId: dateStr,
                        oldValueJson: '{"is_locked":1}',
                        newValueJson: '{"is_locked":0}',
                        reason: reason,
                      );

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _loadData();
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

// ─── Money IN Drill-down ──────────────────────────────────────────────────────

class _MoneyInScreen extends StatefulWidget {
  const _MoneyInScreen({required this.date, required this.txns});
  final String date;
  final List<Map<String, dynamic>> txns;

  @override
  State<_MoneyInScreen> createState() => _MoneyInScreenState();
}

class _MoneyInScreenState extends State<_MoneyInScreen> {
  String _filter = 'all';

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'cash') {
      return widget.txns
          .where((t) => (t['cash'] as num).toDouble() > 0)
          .toList();
    } else if (_filter == 'bank') {
      return widget.txns
          .where((t) => (t['upi'] as num).toDouble() > 0)
          .toList();
    }
    return widget.txns;
  }

  String _group(Map<String, dynamic> t) {
    final payType = t['payment_type'] as String? ?? '';
    return payType == 'ADJUSTMENT' ? 'adjustment' : 'loan';
  }

  List<Map<String, dynamic>> get _adjustments =>
      _filtered.where((t) => _group(t) == 'adjustment').toList();
  List<Map<String, dynamic>> get _loans =>
      _filtered.where((t) => _group(t) == 'loan').toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.green,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Money IN',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.date,
                style:
                    const TextStyle(fontSize: 13, color: Colors.white70)),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildFilterTabs(),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('No entries for this filter.',
                        style: TextStyle(
                            color: Colors.black54, fontSize: 16)))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_adjustments.isNotEmpty) ...[
                        _sectionLabel('Adjustments'),
                        ..._adjustments.map(_buildCard),
                      ],
                      if (_loans.isNotEmpty) ...[
                        _sectionLabel('Loans Closed'),
                        ..._loans.map(_buildCard),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
              letterSpacing: 0.5)),
    );
  }

  Widget _buildFilterTabs() {
    final allTotal = widget.txns.fold(
        0.0, (s, t) => s + (t['amount'] as num).toDouble());
    final cashTotal = widget.txns
        .where((t) => (t['cash'] as num).toDouble() > 0)
        .fold(0.0, (s, t) => s + (t['cash'] as num).toDouble());
    final upiTotal = widget.txns
        .where((t) => (t['upi'] as num).toDouble() > 0)
        .fold(0.0, (s, t) => s + (t['upi'] as num).toDouble());

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _filterChip('all', 'ALL', money(allTotal)),
          const SizedBox(width: 8),
          _filterChip('cash', 'CASH', money(cashTotal)),
          const SizedBox(width: 8),
          _filterChip('bank', 'BANK', money(upiTotal)),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label, String total) {
    final selected = _filter == value;
    final icon = value == 'cash'
        ? Icons.payments
        : value == 'bank'
            ? Icons.account_balance
            : Icons.format_list_bulleted;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected ? FlowColors.green : FlowColors.greenLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon,
                      size: 13,
                      color: selected ? Colors.white : FlowColors.green),
                  const SizedBox(width: 4),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : FlowColors.green)),
                ],
              ),
              Text(total,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : FlowColors.green)),
            ],
          ),
        ),
      ),
    );
  }

  void _openPledge(Map<String, dynamic> t) {
    final pledgeId = t['pledge_id'] as int?;
    if (pledgeId == null) return;
    final status = (t['pledge_status'] as String?) ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => status == 'open'
            ? PledgeDetailScreen(pledgeId: pledgeId)
            : ClosedPledgeDetailScreen(pledgeId: pledgeId),
      ),
    );
  }

  String _moneyInLabel(String payType, String subCat) {
    switch (payType) {
      case 'LOAN_FULL_CLOSURE':
        return 'Pledge Closed';
      case 'RENEWAL_INTEREST_PAID':
        return 'Renewal Interest';
      case 'PART_PAYMENT_RECEIVED':
        return subCat == 'FIXED_AMOUNT_INCLUSIVE'
            ? 'Part Payment — Fixed Amount'
            : 'Part Payment — Principal & Interest';
      case 'ADJUSTMENT':
        switch (subCat) {
          case 'ADD_CASH':     return 'Cash Added';
          case 'ADD_BANK':     return 'Added Money to Bank Account';
          case 'ADD_UPI':      return 'UPI Added';
          case 'CASH_TO_BANK': return 'Transfer : Cash to Bank';
          case 'BANK_TO_CASH': return 'Transfer : Bank to Cash';
          case 'BANK_TO_BANK': return 'Transfer : Bank to Bank';
          case 'CASH_TO_UPI':  return 'Transfer : Cash to UPI';
          case 'UPI_TO_CASH':  return 'Transfer : UPI to Cash';
          default:             return 'Adjustment';
        }
      default:
        return payType;
    }
  }

  Widget _buildCard(Map<String, dynamic> t) {
    final pledgeNo = t['pledge_no']?.toString() ?? '';
    final pledgeId = t['pledge_id'] as int?;
    final payType = (t['payment_type'] as String?) ?? '';
    final subCat = (t['sub_category'] as String?) ?? '';
    final typeLabel = _moneyInLabel(payType, subCat);
    final cash = (t['cash'] as num).toDouble();
    final upi = (t['upi'] as num).toDouble();
    final total = (t['amount'] as num).toDouble();
    final bankName = t['bank_account_name'] as String?;
    final bankLabel = bankName != null ? 'Bank ($bankName)' : 'Bank';
    final customer = (t['customer_name'] as String?) ?? '';
    final notes = (t['notes'] as String?) ?? '';
    final isAdjustment = payType == 'ADJUSTMENT';
    final isSplit = cash > 0 && upi > 0;
    final tappable = pledgeId != null && pledgeNo.isNotEmpty;

    return GestureDetector(
      onTap: tappable ? () => _openPledge(t) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FlowColors.primaryLight),
        ),
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: FlowColors.greenLight,
            child: Icon(Icons.arrow_downward,
                color: FlowColors.green, size: 20),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  pledgeNo.isNotEmpty ? 'Pledge #$pledgeNo' : typeLabel,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: tappable ? FlowColors.primary : null),
                ),
              ),
              if (tappable)
                const Icon(Icons.chevron_right,
                    size: 18, color: Colors.black38),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (customer.isNotEmpty)
                Text(customer,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
              if (!isAdjustment && typeLabel.isNotEmpty)
                Text(typeLabel,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
              if (isAdjustment && notes.isNotEmpty)
                Text(notes,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
              if (isSplit)
                Text('Cash: ${money(cash)}   $bankLabel: ${money(upi)}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black45))
              else if (cash > 0)
                const Text('Cash',
                    style: TextStyle(fontSize: 12, color: Colors.black45))
              else if (upi > 0)
                Text(bankLabel,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black45)),
            ],
          ),
          trailing: Text(money(total),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.green)),
          isThreeLine: customer.isNotEmpty,
        ),
      ),
    );
  }
}

// ─── Money OUT Drill-down ─────────────────────────────────────────────────────

class _MoneyOutScreen extends StatefulWidget {
  const _MoneyOutScreen({required this.date, required this.txns});
  final String date;
  final List<Map<String, dynamic>> txns;

  @override
  State<_MoneyOutScreen> createState() => _MoneyOutScreenState();
}

class _MoneyOutScreenState extends State<_MoneyOutScreen> {
  String _filter = 'all';

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'cash') {
      return widget.txns
          .where((t) => (t['cash'] as num).toDouble() > 0)
          .toList();
    } else if (_filter == 'bank') {
      return widget.txns
          .where((t) => (t['upi'] as num).toDouble() > 0)
          .toList();
    }
    return widget.txns;
  }

  String _group(Map<String, dynamic> t) {
    switch (t['payment_type'] as String? ?? '') {
      case 'EXPENSE':
        return 'expense';
      case 'ADJUSTMENT':
        return 'adjustment';
      default:
        return 'loan';
    }
  }

  List<Map<String, dynamic>> get _loans =>
      _filtered.where((t) => _group(t) == 'loan').toList();
  List<Map<String, dynamic>> get _expenses =>
      _filtered.where((t) => _group(t) == 'expense').toList();
  List<Map<String, dynamic>> get _adjustments =>
      _filtered.where((t) => _group(t) == 'adjustment').toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.red,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Money OUT',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.date,
                style:
                    const TextStyle(fontSize: 13, color: Colors.white70)),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildFilterTabs(),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('No entries for this filter.',
                        style: TextStyle(
                            color: Colors.black54, fontSize: 16)))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_loans.isNotEmpty) ...[
                        _sectionLabel('Loans Disbursed'),
                        ..._loans.map(_buildCard),
                      ],
                      if (_expenses.isNotEmpty) ...[
                        _sectionLabel('Expenses'),
                        ..._expenses.map(_buildCard),
                      ],
                      if (_adjustments.isNotEmpty) ...[
                        _sectionLabel('Adjustments'),
                        ..._adjustments.map(_buildCard),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final cashTotal =
        widget.txns.fold(0.0, (s, t) => s + (t['cash'] as num).toDouble());
    final upiTotal =
        widget.txns.fold(0.0, (s, t) => s + (t['upi'] as num).toDouble());
    final allTotal = cashTotal + upiTotal;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _filterChip('all', 'ALL', money(allTotal)),
          const SizedBox(width: 8),
          _filterChip('cash', 'CASH', money(cashTotal)),
          const SizedBox(width: 8),
          _filterChip('bank', 'BANK', money(upiTotal)),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label, String total) {
    final selected = _filter == value;
    final icon = value == 'cash'
        ? Icons.payments
        : value == 'bank'
            ? Icons.account_balance
            : Icons.format_list_bulleted;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected ? FlowColors.red : FlowColors.redLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon,
                      size: 13,
                      color: selected ? Colors.white : FlowColors.red),
                  const SizedBox(width: 4),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : FlowColors.red)),
                ],
              ),
              Text(total,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : FlowColors.red)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
              letterSpacing: 0.5)),
    );
  }

  void _openPledge(Map<String, dynamic> t) {
    final pledgeId = t['pledge_id'] as int?;
    if (pledgeId == null) return;
    final status = (t['pledge_status'] as String?) ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => status == 'open'
            ? PledgeDetailScreen(pledgeId: pledgeId, hideActions: true)
            : ClosedPledgeDetailScreen(pledgeId: pledgeId),
      ),
    );
  }

  String _moneyOutLabel(String payType, String subCat) {
    switch (payType) {
      case 'LOAN_DISBURSED':
        return 'New Pledge';
      case 'LOAN_INCREASE_DISBURSED':
        return subCat == 'INTEREST_CAPITALISED'
            ? 'Loan Top-Up — Interest Added'
            : 'Loan Top-Up — Interest Paid';
      case 'EXPENSE':
        return subCat.isNotEmpty ? subCat : 'Expense';
      case 'ADJUSTMENT':
        switch (subCat) {
          case 'ADD_CASH':     return 'Cash Added';
          case 'ADD_BANK':     return 'Added Money to Bank Account';
          case 'ADD_UPI':      return 'UPI Added';
          case 'CASH_TO_BANK': return 'Transfer : Cash to Bank';
          case 'BANK_TO_CASH': return 'Transfer : Bank to Cash';
          case 'BANK_TO_BANK': return 'Transfer : Bank to Bank';
          case 'CASH_TO_UPI':  return 'Transfer : Cash to UPI';
          case 'UPI_TO_CASH':  return 'Transfer : UPI to Cash';
          default:             return 'Adjustment';
        }
      default:
        return payType;
    }
  }

  Widget _buildCard(Map<String, dynamic> t) {
    final group = _group(t);
    final isLoan = group == 'loan';
    final pledgeNo = t['pledge_no']?.toString() ?? '';
    final pledgeId = t['pledge_id'] as int?;
    final payType = (t['payment_type'] as String?) ?? '';
    final subCat = (t['sub_category'] as String?) ?? '';
    final label = _moneyOutLabel(payType, subCat);
    final cash = (t['cash'] as num).toDouble();
    final upi = (t['upi'] as num).toDouble();
    final amount = (t['amount'] as num).toDouble();
    final bankName = t['bank_account_name'] as String?;
    final bankLabel = bankName != null ? 'Bank ($bankName)' : 'Bank';
    final customer = (t['customer_name'] as String?) ?? '';
    final notes = (t['notes'] as String?) ?? '';
    final isAdjustment = payType == 'ADJUSTMENT';
    final isExpense = payType == 'EXPENSE';
    final isSplit = cash > 0 && upi > 0;
    final tappable = isLoan && pledgeId != null && pledgeNo.isNotEmpty;

    return GestureDetector(
      onTap: tappable ? () => _openPledge(t) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FlowColors.primaryLight),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: FlowColors.redLight,
            child: Icon(
                group == 'expense'
                    ? Icons.receipt_long
                    : group == 'adjustment'
                        ? Icons.swap_horiz
                        : Icons.handshake_outlined,
                color: FlowColors.red,
                size: 20),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  isLoan && pledgeNo.isNotEmpty ? 'Pledge #$pledgeNo' : label,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: tappable ? FlowColors.primary : null),
                ),
              ),
              if (tappable)
                const Icon(Icons.chevron_right,
                    size: 18, color: Colors.black38),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isLoan && customer.isNotEmpty)
                Text(customer,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
              if (!isExpense && !isAdjustment)
                Text(label,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
              if (isExpense && notes.isNotEmpty)
                Text(notes,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
              if (isAdjustment && notes.isNotEmpty)
                Text(notes,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
              if (isSplit)
                Text('Cash: ${money(cash)}   $bankLabel: ${money(upi)}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black45))
              else if (cash > 0)
                const Text('Cash',
                    style: TextStyle(fontSize: 12, color: Colors.black45))
              else if (upi > 0)
                Text(bankLabel,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black45)),
            ],
          ),
          trailing: Text(money(amount),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.red)),
          isThreeLine: isLoan && customer.isNotEmpty,
        ),
      ),
    );
  }
}

// ─── Reconcile & Lock Screen ──────────────────────────────────────────────────

class _ReconcileScreen extends StatefulWidget {
  const _ReconcileScreen({
    required this.dateStr,
    required this.displayDate,
    required this.openingCash,
    required this.openingUpi,
    required this.cashIn,
    required this.upiIn,
    required this.cashOut,
    required this.upiOut,
    required this.expectedCash,
    required this.expectedUpi,
    required this.onLocked,
  });

  final String dateStr;
  final String displayDate;
  final double openingCash;
  final double openingUpi;
  final double cashIn;
  final double upiIn;
  final double cashOut;
  final double upiOut;
  final double expectedCash;
  final double expectedUpi;
  final VoidCallback onLocked;

  @override
  State<_ReconcileScreen> createState() => _ReconcileScreenState();
}

class _ReconcileScreenState extends State<_ReconcileScreen> {
  final _actualCashCtrl = TextEditingController();
  final _actualUpiCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();

  double get _actualCash =>
      double.tryParse(_actualCashCtrl.text.replaceAll(',', '').trim()) ?? 0;
  double get _actualUpi =>
      double.tryParse(_actualUpiCtrl.text.replaceAll(',', '').trim()) ?? 0;
  double get _cashDiff => _actualCash - widget.expectedCash;
  double get _upiDiff => _actualUpi - widget.expectedUpi;
  bool get _isMatch =>
      _cashDiff.abs() < 1 && _upiDiff.abs() < 1;

  bool _locking = false;
  String? _error;

  @override
  void dispose() {
    _actualCashCtrl.dispose();
    _actualUpiCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Verify & Close Day'),
            Text(widget.displayDate,
                style:
                    const TextStyle(fontSize: 13, color: FlowColors.textOnNavyMuted)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FlowCard(
            backgroundColor: FlowColors.accent,
            header: 'Expected Balance (Computed)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DetailRow(
                    label: 'Cash',
                    value: money(widget.expectedCash)),
                DetailRow(
                    label: 'Bank',
                    value: money(widget.expectedUpi),
                    isLast: true),
              ],
            ),
          ),
          FlowCard(
            header: 'Actual Balance (Count Now)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                TextField(
                  controller: _actualCashCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [IndianNumberFormatter()],
                  decoration: const InputDecoration(
                      labelText: 'Actual Cash in Hand (₹)',
                      prefixText: '₹ ',
                      border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _actualUpiCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [IndianNumberFormatter()],
                  decoration: const InputDecoration(
                      labelText: 'Actual UPI Balance (₹)',
                      prefixText: '₹ ',
                      border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          FlowCard(
            backgroundColor:
                _isMatch ? FlowColors.greenLight : FlowColors.redLight,
            borderColor: _isMatch ? FlowColors.green : FlowColors.red,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlowCardTitle(
                    _isMatch ? 'Balances Match ✓' : 'Mismatch Detected'),
                _diffRow('Cash Difference', _cashDiff),
                _diffRow('UPI Difference', _upiDiff, isLast: true),
              ],
            ),
          ),
          if (!_isMatch) ...[
            TextField(
              controller: _remarksCtrl,
              decoration: const InputDecoration(
                labelText: 'Remarks — required for mismatch *',
                hintText: 'Explain the difference...',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 3,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 16),
          ],
          if (_error != null) ...[
            Text(_error!,
                style:
                    const TextStyle(color: Colors.red, fontSize: 14)),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _locking ? null : _lock,
              icon: Icon(
                  _isMatch ? Icons.lock : Icons.lock_outline,
                  size: 22),
              label: Text(
                _isMatch ? 'LOCK DAY' : 'LOCK ANYWAY',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isMatch ? FlowColors.green : FlowColors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _diffRow(String label, double diff, {bool isLast = false}) {
    final color = diff.abs() < 1 ? FlowColors.green : FlowColors.red;
    final prefix = diff > 0.5 ? '+' : '';
    return DetailRow(
      label: label,
      value: '$prefix${money(diff)}',
      valueColor: color,
      isLast: isLast,
    );
  }

  Future<void> _lock() async {
    if (!_isMatch && _remarksCtrl.text.trim().isEmpty) {
      setState(
          () => _error = 'Enter remarks explaining the mismatch.');
      return;
    }
    setState(() => _locking = true);

    final remarks =
        _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim();

    // Compute + store final totals from the ledger and lock the day.
    await DailyBalanceRepository.instance.lockDay(widget.dateStr, null);
    await DayReconciliationRepository.instance.lockReconciliation(
      date: widget.dateStr,
      expectedCash: widget.expectedCash,
      expectedUpi: widget.expectedUpi,
      actualCash: _actualCash,
      actualUpi: _actualUpi,
      remarks: remarks,
    );
    await AuditLogRepository.instance.log(
      actionCategory: AuditCategory.dayManagement,
      action: 'DAY_LOCKED',
      entityType: 'daily_balance',
      entityId: widget.dateStr,
      oldValueJson: '{"is_locked":0}',
      newValueJson:
          '{"is_locked":1,"cash_diff":${_cashDiff.round()},"upi_diff":${_upiDiff.round()}}',
      reason: remarks ?? 'Day locked — balances matched',
    );

    if (!mounted) return;
    widget.onLocked();
  }
}
