import '../../../core/database/app_database.dart';
import '../../../core/services/ledger_posting_service.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../pledges/data/payments_repository.dart';
import 'daily_account_balance_repository.dart';

/// Live cash/UPI movement totals for a day, computed from the `payments` table.
class DayTotals {
  const DayTotals({
    required this.openingCash,
    required this.openingUpi,
    required this.cashIn,
    required this.upiIn,
    required this.cashOut,
    required this.upiOut,
  });

  final double openingCash;
  final double openingUpi;
  final double cashIn;
  final double upiIn;
  final double cashOut;
  final double upiOut;

  double get closingCash => openingCash + cashIn - cashOut;
  double get closingUpi => openingUpi + upiIn - upiOut;
}

class DailyBalance {
  const DailyBalance({
    this.id,
    required this.businessDate,
    required this.openingCash,
    required this.openingUpi,
    this.closingCash,
    this.closingUpi,
    this.cashIn,
    this.upiIn,
    this.cashOut,
    this.upiOut,
    required this.isLocked,
    this.lockedAt,
    this.lockedBy,
  });

  final int? id;
  final String businessDate;
  final double openingCash;
  final double openingUpi;
  final double? closingCash;
  final double? closingUpi;
  final double? cashIn;
  final double? upiIn;
  final double? cashOut;
  final double? upiOut;
  final bool isLocked;
  final String? lockedAt;
  final int? lockedBy;

  factory DailyBalance.fromMap(Map<String, dynamic> map) {
    return DailyBalance(
      id: map['id'] as int?,
      businessDate: map['business_date'] as String? ?? '',
      openingCash: (map['opening_cash'] as num?)?.toDouble() ?? 0.0,
      openingUpi: (map['opening_upi'] as num?)?.toDouble() ?? 0.0,
      closingCash: (map['closing_cash'] as num?)?.toDouble(),
      closingUpi: (map['closing_upi'] as num?)?.toDouble(),
      cashIn: (map['cash_in'] as num?)?.toDouble(),
      upiIn: (map['upi_in'] as num?)?.toDouble(),
      cashOut: (map['cash_out'] as num?)?.toDouble(),
      upiOut: (map['upi_out'] as num?)?.toDouble(),
      isLocked: (map['is_locked'] as int?) == 1,
      lockedAt: map['locked_at'] as String?,
      lockedBy: map['locked_by'] as int?,
    );
  }
}

class DailyBalanceRepository {
  DailyBalanceRepository._();
  static final DailyBalanceRepository instance = DailyBalanceRepository._();

  final _payments = PaymentsRepository.instance;
  final _settings = AppSettingsRepository();

  Future<DailyBalance?> getForDate(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('daily_balance',
        where: 'business_date = ?', whereArgs: [date], limit: 1);
    return rows.isEmpty ? null : DailyBalance.fromMap(rows.first);
  }

  /// Returns the existing row for [date], or creates one with the opening
  /// balance derived from the previous day's closing (or settings for the very
  /// first day).
  Future<DailyBalance> getOrCreateForDate(String date) async {
    final existing = await getForDate(date);
    if (existing != null) return existing;

    final opening = await _openingFor(date);
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('daily_balance', {
      'business_date': date,
      'opening_cash': opening.cash,
      'opening_upi': opening.upi,
      'is_locked': 0,
      'created_at': now,
      'updated_at': now,
    });
    return DailyBalance(
      id: id,
      businessDate: date,
      openingCash: opening.cash,
      openingUpi: opening.upi,
      isLocked: false,
    );
  }

  /// Opening balance for [date]: the previous day's closing, or the configured
  /// starting balance (settings) when no earlier day exists.
  Future<({double cash, double upi})> _openingFor(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'daily_balance',
      where: 'business_date < ?',
      whereArgs: [date],
      orderBy: 'business_date DESC',
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final prev = DailyBalance.fromMap(rows.first);
      if (prev.isLocked && prev.closingCash != null) {
        return (cash: prev.closingCash!, upi: prev.closingUpi ?? 0.0);
      }
      // Unlocked previous day: compute its closing live.
      final t = await calculateTotalsForDate(prev.businessDate,
          openingCash: prev.openingCash, openingUpi: prev.openingUpi);
      return (cash: t.closingCash, upi: t.closingUpi);
    }

    final cash =
        double.tryParse(await _settings.getString('opening_cash') ?? '0') ?? 0;
    final upi =
        double.tryParse(await _settings.getString('opening_upi') ?? '0') ?? 0;
    return (cash: cash, upi: upi);
  }

  /// Live totals for [date], computed from the payments ledger. Opening values
  /// are derived automatically unless supplied.
  Future<DayTotals> calculateTotalsForDate(
    String date, {
    double? openingCash,
    double? openingUpi,
  }) async {
    double oCash = openingCash ?? 0;
    double oUpi = openingUpi ?? 0;
    if (openingCash == null || openingUpi == null) {
      final o = await _openingFor(date);
      oCash = openingCash ?? o.cash;
      oUpi = openingUpi ?? o.upi;
    }

    final results = await Future.wait([
      _payments.getTotalCashInForDate(date),
      _payments.getTotalBankInForDate(date),
      _payments.getTotalCashOutForDate(date),
      _payments.getTotalBankOutForDate(date),
    ]);

    return DayTotals(
      openingCash: oCash,
      openingUpi: oUpi,
      cashIn: results[0],
      upiIn: results[1],
      cashOut: results[2],
      upiOut: results[3],
    );
  }

  /// Calculates final totals from the payments ledger, stores them, and locks
  /// the day. Also freezes per-account daily_account_balance rows and posts
  /// the day's journal entries — all in one transaction, so a posting failure
  /// (unbalanced entry, unmapped account) rolls the whole lock back and the
  /// day stays unlocked. Throws [LedgerPostingException] in that case.
  Future<DayTotals> lockDay(String date, int? userId) async {
    final record = await getOrCreateForDate(date);
    final totals = await calculateTotalsForDate(date,
        openingCash: record.openingCash, openingUpi: record.openingUpi);

    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'daily_balance',
        {
          'cash_in': totals.cashIn,
          'upi_in': totals.upiIn,
          'cash_out': totals.cashOut,
          'upi_out': totals.upiOut,
          'closing_cash': totals.closingCash,
          'closing_upi': totals.closingUpi,
          'is_locked': 1,
          'locked_at': now,
          'locked_by': userId,
          'updated_at': now,
        },
        where: 'business_date = ?',
        whereArgs: [date],
      );

      // Freeze per-account balances alongside the combined total.
      if (record.id != null) {
        await DailyAccountBalanceRepository.instance
            .lockAllForDate(date, record.id!, txn: txn);
      }

      // Day End & Close is the ledger's posting moment: generate the day's
      // journal entries from the final, locked state.
      await LedgerPostingService.instance
          .postForDate(date, createdBy: userId, txn: txn);
    });

    return totals;
  }

  // ─── Unlocked-day detection & cascade (backdated entries) ───────────────────

  /// Returns the earliest business_date in daily_balance, or null if no records exist.
  Future<String?> getFirstRecordDate() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'daily_balance',
      columns: ['business_date'],
      orderBy: 'business_date ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['business_date'] as String;
  }

  /// All dates in [fromDate, toDate) that are NOT locked — including days with
  /// no `daily_balance` row at all (never closed) and days whose row has
  /// is_locked = 0 (admin-unlocked). This is the correct source for the
  /// "unlocked previous days" banner and for sequential-lock enforcement.
  Future<List<String>> getUnclosedDaysBefore(String toDate,
      {required String fromDate}) async {
    final db = await AppDatabase.instance.database;

    // Fetch every row in the range so we know which dates have been locked.
    final rows = await db.query(
      'daily_balance',
      columns: ['business_date', 'is_locked'],
      where: 'business_date >= ? AND business_date < ?',
      whereArgs: [fromDate, toDate],
    );

    // Set of dates that have a locked row.
    final lockedDates = <String>{
      for (final r in rows)
        if ((r['is_locked'] as int?) == 1) r['business_date'] as String,
    };

    // Walk every calendar day in [fromDate, toDate); collect those not locked.
    final result = <String>[];
    var cur = _parseIso(fromDate);
    final end = _parseIso(toDate);
    while (cur.isBefore(end)) {
      final iso = _fmtIso(cur);
      if (!lockedDates.contains(iso)) result.add(iso);
      cur = cur.add(const Duration(days: 1));
    }
    return result;
  }

  static DateTime _parseIso(String iso) {
    final p = iso.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static String _fmtIso(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  /// Business dates strictly before [date] that have an unlocked
  /// `daily_balance` row, oldest first. Only finds EXISTING rows with
  /// is_locked = 0 — does NOT count days with no row. Prefer
  /// [getUnclosedDaysBefore] for banner/lock-guard use.
  Future<List<String>> getUnlockedDaysBefore(String date,
      {String? fromDate}) async {
    final db = await AppDatabase.instance.database;
    final String where;
    final List<Object?> args;
    if (fromDate != null) {
      where = 'business_date < ? AND business_date >= ? AND is_locked = 0';
      args = [date, fromDate];
    } else {
      where = 'business_date < ? AND is_locked = 0';
      args = [date];
    }
    final rows = await db.query(
      'daily_balance',
      columns: ['business_date'],
      where: where,
      whereArgs: args,
      orderBy: 'business_date ASC',
    );
    return rows.map((r) => r['business_date'] as String).toList();
  }

  /// True only if a `daily_balance` row exists for [date] and is locked.
  Future<bool> isDateLocked(String date) async {
    final rec = await getForDate(date);
    return rec?.isLocked ?? false;
  }

  /// Recomputes opening (from the previous day) and closing (from the payments
  /// ledger) for an unlocked [date] and stores them, without locking. Used by
  /// [cascadeFrom] so backdated entries update intermediate days.
  Future<void> refreshUnlockedDay(String date) async {
    final existing = await getForDate(date);
    if (existing != null && existing.isLocked) return;

    final opening = await _openingFor(date);
    final totals = await calculateTotalsForDate(date,
        openingCash: opening.cash, openingUpi: opening.upi);

    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final values = {
      'opening_cash': opening.cash,
      'opening_upi': opening.upi,
      'cash_in': totals.cashIn,
      'upi_in': totals.upiIn,
      'cash_out': totals.cashOut,
      'upi_out': totals.upiOut,
      'closing_cash': totals.closingCash,
      'closing_upi': totals.closingUpi,
      'updated_at': now,
    };
    if (existing == null) {
      await db.insert('daily_balance', {
        'business_date': date,
        ...values,
        'is_locked': 0,
        'created_at': now,
      });
    } else {
      await db.update('daily_balance', values,
          where: 'business_date = ?', whereArgs: [date]);
    }
  }

  /// Refreshes [date] and every following unlocked day so a backdated payment
  /// ripples forward. Stops at the first locked day.
  Future<void> cascadeFrom(String date) async {
    await refreshUnlockedDay(date);
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'daily_balance',
      columns: ['business_date', 'is_locked'],
      where: 'business_date > ?',
      whereArgs: [date],
      orderBy: 'business_date ASC',
    );
    for (final r in rows) {
      if ((r['is_locked'] as int?) == 1) break;
      await refreshUnlockedDay(r['business_date'] as String);
    }
  }

  Future<void> unlockDay(String date) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'daily_balance',
      {
        'is_locked': 0,
        'locked_at': null,
        'locked_by': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'business_date = ?',
      whereArgs: [date],
    );
  }
}
