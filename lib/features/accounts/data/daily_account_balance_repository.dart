import '../../../core/database/app_database.dart';
import 'bank_account_model.dart';
import 'bank_account_repository.dart';
import 'daily_account_balance_model.dart';

/// Per-account daily balance repository (`daily_account_balance` table).
///
/// Lock state is determined by joining to `daily_balance.is_locked` — this
/// table has no is_locked column of its own.
///
/// Before lock: totals are computed live from `payments` filtered by bank_account_id.
/// After lock:  frozen closing_balance / amount_in / amount_out are read directly.
class DailyAccountBalanceRepository {
  DailyAccountBalanceRepository._();
  static final DailyAccountBalanceRepository instance =
      DailyAccountBalanceRepository._();

  final _bankAccounts = BankAccountRepository.instance;

  // ─── Read ────────────────────────────────────────────────────────────────────

  /// Live or frozen per-account totals for [date], one entry per active account.
  ///
  /// If [isLocked] is true, reads from the frozen daily_account_balance rows.
  /// If false, computes in/out live from payments and derives opening from the
  /// most recent prior locked row (or account.openingBalance if none).
  Future<List<DailyAccountTotals>> getTotalsForDate(
    String date, {
    required bool isLocked,
    int? dailyBalanceId,
  }) async {
    final db = await AppDatabase.instance.database;
    final accounts = await _bankAccounts.getActiveForDate(date);

    if (isLocked && dailyBalanceId != null) {
      final dabRows = await db.query('daily_account_balance',
          where: 'daily_balance_id = ?', whereArgs: [dailyBalanceId]);

      return accounts.map((acct) {
        final row = dabRows.cast<Map<String, dynamic>?>().firstWhere(
              (r) => r!['bank_account_id'] == acct.id,
              orElse: () => null,
            );
        return DailyAccountTotals(
          bankAccount: acct,
          openingBalance: (row?['opening_balance'] as num?)?.toDouble() ?? 0.0,
          amountIn: (row?['amount_in'] as num?)?.toDouble() ?? 0.0,
          amountOut: (row?['amount_out'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
    }

    // Unlocked: compute live per account.
    return Future.wait(
      accounts.map((acct) async {
        final opening =
            await _openingBalanceForDate(db, date, acct);
        final bankIn = await _sumPayments(db, date, acct.id!, 'in');
        final bankOut = await _sumPayments(db, date, acct.id!, 'out');
        return DailyAccountTotals(
          bankAccount: acct,
          openingBalance: opening,
          amountIn: bankIn,
          amountOut: bankOut,
        );
      }),
    );
  }

  // ─── Lock ────────────────────────────────────────────────────────────────────

  /// Freezes per-account closing values for [date] into daily_account_balance.
  /// Called by DailyBalanceRepository.lockDay immediately after locking daily_balance.
  Future<void> lockAllForDate(String date, int dailyBalanceId) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final accounts = await _bankAccounts.getActiveForDate(date);

    for (final acct in accounts) {
      final opening =
          await _openingBalanceForDate(db, date, acct);
      final bankIn = await _sumPayments(db, date, acct.id!, 'in');
      final bankOut = await _sumPayments(db, date, acct.id!, 'out');
      final closing = opening + bankIn - bankOut;

      final existing = await db.query(
        'daily_account_balance',
        where: 'daily_balance_id = ? AND bank_account_id = ?',
        whereArgs: [dailyBalanceId, acct.id!],
        limit: 1,
      );

      if (existing.isEmpty) {
        await db.insert('daily_account_balance', {
          'daily_balance_id': dailyBalanceId,
          'bank_account_id': acct.id!,
          'opening_balance': opening,
          'closing_balance': closing,
          'amount_in': bankIn,
          'amount_out': bankOut,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        await db.update(
          'daily_account_balance',
          {
            'opening_balance': opening,
            'closing_balance': closing,
            'amount_in': bankIn,
            'amount_out': bankOut,
            'updated_at': now,
          },
          where: 'daily_balance_id = ? AND bank_account_id = ?',
          whereArgs: [dailyBalanceId, acct.id!],
        );
      }
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  /// Opening balance for [date] for [acct]: the closing_balance of the most
  /// recent prior locked row, or a fallback when none exists.
  ///
  /// Fallback logic distinguishes account type by whether an ADD_BANK payment
  /// exists on the account's start_date:
  ///   - No ADD_BANK payment → initial account (wizard / migration); return
  ///     acct.openingBalance (pre-existing money, not a cashbook transaction).
  ///   - ADD_BANK payment present → managed account; return 0.0 (the payment
  ///     is already counted in Bank In via _sumPayments).
  Future<double> _openingBalanceForDate(
    dynamic db,
    String date,
    BankAccount acct,
  ) async {
    final rows = await db.rawQuery('''
      SELECT dab.closing_balance
      FROM daily_account_balance dab
      JOIN daily_balance db_row ON db_row.id = dab.daily_balance_id
      WHERE dab.bank_account_id = ?
        AND db_row.business_date < ?
        AND db_row.is_locked = 1
      ORDER BY db_row.business_date DESC
      LIMIT 1
    ''', [acct.id!, date]) as List<Map<String, dynamic>>;

    if (rows.isNotEmpty && rows.first['closing_balance'] != null) {
      return (rows.first['closing_balance'] as num).toDouble();
    }

    final addBankRows = await db.rawQuery(
      "SELECT id FROM payments "
      "WHERE bank_account_id = ? AND sub_category = 'ADD_BANK' "
      "  AND DATE(payment_date) = ?",
      [acct.id!, acct.startDate],
    ) as List<Map<String, dynamic>>;

    return addBankRows.isEmpty ? acct.openingBalance : 0.0;
  }

  Future<double> _sumPayments(
    dynamic db,
    String date,
    int bankAccountId,
    String direction,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(bank_amount), 0) AS s FROM payments '
      'WHERE DATE(payment_date) = ? AND bank_account_id = ? AND direction = ?',
      [date, bankAccountId, direction],
    ) as List<Map<String, dynamic>>;
    return (rows.first['s'] as num?)?.toDouble() ?? 0.0;
  }
}
