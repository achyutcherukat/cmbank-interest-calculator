import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../pledges/presentation/closed_pledges_screen.dart';
import '../../pledges/presentation/open_pledge_screen.dart';

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

  double _openingCash = 0;
  double _openingUpi = 0;

  List<Map<String, dynamic>> _inTxns = [];
  List<Map<String, dynamic>> _outTxns = [];
  List<Map<String, dynamic>> _adjustments = [];

  // Computed totals
  double get _cashIn =>
      _inTxns.fold(0.0, (s, t) => s + (t['cash'] as num).toDouble());
  double get _upiIn =>
      _inTxns.fold(0.0, (s, t) => s + (t['upi'] as num).toDouble());
  double get _cashOut => _outTxns
      .where((t) => t['mode'] == 'cash')
      .fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());
  double get _upiOut => _outTxns
      .where((t) => t['mode'] == 'upi')
      .fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());
  double get _adjCash => _adjustments.fold(
      0.0,
      (s, a) =>
          s + ((a['mode'] == 'cash') ? (a['net'] as num).toDouble() : 0.0));
  double get _adjUpi => _adjustments.fold(
      0.0,
      (s, a) =>
          s + ((a['mode'] == 'upi') ? (a['net'] as num).toDouble() : 0.0));

  double get _closingCash => _openingCash + _cashIn - _cashOut + _adjCash;
  double get _closingUpi => _openingUpi + _upiIn - _upiOut + _adjUpi;

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
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
    final db = await AppDatabase.instance.database;
    final dateStr = _iso(_selectedDate);

    // Opening balance: previous day closing from daily_balance, else compute.
    final prevStr = _iso(_selectedDate.subtract(const Duration(days: 1)));
    final prevBal = await db.query(
      'daily_balance',
      where: 'business_date = ?',
      whereArgs: [prevStr],
      limit: 1,
    );

    double openingCash, openingUpi;
    if (prevBal.isNotEmpty) {
      openingCash = (prevBal.first['closing_cash'] as num).toDouble();
      openingUpi = (prevBal.first['closing_upi'] as num).toDouble();
    } else {
      final settings = AppSettingsRepository();
      final initCash =
          double.tryParse(await settings.getString('opening_cash') ?? '0') ?? 0;
      final initUpi =
          double.tryParse(await settings.getString('opening_upi') ?? '0') ?? 0;

      double q(List<Map<String, dynamic>> rows) =>
          (rows.first['s'] as num).toDouble();

      final cashInP = await db.rawQuery(
          "SELECT COALESCE(SUM(cash_amount),0) AS s FROM payments WHERE paid_at < ?",
          [dateStr]);
      final upiInP = await db.rawQuery(
          "SELECT COALESCE(SUM(upi_amount),0) AS s FROM payments WHERE paid_at < ?",
          [dateStr]);
      final cashOutP = await db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
          "WHERE type='loan_disbursed' AND mode='cash' AND transaction_date < ?",
          [dateStr]);
      final upiOutP = await db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
          "WHERE type='loan_disbursed' AND mode='upi' AND transaction_date < ?",
          [dateStr]);
      final expCashP = await db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
          "WHERE type='expense' AND mode='cash' AND transaction_date < ?",
          [dateStr]);
      final expUpiP = await db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
          "WHERE type='expense' AND mode='upi' AND transaction_date < ?",
          [dateStr]);
      final adjCashP = await db.rawQuery(
          "SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE -amount END),0) AS s "
          "FROM transactions WHERE type='adjustment' AND mode='cash' AND transaction_date < ?",
          [dateStr]);
      final adjUpiP = await db.rawQuery(
          "SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE -amount END),0) AS s "
          "FROM transactions WHERE type='adjustment' AND mode='upi' AND transaction_date < ?",
          [dateStr]);

      openingCash = initCash +
          q(cashInP) -
          q(cashOutP) -
          q(expCashP) +
          q(adjCashP);
      openingUpi =
          initUpi + q(upiInP) - q(upiOutP) - q(expUpiP) + q(adjUpiP);
    }

    // Money IN: payment_received transactions today
    final inRows = await db.rawQuery(
      """SELECT t.id, t.amount, t.mode, t.description,
                pay.cash_amount, pay.upi_amount, pay.payment_type,
                COALESCE(p.pledge_no, '') AS pledge_no, p.id AS pledge_id,
                COALESCE(p.status, '') AS pledge_status,
                COALESCE(p.customer_name, '') AS customer_name
         FROM transactions t
         LEFT JOIN payments pay ON pay.id = t.payment_id
         LEFT JOIN pledges p ON p.id = t.pledge_id
         WHERE t.type = 'payment_received' AND t.transaction_date = ?
         ORDER BY t.created_at""",
      [dateStr],
    );

    // Money OUT: loan_disbursed + expense transactions today
    final outRows = await db.rawQuery(
      """SELECT t.id, t.amount, t.mode, t.description, t.type,
                ec.name AS category_name,
                COALESCE(p.pledge_no, '') AS pledge_no, p.id AS pledge_id,
                COALESCE(p.status, '') AS pledge_status,
                COALESCE(p.customer_name, '') AS customer_name
         FROM transactions t
         LEFT JOIN expense_categories ec ON ec.id = t.expense_category_id
         LEFT JOIN pledges p ON p.id = t.pledge_id
         WHERE t.type IN ('loan_disbursed', 'expense') AND t.transaction_date = ?
         ORDER BY t.type, t.created_at""",
      [dateStr],
    );

    // Adjustments today
    final adjRows = await db.rawQuery(
      """SELECT id, amount, mode, direction, description
         FROM transactions
         WHERE type = 'adjustment' AND transaction_date = ?
         ORDER BY created_at""",
      [dateStr],
    );

    // Lock status
    final balRows = await db.query(
      'daily_balance',
      where: 'business_date = ?',
      whereArgs: [dateStr],
      limit: 1,
    );
    final isLocked =
        balRows.isNotEmpty && (balRows.first['is_locked'] as int? ?? 0) == 1;

    // Build IN list with resolved cash/upi split
    final inMapped = inRows.map((r) {
      final cashAmt = (r['cash_amount'] as num?)?.toDouble() ?? 0;
      final upiAmt = (r['upi_amount'] as num?)?.toDouble() ?? 0;
      final total = (r['amount'] as num).toDouble();
      return {
        ...Map<String, dynamic>.from(r),
        'cash': (cashAmt > 0 || upiAmt > 0)
            ? cashAmt
            : (r['mode'] == 'cash' ? total : 0.0),
        'upi': (cashAmt > 0 || upiAmt > 0)
            ? upiAmt
            : (r['mode'] == 'upi' ? total : 0.0),
      };
    }).toList();

    // Adjustments with signed net
    final adjMapped = adjRows.map((r) {
      final amt = (r['amount'] as num).toDouble();
      final isIn = (r['direction'] as String) == 'in';
      return {
        ...Map<String, dynamic>.from(r),
        'net': isIn ? amt : -amt,
      };
    }).toList();

    if (mounted) {
      setState(() {
        _openingCash = openingCash;
        _openingUpi = openingUpi;
        _inTxns = inMapped;
        _outTxns = outRows.map((r) => Map<String, dynamic>.from(r)).toList();
        _adjustments = adjMapped;
        _isLocked = isLocked;
        _loading = false;
      });
    }
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
        title: const Text('Daily Accounts'),
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
                          _buildActionBtn(
                            label: 'ADJUST BALANCE',
                            icon: Icons.tune,
                            color: FlowColors.primaryLight,
                            onTap: _showAdjustBalance,
                          ),
                          const SizedBox(height: 10),
                          _buildActionBtn(
                            label: 'ADD EXPENSE',
                            icon: Icons.receipt_long,
                            color: FlowColors.orange,
                            onTap: _showAddExpense,
                          ),
                          const SizedBox(height: 10),
                          _buildActionBtn(
                            label: 'RECONCILE & LOCK DAY',
                            icon: Icons.lock_outline,
                            color: FlowColors.primary,
                            foregroundColor: FlowColors.textOnNavyLarge,
                            borderSide: const BorderSide(
                                color: FlowColors.borderOnNavy, width: 0.8),
                            onTap: _showReconcile,
                          ),
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
    final label =
        _isToday ? 'Today  ${_fmt(_selectedDate)}' : _fmt(_selectedDate);
    return Container(
      color: FlowColors.accent,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left,
                size: 32, color: FlowColors.primary),
            onPressed: () => _changeDate(-1),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.primary)),
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
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
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
                      'UPI', _openingUpi, Icons.qr_code_scanner)),
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
            _modeRow('UPI', upi, color),
          ],
        ),
      ),
    );
  }

  Widget _buildClosingCard() {
    return Container(
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
                      'UPI', _closingUpi, Icons.qr_code_scanner)),
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

  Widget _modeChip(
      String label, IconData icon, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? FlowColors.accent : Colors.white,
          border: Border.all(
              color: selected ? FlowColors.primary : Colors.black26,
              width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: FlowColors.primary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                    color: FlowColors.primary)),
          ],
        ),
      ),
    );
  }

  // ─── Add Expense ──────────────────────────────────────────────────────────

  void _showAddExpense() {
    const cats = [
      'Rent',
      'Electricity',
      'Staff Salary',
      'Office Supplies',
      'Other'
    ];
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final otherCtrl = TextEditingController();
    String? selectedCat;
    String mode = 'cash';
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
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹) *',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (error != null) setBS(() => error = null);
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
                  if (selectedCat == 'Other') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: otherCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Specify category',
                          border: OutlineInputBorder()),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Payment Method',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: _modeChip(
                              'CASH',
                              Icons.payments,
                              mode == 'cash',
                              () => setBS(() => mode = 'cash'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _modeChip(
                              'UPI',
                              Icons.qr_code_scanner,
                              mode == 'upi',
                              () => setBS(() => mode = 'upi'))),
                    ],
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
                                      amountCtrl.text.trim());
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
                                  setBS(() => saving = true);
                                  final catLabel =
                                      selectedCat == 'Other'
                                          ? (otherCtrl.text.trim().isEmpty
                                              ? 'Other'
                                              : otherCtrl.text.trim())
                                          : selectedCat!;
                                  final db =
                                      await AppDatabase.instance.database;
                                  final now =
                                      DateTime.now().toIso8601String();
                                  await db.insert('transactions', {
                                    'transaction_date':
                                        _iso(_selectedDate),
                                    'type': 'expense',
                                    'direction': 'out',
                                    'amount': amt,
                                    'mode': mode,
                                    'pledge_id': null,
                                    'payment_id': null,
                                    'expense_category_id': null,
                                    'description': catLabel +
                                        (notesCtrl.text.trim().isNotEmpty
                                            ? ': ${notesCtrl.text.trim()}'
                                            : ''),
                                    'created_by': null,
                                    'created_at': now,
                                  });
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

  // ─── Adjust Balance ───────────────────────────────────────────────────────

  void _showAdjustBalance() {
    String adjustType = 'add_cash';
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String? error;
    bool saving = false;

    const options = <(String, String, IconData)>[
      ('add_cash', 'Add Cash', Icons.payments),
      ('add_upi', 'Add UPI', Icons.qr_code_scanner),
      ('transfer', 'Transfer Cash → UPI', Icons.swap_horiz),
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Adjust Balance',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.primary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Adjustment Type',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ...options.map((t) {
                  final selected = adjustType == t.$1;
                  return GestureDetector(
                    onTap: () => setD(() => adjustType = t.$1),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? FlowColors.accent : Colors.white,
                        border: Border.all(
                            color: selected
                                ? FlowColors.primary
                                : Colors.black26,
                            width: selected ? 2 : 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        Icon(t.$3,
                            size: 18,
                            color: selected
                                ? FlowColors.primary
                                : Colors.black54),
                        const SizedBox(width: 10),
                        Text(t.$2,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: selected
                                    ? FlowColors.primary
                                    : Colors.black87)),
                        const Spacer(),
                        if (selected)
                          const Icon(Icons.check_circle,
                              color: FlowColors.primary, size: 18),
                      ]),
                    ),
                  );
                }),
                const SizedBox(height: 14),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration: const InputDecoration(
                      labelText: 'Amount (₹) *',
                      prefixText: '₹ ',
                      border: OutlineInputBorder()),
                  onChanged: (_) {
                    if (error != null) setD(() => error = null);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Reason (mandatory) *',
                      hintText: 'Why is this adjustment needed?',
                      border: OutlineInputBorder()),
                  maxLines: 2,
                  onChanged: (_) {
                    if (error != null) setD(() => error = null);
                  },
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
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.primaryLight,
                  foregroundColor: Colors.white),
              onPressed: saving
                  ? null
                  : () async {
                      final amt =
                          int.tryParse(amountCtrl.text.trim());
                      if (amt == null || amt <= 0) {
                        setD(() => error = 'Enter a valid amount.');
                        return;
                      }
                      if (reasonCtrl.text.trim().isEmpty) {
                        setD(() => error = 'Reason is required.');
                        return;
                      }
                      setD(() => saving = true);

                      final db = await AppDatabase.instance.database;
                      final now = DateTime.now().toIso8601String();
                      final dateStr = _iso(_selectedDate);
                      final reason = reasonCtrl.text.trim();

                      Future<void> ins(
                              String dir, String m, String desc) =>
                          db.insert('transactions', {
                            'transaction_date': dateStr,
                            'type': 'adjustment',
                            'direction': dir,
                            'amount': amt,
                            'mode': m,
                            'pledge_id': null,
                            'payment_id': null,
                            'expense_category_id': null,
                            'description': desc,
                            'created_by': null,
                            'created_at': now,
                          });

                      if (adjustType == 'add_cash') {
                        await ins(
                            'in', 'cash', 'Cash adjustment: $reason');
                      } else if (adjustType == 'add_upi') {
                        await ins(
                            'in', 'upi', 'UPI adjustment: $reason');
                      } else {
                        await ins('out', 'cash',
                            'Transfer cash→UPI: $reason');
                        await ins(
                            'in', 'upi', 'Transfer cash→UPI: $reason');
                      }

                      await db.insert('audit_log', {
                        'entity_type': 'daily_accounts',
                        'entity_id': dateStr,
                        'action': 'balance_adjustment',
                        'old_value_json': null,
                        'new_value_json':
                            '{"type":"$adjustType","amount":$amt}',
                        'reason': reason,
                        'created_by': null,
                        'created_at': now,
                      });

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _loadData();
                    },
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('APPLY',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Reconcile & Lock ─────────────────────────────────────────────────────

  void _showReconcile() {
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FlowNoticeBox(
                text:
                    'Unlocking allows edits. This action will be logged.',
                color: FlowColors.orange,
                backgroundColor: FlowColors.orangeLight,
                icon: Icons.warning_amber,
              ),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly
                ],
                obscureText: true,
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
                      final settings = AppSettingsRepository();
                      final storedPin =
                          await settings.getString('admin_pin') ??
                              '1234';
                      if (pinCtrl.text.trim() != storedPin) {
                        setD(() => error = 'Incorrect PIN.');
                        return;
                      }
                      setD(() => unlocking = true);

                      final db = await AppDatabase.instance.database;
                      final now = DateTime.now().toIso8601String();
                      final dateStr = _iso(_selectedDate);

                      await db.update(
                        'day_reconciliation',
                        {
                          'unlocked_at': now,
                          'unlocked_by': null,
                          'unlock_reason': reasonCtrl.text.trim(),
                        },
                        where: 'business_date = ?',
                        whereArgs: [dateStr],
                      );
                      await db.update(
                        'daily_balance',
                        {'is_locked': 0, 'updated_at': now},
                        where: 'business_date = ?',
                        whereArgs: [dateStr],
                      );
                      await db.insert('audit_log', {
                        'entity_type': 'daily_accounts',
                        'entity_id': dateStr,
                        'action': 'day_unlocked',
                        'old_value_json': '{"is_locked":1}',
                        'new_value_json': '{"is_locked":0}',
                        'reason': reasonCtrl.text.trim(),
                        'created_by': null,
                        'created_at': now,
                      });

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
    } else if (_filter == 'upi') {
      return widget.txns
          .where((t) => (t['upi'] as num).toDouble() > 0)
          .toList();
    }
    return widget.txns;
  }

  double get _totalCash =>
      _filtered.fold(0.0, (s, t) => s + (t['cash'] as num).toDouble());
  double get _totalUpi =>
      _filtered.fold(0.0, (s, t) => s + (t['upi'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.green,
        foregroundColor: Colors.white,
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
          _buildHeader(),
          _buildFilterTabs(),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No entries for this filter.',
                        style: TextStyle(
                            color: Colors.black54, fontSize: 16)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _buildCard(filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: FlowColors.greenLight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
              child: _stat('CASH IN', _totalCash, Icons.payments)),
          Container(
              width: 1,
              height: 36,
              color: FlowColors.green.withAlpha(80),
              margin: const EdgeInsets.symmetric(horizontal: 8)),
          Expanded(
              child: _stat('UPI IN', _totalUpi, Icons.qr_code_scanner)),
          Container(
              width: 1,
              height: 36,
              color: FlowColors.green.withAlpha(80),
              margin: const EdgeInsets.symmetric(horizontal: 8)),
          Expanded(
              child: _stat(
                  'TOTAL', _totalCash + _totalUpi, Icons.arrow_downward)),
        ],
      ),
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
          _filterChip('upi', 'UPI', money(upiTotal)),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label, String total) {
    final selected = _filter == value;
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
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : FlowColors.green)),
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

  Widget _stat(String label, double amt, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 13, color: FlowColors.green),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: FlowColors.green,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(money(amt),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: FlowColors.green)),
      ],
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

  Widget _buildCard(Map<String, dynamic> t) {
    final pledgeNo = t['pledge_no']?.toString() ?? '';
    final pledgeId = t['pledge_id'] as int?;
    final payType = (t['payment_type'] as String?) ?? '';
    final typeLabel = switch (payType) {
      'closure' => 'Closure',
      'renewal' => 'Renewal',
      'interest' => 'Interest',
      _ => payType,
    };
    final cash = (t['cash'] as num).toDouble();
    final upi = (t['upi'] as num).toDouble();
    final total = (t['amount'] as num).toDouble();
    final customer = (t['customer_name'] as String?) ?? '';
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
                  pledgeNo.isNotEmpty ? 'Pledge #$pledgeNo' : 'Payment',
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
              if (typeLabel.isNotEmpty)
                Text(typeLabel,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
              if (cash > 0 || upi > 0)
                Text('Cash: ${money(cash)}   UPI: ${money(upi)}',
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
      return widget.txns.where((t) => t['mode'] == 'cash').toList();
    } else if (_filter == 'upi') {
      return widget.txns.where((t) => t['mode'] == 'upi').toList();
    }
    return widget.txns;
  }

  List<Map<String, dynamic>> get _loans =>
      _filtered.where((t) => t['type'] == 'loan_disbursed').toList();
  List<Map<String, dynamic>> get _expenses =>
      _filtered.where((t) => t['type'] == 'expense').toList();

  double get _totalCash => _filtered
      .where((t) => t['mode'] == 'cash')
      .fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());
  double get _totalUpi => _filtered
      .where((t) => t['mode'] == 'upi')
      .fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.red,
        foregroundColor: Colors.white,
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
          _buildHeader(),
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
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: FlowColors.redLight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
              child: _stat('CASH OUT', _totalCash, Icons.payments)),
          Container(
              width: 1,
              height: 36,
              color: FlowColors.red.withAlpha(80),
              margin: const EdgeInsets.symmetric(horizontal: 8)),
          Expanded(
              child: _stat('UPI OUT', _totalUpi, Icons.qr_code_scanner)),
          Container(
              width: 1,
              height: 36,
              color: FlowColors.red.withAlpha(80),
              margin: const EdgeInsets.symmetric(horizontal: 8)),
          Expanded(
              child: _stat(
                  'TOTAL', _totalCash + _totalUpi, Icons.arrow_upward)),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final allTotal = widget.txns.fold(
        0.0, (s, t) => s + (t['amount'] as num).toDouble());
    final cashTotal = widget.txns
        .where((t) => t['mode'] == 'cash')
        .fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());
    final upiTotal = widget.txns
        .where((t) => t['mode'] == 'upi')
        .fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _filterChip('all', 'ALL', money(allTotal)),
          const SizedBox(width: 8),
          _filterChip('cash', 'CASH', money(cashTotal)),
          const SizedBox(width: 8),
          _filterChip('upi', 'UPI', money(upiTotal)),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label, String total) {
    final selected = _filter == value;
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
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : FlowColors.red)),
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

  Widget _stat(String label, double amt, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 13, color: FlowColors.red),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                color: FlowColors.red,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(money(amt),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: FlowColors.red)),
      ],
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
            ? PledgeDetailScreen(pledgeId: pledgeId)
            : ClosedPledgeDetailScreen(pledgeId: pledgeId),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> t) {
    final isLoan = t['type'] == 'loan_disbursed';
    final pledgeNo = t['pledge_no']?.toString() ?? '';
    final pledgeId = t['pledge_id'] as int?;
    final desc = (t['description'] as String?) ?? '';
    final catName = (t['category_name'] as String?) ?? '';
    final mode = (t['mode'] as String).toUpperCase();
    final amount = (t['amount'] as num).toDouble();
    final customer = (t['customer_name'] as String?) ?? '';
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
                isLoan
                    ? Icons.handshake_outlined
                    : Icons.receipt_long,
                color: FlowColors.red,
                size: 20),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  isLoan
                      ? (pledgeNo.isNotEmpty ? 'Pledge #$pledgeNo' : 'Loan')
                      : (catName.isNotEmpty ? catName : desc),
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
              Text(
                isLoan ? 'Loan  ·  $mode' : 'Expense  ·  $mode',
                style: const TextStyle(
                    fontSize: 13, color: Colors.black54),
              ),
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
      double.tryParse(_actualCashCtrl.text.trim()) ?? 0;
  double get _actualUpi =>
      double.tryParse(_actualUpiCtrl.text.trim()) ?? 0;
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
            const Text('Reconcile & Lock Day'),
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
                    label: 'UPI',
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
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
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
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
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

    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'daily_balance',
      {
        'business_date': widget.dateStr,
        'opening_cash': widget.openingCash,
        'opening_upi': widget.openingUpi,
        'cash_in': widget.cashIn,
        'cash_out': widget.cashOut,
        'upi_in': widget.upiIn,
        'upi_out': widget.upiOut,
        'closing_cash': widget.expectedCash,
        'closing_upi': widget.expectedUpi,
        'is_locked': 1,
        'locked_at': now,
        'locked_by': null,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.insert(
      'day_reconciliation',
      {
        'business_date': widget.dateStr,
        'expected_cash': widget.expectedCash,
        'actual_cash': _actualCash,
        'cash_difference': _cashDiff,
        'expected_upi': widget.expectedUpi,
        'actual_upi': _actualUpi,
        'upi_difference': _upiDiff,
        'remarks': _remarksCtrl.text.trim().isEmpty
            ? null
            : _remarksCtrl.text.trim(),
        'locked_by': null,
        'locked_at': now,
        'unlocked_by': null,
        'unlocked_at': null,
        'unlock_reason': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.insert('audit_log', {
      'entity_type': 'daily_accounts',
      'entity_id': widget.dateStr,
      'action': 'day_locked',
      'old_value_json': '{"is_locked":0}',
      'new_value_json':
          '{"is_locked":1,"cash_diff":${_cashDiff.round()},"upi_diff":${_upiDiff.round()}}',
      'reason': _remarksCtrl.text.trim().isEmpty
          ? 'Day locked — balances matched'
          : _remarksCtrl.text.trim(),
      'created_by': null,
      'created_at': now,
    });

    if (!mounted) return;
    widget.onLocked();
  }
}
