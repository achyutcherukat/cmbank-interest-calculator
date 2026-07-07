import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import 'payment_model.dart';

/// Accounts-ledger repository (`payments` table).
///
/// Every create* method writes a single row. Read totals are computed from
/// `cash_amount` / `bank_amount` split by `direction`. All create* methods
/// accept an optional [txn] so pledge flows can record payments inside their
/// own transaction.
class PaymentsRepository {
  PaymentsRepository._();
  static final PaymentsRepository instance = PaymentsRepository._();

  Future<int> _insert(
    DatabaseExecutor db, {
    required String date,
    required String paymentType,
    required String direction,
    String? subCategory,
    int? ledgerAccountId,
    required double amount,
    required double cashAmount,
    required double bankAmount,
    int? bankAccountId,
    int? pledgeId,
    String? notes,
    int? createdBy,
  }) {
    return db.insert('payments', {
      'payment_date': date,
      'payment_type': paymentType,
      'sub_category': subCategory,
      'ledger_account_id': ledgerAccountId,
      'direction': direction,
      'amount': amount,
      'cash_amount': cashAmount,
      'bank_amount': bankAmount,
      'bank_account_id': bankAmount == 0 ? null : bankAccountId,
      'pledge_id': pledgeId,
      'notes': notes,
      'created_by': createdBy,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ─── Create ──────────────────────────────────────────────────────────────────

  Future<int> createLoanDisbursed(
    int pledgeId,
    double amount,
    double cashAmount,
    double bankAmount,
    String date, {
    int? bankAccountId,
    String? notes,
    int? createdBy,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await AppDatabase.instance.database;
    return _insert(db,
        date: date,
        paymentType: PaymentType.loanDisbursed,
        direction: PaymentDirection.outward,
        amount: amount,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        bankAccountId: bankAccountId,
        pledgeId: pledgeId,
        notes: notes,
        createdBy: createdBy);
  }

  Future<int> createLoanFullClosure(
    int pledgeId,
    double amount,
    double cashAmount,
    double bankAmount,
    String date, {
    int? bankAccountId,
    String? notes,
    int? createdBy,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await AppDatabase.instance.database;
    return _insert(db,
        date: date,
        paymentType: PaymentType.loanFullClosure,
        direction: PaymentDirection.inward,
        amount: amount,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        bankAccountId: bankAccountId,
        pledgeId: pledgeId,
        notes: notes,
        createdBy: createdBy);
  }

  Future<int> createRenewalInterestPaid(
    int pledgeId,
    double amount,
    double cashAmount,
    double bankAmount,
    String date, {
    int? bankAccountId,
    String? notes,
    int? createdBy,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await AppDatabase.instance.database;
    return _insert(db,
        date: date,
        paymentType: PaymentType.renewalInterestPaid,
        direction: PaymentDirection.inward,
        amount: amount,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        bankAccountId: bankAccountId,
        pledgeId: pledgeId,
        notes: notes,
        createdBy: createdBy);
  }

  Future<int> createPartPayment(
    int pledgeId,
    double amount,
    double cashAmount,
    double bankAmount,
    String subCategory,
    String date, {
    int? bankAccountId,
    String? notes,
    int? createdBy,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await AppDatabase.instance.database;
    return _insert(db,
        date: date,
        paymentType: PaymentType.partPaymentReceived,
        direction: PaymentDirection.inward,
        subCategory: subCategory,
        amount: amount,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        bankAccountId: bankAccountId,
        pledgeId: pledgeId,
        notes: notes,
        createdBy: createdBy);
  }

  Future<int> createLoanIncreaseDisbursed(
    int pledgeId,
    double amount,
    double cashAmount,
    double bankAmount,
    String subCategory,
    String date, {
    int? bankAccountId,
    String? notes,
    int? createdBy,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await AppDatabase.instance.database;
    return _insert(db,
        date: date,
        paymentType: PaymentType.loanIncreaseDisbursed,
        direction: PaymentDirection.outward,
        subCategory: subCategory,
        amount: amount,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        bankAccountId: bankAccountId,
        pledgeId: pledgeId,
        notes: notes,
        createdBy: createdBy);
  }

  /// [ledgerAccountId] is the chart_of_accounts row linked to the chosen
  /// expense category — the posting engine's sole account reference.
  Future<int> createExpense(
    double amount,
    double cashAmount,
    double bankAmount,
    String categoryName,
    String date, {
    int? ledgerAccountId,
    int? bankAccountId,
    String? notes,
    int? createdBy,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await AppDatabase.instance.database;
    return _insert(db,
        date: date,
        paymentType: PaymentType.expense,
        direction: PaymentDirection.outward,
        subCategory: categoryName,
        ledgerAccountId: ledgerAccountId,
        amount: amount,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        bankAccountId: bankAccountId,
        pledgeId: null,
        notes: notes,
        createdBy: createdBy);
  }

  /// Valid sub_category values for CAPITAL rows (application-level
  /// validation — same approach as ADJUSTMENT's sub types).
  static const _capitalSubCategories = {
    PaymentSubCategory.capitalContribution,
    PaymentSubCategory.drawings,
    PaymentSubCategory.tdsPayment,
  };

  /// Partner money movement: one CAPITAL row whose [subCategory] is
  /// CAPITAL_CONTRIBUTION (in), DRAWINGS (out) or TDS_PAYMENT (out).
  /// [ledgerAccountId] points at the partner's capital account in
  /// chart_of_accounts — the sole partner reference (never name text).
  Future<int> createCapital(
    double amount,
    double cashAmount,
    double bankAmount,
    String subCategory,
    String date, {
    required int ledgerAccountId,
    int? bankAccountId,
    String? notes,
    int? createdBy,
    DatabaseExecutor? txn,
  }) async {
    if (!_capitalSubCategories.contains(subCategory)) {
      throw ArgumentError.value(
          subCategory, 'subCategory', 'Not a valid CAPITAL sub_category');
    }
    final db = txn ?? await AppDatabase.instance.database;
    return _insert(db,
        date: date,
        paymentType: PaymentType.capital,
        direction: subCategory == PaymentSubCategory.capitalContribution
            ? PaymentDirection.inward
            : PaymentDirection.outward,
        subCategory: subCategory,
        ledgerAccountId: ledgerAccountId,
        amount: amount,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        bankAccountId: bankAccountId,
        pledgeId: null,
        notes: notes,
        createdBy: createdBy);
  }

  Future<int> createAdjustment(
    double amount,
    double cashAmount,
    double bankAmount,
    String subCategory,
    String direction,
    String date, {
    int? bankAccountId,
    String? notes,
    int? createdBy,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await AppDatabase.instance.database;
    return _insert(db,
        date: date,
        paymentType: PaymentType.adjustment,
        direction: direction,
        subCategory: subCategory,
        amount: amount,
        cashAmount: cashAmount,
        bankAmount: bankAmount,
        bankAccountId: bankAccountId,
        pledgeId: null,
        notes: notes,
        createdBy: createdBy);
  }

  // ─── Read ────────────────────────────────────────────────────────────────────

  Future<List<PaymentModel>> getPaymentsForDate(String date) =>
      _query(where: 'DATE(payment_date) = ?', args: [date]);

  Future<List<PaymentModel>> getPaymentsInForDate(String date) => _query(
      where: "DATE(payment_date) = ? AND direction = 'in'", args: [date]);

  Future<List<PaymentModel>> getPaymentsOutForDate(String date) => _query(
      where: "DATE(payment_date) = ? AND direction = 'out'", args: [date]);

  Future<List<PaymentModel>> getPaymentsForPledge(int pledgeId) =>
      _query(where: 'pledge_id = ?', args: [pledgeId]);

  Future<List<PaymentModel>> _query({
    required String where,
    required List<Object?> args,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('payments',
        where: where, whereArgs: args, orderBy: 'created_at ASC');
    return rows.map(PaymentModel.fromMap).toList();
  }

  // ─── Read (by id / by type) ──────────────────────────────────────────────────

  Future<PaymentModel?> getById(int id) async {
    final rows = await _query(where: 'id = ?', args: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<PaymentModel>> getByDateAndTypes(
      String date, List<String> paymentTypes) async {
    if (paymentTypes.isEmpty) return [];
    final db = await AppDatabase.instance.database;
    final ph = List.filled(paymentTypes.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM payments WHERE DATE(payment_date) = ? '
      'AND payment_type IN ($ph) ORDER BY created_at ASC',
      [date, ...paymentTypes],
    );
    return rows.map(PaymentModel.fromMap).toList();
  }

  /// Finds the paired row for a two-row transfer adjustment (CASH_TO_BANK,
  /// BANK_TO_CASH, BANK_TO_BANK). The partner has the same date, sub_category,
  /// and amount but the opposite direction.
  Future<PaymentModel?> getAdjustmentPartner(
    int excludeId,
    String date,
    String subCategory,
    double amount,
    String oppositeDirection,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      "SELECT * FROM payments WHERE id != ? AND DATE(payment_date) = ? "
      "AND payment_type = 'ADJUSTMENT' AND sub_category = ? "
      "AND ABS(amount - ?) < 0.01 AND direction = ? LIMIT 1",
      [excludeId, date, subCategory, amount, oppositeDirection],
    );
    return rows.isEmpty ? null : PaymentModel.fromMap(rows.first);
  }

  /// Partial UPDATE for a payments row. Only non-null supplied fields are
  /// written. Pass [clearBankAccountId] = true to explicitly set it to NULL.
  ///
  /// Always stamps `updated_at` — the ledger's lock-time staleness check
  /// compares it against the posted journal entry's created_at to decide
  /// whether an unlock-edit-relock made that entry stale.
  Future<void> updatePaymentFields(
    DatabaseExecutor db,
    int id, {
    double? amount,
    double? cashAmount,
    double? bankAmount,
    int? bankAccountId,
    bool clearBankAccountId = false,
    String? notes,
    String? subCategory,
    int? ledgerAccountId,
    String? direction,
  }) async {
    final values = <String, dynamic>{};
    if (amount != null) values['amount'] = amount;
    if (cashAmount != null) values['cash_amount'] = cashAmount;
    if (bankAmount != null) values['bank_amount'] = bankAmount;
    if (bankAccountId != null) values['bank_account_id'] = bankAccountId;
    if (clearBankAccountId) values['bank_account_id'] = null;
    if (notes != null) values['notes'] = notes;
    if (subCategory != null) values['sub_category'] = subCategory;
    if (ledgerAccountId != null) {
      values['ledger_account_id'] = ledgerAccountId;
    }
    if (direction != null) values['direction'] = direction;
    if (values.isEmpty) return;
    values['updated_at'] = DateTime.now().toIso8601String();
    await db.update('payments', values, where: 'id = ?', whereArgs: [id]);
  }

  /// Hard-deletes a single payments row. Use inside a [db.transaction] so the
  /// caller can atomically delete paired rows (e.g. both legs of a transfer)
  /// and write an audit log entry.
  Future<void> deletePayment(DatabaseExecutor txn, int id) async {
    await txn.delete('payments', where: 'id = ?', whereArgs: [id]);
  }

  // Combined bank total across all accounts (used by daily_balance combined-total columns).
  Future<double> getTotalCashInForDate(String date) =>
      _sum('cash_amount', 'in', date);
  Future<double> getTotalBankInForDate(String date) =>
      _sum('bank_amount', 'in', date);
  Future<double> getTotalCashOutForDate(String date) =>
      _sum('cash_amount', 'out', date);
  Future<double> getTotalBankOutForDate(String date) =>
      _sum('bank_amount', 'out', date);

  // Per-account bank totals (used by daily_account_balance drill-down).
  Future<double> getTotalBankInForDateAndAccount(String date, int bankAccountId) =>
      _sumForAccount('bank_amount', 'in', date, bankAccountId);
  Future<double> getTotalBankOutForDateAndAccount(String date, int bankAccountId) =>
      _sumForAccount('bank_amount', 'out', date, bankAccountId);

  Future<double> _sum(String column, String direction, String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM($column), 0) AS s FROM payments '
      'WHERE direction = ? AND DATE(payment_date) = ?',
      [direction, date],
    );
    return (rows.first['s'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> _sumForAccount(
      String column, String direction, String date, int bankAccountId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM($column), 0) AS s FROM payments '
      'WHERE direction = ? AND DATE(payment_date) = ? AND bank_account_id = ?',
      [direction, date, bankAccountId],
    );
    return (rows.first['s'] as num?)?.toDouble() ?? 0.0;
  }
}
