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
      'direction': direction,
      'amount': amount,
      'cash_amount': cashAmount,
      'bank_amount': bankAmount,
      'bank_account_id': bankAccountId,
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

  Future<int> createExpense(
    double amount,
    double cashAmount,
    double bankAmount,
    String categoryName,
    String date, {
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
