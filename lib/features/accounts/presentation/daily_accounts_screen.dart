import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../../shared/widgets/flow_widgets.dart';

class DailyAccountsScreen extends StatefulWidget {
  const DailyAccountsScreen({super.key});

  @override
  State<DailyAccountsScreen> createState() => _DailyAccountsScreenState();
}

class _DailyAccountsScreenState extends State<DailyAccountsScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;

  double _openingCash = 0;
  double _openingUpi = 0;

  List<Map<String, dynamic>> _loans = [];
  List<Map<String, dynamic>> _collections = [];
  List<Map<String, dynamic>> _expenses = [];

  // ─── Computed totals ──────────────────────────────────────────────────────

  double get _cashIn =>
      _collections.fold(0.0, (s, p) => s + (p['cash_amount'] as num).toDouble());
  double get _upiIn =>
      _collections.fold(0.0, (s, p) => s + (p['upi_amount'] as num).toDouble());
  double get _loansOutCash => _loans
      .where((l) => l['mode'] == 'cash')
      .fold(0.0, (s, l) => s + (l['amount'] as num).toDouble());
  double get _loansOutUpi => _loans
      .where((l) => l['mode'] == 'upi')
      .fold(0.0, (s, l) => s + (l['amount'] as num).toDouble());
  double get _expCash => _expenses
      .where((e) => e['mode'] == 'cash')
      .fold(0.0, (s, e) => s + (e['amount'] as num).toDouble());
  double get _expUpi => _expenses
      .where((e) => e['mode'] == 'upi')
      .fold(0.0, (s, e) => s + (e['amount'] as num).toDouble());

  double get _closingCash =>
      _openingCash + _cashIn - _loansOutCash - _expCash;
  double get _closingUpi =>
      _openingUpi + _upiIn - _loansOutUpi - _expUpi;

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ─── Data loading ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    final dateStr = _dateStr(_selectedDate);
    final db = await AppDatabase.instance.database;
    final settings = AppSettingsRepository();

    final initCashStr = await settings.getString('opening_cash');
    final initUpiStr = await settings.getString('opening_upi');
    final initCash = double.tryParse(initCashStr ?? '0') ?? 0;
    final initUpi = double.tryParse(initUpiStr ?? '0') ?? 0;

    // ── Opening balance = initial settings + all history before this date ──
    final cashInPrior = await db.rawQuery(
      "SELECT COALESCE(SUM(cash_amount),0) AS s FROM payments WHERE paid_at < ?",
      [dateStr],
    );
    final upiInPrior = await db.rawQuery(
      "SELECT COALESCE(SUM(upi_amount),0) AS s FROM payments WHERE paid_at < ?",
      [dateStr],
    );
    final loanCashPrior = await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
      "WHERE type='loan_disbursed' AND mode='cash' AND transaction_date < ?",
      [dateStr],
    );
    final loanUpiPrior = await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
      "WHERE type='loan_disbursed' AND mode='upi' AND transaction_date < ?",
      [dateStr],
    );
    final expCashPrior = await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
      "WHERE type='expense' AND mode='cash' AND transaction_date < ?",
      [dateStr],
    );
    final expUpiPrior = await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS s FROM transactions "
      "WHERE type='expense' AND mode='upi' AND transaction_date < ?",
      [dateStr],
    );

    final openingCash = initCash
        + (cashInPrior.first['s'] as num).toDouble()
        - (loanCashPrior.first['s'] as num).toDouble()
        - (expCashPrior.first['s'] as num).toDouble();

    final openingUpi = initUpi
        + (upiInPrior.first['s'] as num).toDouble()
        - (loanUpiPrior.first['s'] as num).toDouble()
        - (expUpiPrior.first['s'] as num).toDouble();

    // ── Today's loans given ───────────────────────────────────────────────
    final loans = await db.rawQuery(
      """SELECT t.amount, t.mode, t.description,
                COALESCE(p.pledge_no, '') AS pledge_no
         FROM transactions t
         LEFT JOIN pledges p ON p.id = t.pledge_id
         WHERE t.type = 'loan_disbursed' AND t.transaction_date = ?
         ORDER BY t.created_at""",
      [dateStr],
    );

    // ── Today's collections received ──────────────────────────────────────
    final collections = await db.rawQuery(
      """SELECT pay.cash_amount, pay.upi_amount, pay.amount,
                pay.payment_type,
                COALESCE(p.pledge_no, '') AS pledge_no
         FROM payments pay
         LEFT JOIN pledges p ON p.id = pay.pledge_id
         WHERE pay.paid_at LIKE ?
         ORDER BY pay.paid_at""",
      ['$dateStr%'],
    );

    // ── Today's expenses ──────────────────────────────────────────────────
    final expenses = await db.rawQuery(
      """SELECT amount, mode, description, id
         FROM transactions
         WHERE type = 'expense' AND transaction_date = ?
         ORDER BY created_at""",
      [dateStr],
    );

    if (mounted) {
      setState(() {
        _openingCash = openingCash;
        _openingUpi = openingUpi;
        _loans = loans.map((r) => Map<String, dynamic>.from(r)).toList();
        _collections =
            collections.map((r) => Map<String, dynamic>.from(r)).toList();
        _expenses =
            expenses.map((r) => Map<String, dynamic>.from(r)).toList();
        _loading = false;
      });
    }
  }

  void _changeDate(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    _loadData();
  }

  // ─── Add Expense Dialog ───────────────────────────────────────────────────

  void _showAddExpenseDialog() {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String mode = 'cash';
    String? error;
    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) => AlertDialog(
          title: const Text('Record Expense',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.primary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}'))
                  ],
                  style: const TextStyle(fontSize: 20),
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹) *',
                    prefixText: '₹ ',
                  ),
                  onChanged: (_) {
                    if (error != null) setDS(() => error = null);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descCtrl,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'e.g. Petty cash, electricity',
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Paid via',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _modeBtn('Cash', 'cash', mode == 'cash',
                          () => setDS(() => mode = 'cash')),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _modeBtn('UPI', 'upi', mode == 'upi',
                          () => setDS(() => mode = 'upi')),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(color: Colors.red, fontSize: 14)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(fontSize: 17, color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.primary),
              onPressed: saving
                  ? null
                  : () async {
                      final amount =
                          double.tryParse(amountCtrl.text.trim());
                      if (amount == null || amount <= 0) {
                        setDS(() => error = 'Enter a valid amount.');
                        return;
                      }
                      setDS(() => saving = true);
                      final db = await AppDatabase.instance.database;
                      final now = DateTime.now().toIso8601String();
                      await db.insert('transactions', {
                        'transaction_date': _dateStr(_selectedDate),
                        'type': 'expense',
                        'direction': 'out',
                        'amount': amount,
                        'mode': mode,
                        'pledge_id': null,
                        'payment_id': null,
                        'expense_category_id': null,
                        'description': descCtrl.text.trim().isEmpty
                            ? 'Expense'
                            : descCtrl.text.trim(),
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
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('SAVE',
                      style:
                          TextStyle(fontSize: 17, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Daily Accounts'),
      ),
      body: Column(
        children: [
          _dateNavigator(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        _openingSection(),
                        const SizedBox(height: 6),
                        _loansSection(),
                        const SizedBox(height: 6),
                        _collectionsSection(),
                        const SizedBox(height: 6),
                        _expensesSection(),
                        const SizedBox(height: 6),
                        _closingSection(),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: ElevatedButton.icon(
                            onPressed: _showAddExpenseDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('ADD EXPENSE',
                                style: TextStyle(fontSize: 18)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: FlowColors.orange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
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

  Widget _dateNavigator() {
    final label = _isToday
        ? 'Today — ${_fmtDate(_selectedDate)}'
        : _fmtDate(_selectedDate);

    return Container(
      color: FlowColors.accent,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 32,
                color: FlowColors.primary),
            onPressed: () => _changeDate(-1),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.primary),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, size: 32,
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

  // ─── Sections ─────────────────────────────────────────────────────────────

  Widget _openingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Opening Balance', Icons.account_balance_wallet_outlined),
        FlowCard(
          backgroundColor: FlowColors.accent,
          child: Column(
            children: [
              _balanceRow('Cash', _openingCash),
              const SizedBox(height: 8),
              _balanceRow('UPI', _openingUpi, isLast: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _loansSection() {
    final totalCash = _loansOutCash;
    final totalUpi = _loansOutUpi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Loans Given (OUT)', Icons.arrow_upward,
            color: FlowColors.red),
        if (_loans.isEmpty)
          const FlowCard(
            child: Text('No loans disbursed.',
                style: TextStyle(color: Colors.black54, fontSize: 16)),
          )
        else ...[
          ..._loans.map((l) => _txRow(
                icon: Icons.arrow_upward,
                iconColor: FlowColors.red,
                title:
                    'Pledge ${l['pledge_no']}  ·  ${l['mode'].toString().toUpperCase()}',
                amount: (l['amount'] as num).toDouble(),
                amountColor: FlowColors.red,
              )),
          FlowCard(
            backgroundColor: FlowColors.redLight,
            borderColor: FlowColors.red,
            child: Column(
              children: [
                if (totalCash > 0)
                  _summLine('Cash Out', totalCash, FlowColors.red),
                if (totalUpi > 0) ...[
                  if (totalCash > 0) const SizedBox(height: 6),
                  _summLine('UPI Out', totalUpi, FlowColors.red),
                ],
                if (totalCash > 0 && totalUpi > 0) ...[
                  const Divider(height: 14),
                  _summLine('Total Out',
                      totalCash + totalUpi, FlowColors.red,
                      bold: true),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _collectionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Collections (IN)', Icons.arrow_downward,
            color: FlowColors.green),
        if (_collections.isEmpty)
          const FlowCard(
            child: Text('No collections received.',
                style: TextStyle(color: Colors.black54, fontSize: 16)),
          )
        else ...[
          ..._collections.map((c) {
            final pledgeNo = c['pledge_no'].toString();
            final cash = (c['cash_amount'] as num).toDouble();
            final upi = (c['upi_amount'] as num).toDouble();
            final type = (c['payment_type'] as String?) ?? '';
            final typeLabel = type == 'closure'
                ? 'Closed'
                : type == 'interest'
                    ? 'Interest'
                    : type == 'renewal'
                        ? 'Renewed'
                        : type;
            return _txRow(
              icon: Icons.arrow_downward,
              iconColor: FlowColors.green,
              title: 'Pledge $pledgeNo  ·  $typeLabel',
              subtitle:
                  '${cash > 0 ? 'Cash: ${money(cash)}' : ''}${cash > 0 && upi > 0 ? '   ' : ''}${upi > 0 ? 'UPI: ${money(upi)}' : ''}',
              amount: (c['amount'] as num).toDouble(),
              amountColor: FlowColors.green,
            );
          }),
          FlowCard(
            backgroundColor: FlowColors.greenLight,
            borderColor: FlowColors.green,
            child: Column(
              children: [
                if (_cashIn > 0)
                  _summLine('Cash In', _cashIn, FlowColors.green),
                if (_upiIn > 0) ...[
                  if (_cashIn > 0) const SizedBox(height: 6),
                  _summLine('UPI In', _upiIn, FlowColors.green),
                ],
                if (_cashIn > 0 && _upiIn > 0) ...[
                  const Divider(height: 14),
                  _summLine('Total In', _cashIn + _upiIn, FlowColors.green,
                      bold: true),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _expensesSection() {
    final totalExp = _expCash + _expUpi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Expenses', Icons.receipt_long_outlined,
            color: FlowColors.orange),
        if (_expenses.isEmpty)
          const FlowCard(
            child: Text('No expenses recorded.',
                style: TextStyle(color: Colors.black54, fontSize: 16)),
          )
        else ...[
          ..._expenses.map((e) => _txRow(
                icon: Icons.receipt_long_outlined,
                iconColor: FlowColors.orange,
                title: (e['description'] as String?) ?? 'Expense',
                subtitle: e['mode'].toString().toUpperCase(),
                amount: (e['amount'] as num).toDouble(),
                amountColor: FlowColors.orange,
              )),
          if (totalExp > 0)
            FlowCard(
              backgroundColor: FlowColors.orangeLight,
              borderColor: FlowColors.orange,
              child: _summLine('Total Expenses', totalExp, FlowColors.orange,
                  bold: true),
            ),
        ],
      ],
    );
  }

  Widget _closingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Closing Balance', Icons.savings_outlined,
            color: FlowColors.primary),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: FlowColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              _closingRow('Cash', _closingCash),
              const Divider(height: 18, color: Colors.white24),
              _closingRow('UPI', _closingUpi),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Formula hint
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Cash: ${money(_openingCash)} + ${money(_cashIn)} − ${money(_loansOutCash)} − ${money(_expCash)}'
            '\nUPI:  ${money(_openingUpi)} + ${money(_upiIn)} − ${money(_loansOutUpi)} − ${money(_expUpi)}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ],
    );
  }

  // ─── Reusable Widgets ─────────────────────────────────────────────────────

  Widget _sectionHeader(String title, IconData icon,
      {Color color = FlowColors.primary}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _txRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required double amount,
    required Color amountColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black54)),
              ],
            ),
          ),
          Text(money(amount),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: amountColor)),
        ],
      ),
    );
  }

  Widget _balanceRow(String label, double amount, {bool isLast = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 17, color: Colors.black54)),
        Text(money(amount),
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
      ],
    );
  }

  Widget _summLine(String label, double amount, Color color,
      {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 16,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: color)),
        Text(money(amount),
            style: TextStyle(
                fontSize: 17,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: color)),
      ],
    );
  }

  Widget _closingRow(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 18, color: Colors.white70)),
        Text(money(amount),
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: amount < 0 ? Colors.red[200] : Colors.white)),
      ],
    );
  }

  Widget _modeBtn(
      String label, String value, bool selected, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? FlowColors.accent : Colors.white,
        side: BorderSide(
            color: selected ? FlowColors.primary : Colors.black26, width: 2),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 16,
              fontWeight:
                  selected ? FontWeight.bold : FontWeight.normal,
              color: FlowColors.primary)),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _fmtDate(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month]} ${d.year}';
  }
}
