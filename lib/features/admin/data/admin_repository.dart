import '../../../core/database/app_database.dart';
import '../../calculator/data/interest_calculator.dart';

// ─── Session ──────────────────────────────────────────────────────────────────

class AdminSession {
  static DateTime? _lastAuth;

  static bool get isValid =>
      _lastAuth != null &&
      DateTime.now().difference(_lastAuth!) < const Duration(minutes: 30);

  static void authenticate() => _lastAuth = DateTime.now();
  static void invalidate() => _lastAuth = null;
}

// ─── Data classes ─────────────────────────────────────────────────────────────

class AdminOverview {
  const AdminOverview({
    required this.openPledges,
    required this.totalOutstanding,
    required this.totalGoldGrams,
    required this.totalCustomers,
  });
  final int openPledges;
  final double totalOutstanding;
  final double totalGoldGrams;
  final int totalCustomers;
}

class TodaySummary {
  const TodaySummary({
    required this.newPledgesCount,
    required this.newPledgesAmount,
    required this.closedPledgesCount,
    required this.closedPledgesAmount,
    required this.interestCollected,
    required this.netCashMovement,
  });
  final int newPledgesCount;
  final double newPledgesAmount;
  final int closedPledgesCount;
  final double closedPledgesAmount;
  final double interestCollected;
  final double netCashMovement;
}

class AgeingBucket {
  const AgeingBucket({
    required this.bucket,
    required this.label,
    required this.count,
    required this.totalAmount,
  });
  final String bucket; // '0','1','2','3'
  final String label;
  final int count;
  final double totalAmount;
}

class AgeingPledge {
  const AgeingPledge({
    required this.id,
    required this.pledgeNumber,
    required this.pledgeDate,
    required this.loanAmount,
    required this.interestRate,
    required this.interestDue,
    required this.totalDue,
    required this.daysOld,
    this.customerName,
  });
  final int id;
  final String pledgeNumber;
  final String pledgeDate;
  final double loanAmount;
  final double interestRate;
  final double interestDue;
  final double totalDue;
  final int daysOld;
  final String? customerName;

  String get ageLabel {
    final months = daysOld ~/ 30;
    final days = daysOld % 30;
    if (months == 0) return '$daysOld days';
    if (days == 0) return '$months months';
    return '$months months $days days';
  }
}

class InterestSummary {
  const InterestSummary({
    required this.thisMonth,
    required this.lastMonth,
    required this.thisYear,
  });
  final double thisMonth;
  final double lastMonth;
  final double thisYear;
}

class BusinessHealth {
  const BusinessHealth({
    required this.topLargest,
    required this.topOldest,
    required this.lastBackupAt,
    required this.daysSinceBackup,
  });
  final List<Map<String, dynamic>> topLargest;
  final List<Map<String, dynamic>> topOldest;
  final String? lastBackupAt;
  final int daysSinceBackup;
}

class ReportData {
  const ReportData({
    required this.newPledgesCount,
    required this.newPledgesAmount,
    required this.closedCount,
    required this.closedAmount,
    required this.renewedCount,
    required this.renewedAmount,
    required this.closingOpenCount,
    required this.closingOpenAmount,
    required this.goldReceived,
    required this.goldReleased,
    required this.goldStock,
    required this.purityBreakdown,
    required this.totalDisbursed,
    required this.totalCollected,
    required this.totalInterest,
    required this.totalExpenses,
    required this.expenseBreakdown,
    required this.netPosition,
  });

  final int newPledgesCount;
  final double newPledgesAmount;
  final int closedCount;
  final double closedAmount;
  final int renewedCount;
  final double renewedAmount;
  final int closingOpenCount;
  final double closingOpenAmount;

  final double goldReceived;
  final double goldReleased;
  final double goldStock;
  final List<Map<String, dynamic>> purityBreakdown;

  final double totalDisbursed;
  final double totalCollected;
  final double totalInterest;
  final double totalExpenses;
  final List<Map<String, dynamic>> expenseBreakdown;
  final double netPosition;
}

// ─── Repository ───────────────────────────────────────────────────────────────

class AdminRepository {
  AdminRepository._();
  static final instance = AdminRepository._();

  // ── Overview ─────────────────────────────────────────────────────────────────

  Future<AdminOverview> getOverview() async {
    final db = await AppDatabase.instance.database;
    final results = await Future.wait([
      db.rawQuery(
          "SELECT COUNT(*) as c, COALESCE(SUM(principal_amount),0) as s "
          "FROM pledges WHERE status='open'"),
      db.rawQuery(
          "SELECT COALESCE(SUM(pi.net_weight),0) as g "
          "FROM pledge_items pi JOIN pledges p ON pi.pledge_id=p.id "
          "WHERE p.status='open'"),
      db.rawQuery(
          "SELECT COUNT(DISTINCT customer_id) as c FROM pledges "
          "WHERE status='open' AND customer_id IS NOT NULL"),
    ]);

    return AdminOverview(
      openPledges: (results[0].first['c'] as int?) ?? 0,
      totalOutstanding: (results[0].first['s'] as num?)?.toDouble() ?? 0,
      totalGoldGrams: (results[1].first['g'] as num?)?.toDouble() ?? 0,
      totalCustomers: (results[2].first['c'] as int?) ?? 0,
    );
  }

  // ── Today ─────────────────────────────────────────────────────────────────────

  Future<TodaySummary> getTodaySummary() async {
    final db = await AppDatabase.instance.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final results = await Future.wait([
      db.rawQuery(
          "SELECT COUNT(*) as c, COALESCE(SUM(principal_amount),0) as s "
          "FROM pledges WHERE start_date=?",
          [today]),
      db.rawQuery(
          "SELECT COUNT(*) as c, COALESCE(SUM(total_amount_collected),0) as s "
          "FROM pledges WHERE closure_date=? AND status IN ('closed','renewed')",
          [today]),
      db.rawQuery(
          "SELECT COALESCE(SUM(total_interest_paid),0) as s FROM pledges "
          "WHERE closure_date=? AND status IN ('closed','renewed')",
          [today]),
      db.rawQuery(
          "SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE -amount END),0) as s "
          "FROM transactions WHERE transaction_date=?",
          [today]),
    ]);

    return TodaySummary(
      newPledgesCount: (results[0].first['c'] as int?) ?? 0,
      newPledgesAmount: (results[0].first['s'] as num?)?.toDouble() ?? 0,
      closedPledgesCount: (results[1].first['c'] as int?) ?? 0,
      closedPledgesAmount: (results[1].first['s'] as num?)?.toDouble() ?? 0,
      interestCollected: (results[2].first['s'] as num?)?.toDouble() ?? 0,
      netCashMovement: (results[3].first['s'] as num?)?.toDouble() ?? 0,
    );
  }

  // ── Ageing Buckets ────────────────────────────────────────────────────────────

  Future<List<AgeingBucket>> getAgeingBuckets() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery("""
      SELECT
        CASE
          WHEN (julianday('now') - julianday(start_date)) <= 180 THEN '0'
          WHEN (julianday('now') - julianday(start_date)) <= 365 THEN '1'
          WHEN (julianday('now') - julianday(start_date)) <= 730 THEN '2'
          ELSE '3'
        END as bucket,
        COUNT(*) as cnt,
        COALESCE(SUM(principal_amount),0) as total
      FROM pledges
      WHERE status='open'
      GROUP BY bucket
    """);

    final map = {for (final r in rows) r['bucket'] as String: r};

    return [
      _makeBucket('0', '0–6 Months', map),
      _makeBucket('1', '6–12 Months', map),
      _makeBucket('2', '1–2 Years', map),
      _makeBucket('3', '2+ Years', map),
    ];
  }

  AgeingBucket _makeBucket(
      String bucket, String label, Map<String, dynamic> map) {
    final row = map[bucket];
    return AgeingBucket(
      bucket: bucket,
      label: label,
      count: (row?['cnt'] as int?) ?? 0,
      totalAmount: (row?['total'] as num?)?.toDouble() ?? 0,
    );
  }

  // ── Ageing Drill Down ─────────────────────────────────────────────────────────

  Future<List<AgeingPledge>> getAgeingPledges(String bucket) async {
    final db = await AppDatabase.instance.database;

    const daysConditions = {
      '0': '(julianday(\'now\') - julianday(start_date)) <= 180',
      '1':
          '(julianday(\'now\') - julianday(start_date)) > 180 AND (julianday(\'now\') - julianday(start_date)) <= 365',
      '2':
          '(julianday(\'now\') - julianday(start_date)) > 365 AND (julianday(\'now\') - julianday(start_date)) <= 730',
      '3': '(julianday(\'now\') - julianday(start_date)) > 730',
    };

    final condition = daysConditions[bucket] ?? daysConditions['0']!;
    final rows = await db.rawQuery(
      "SELECT *, CAST(julianday('now') - julianday(start_date) AS INTEGER) as days_old "
      "FROM pledges WHERE status='open' AND $condition "
      "ORDER BY start_date ASC",
    );

    final today = DateTime.now();
    return rows.map((row) {
      final pledgeDate = DateTime.tryParse(row['start_date'] as String? ?? '') ??
          today;
      final principal = (row['principal_amount'] as num?)?.toDouble() ?? 0;
      final rate = (row['interest_rate'] as num?)?.toDouble() ?? 18;
      final daysOld = (row['days_old'] as int?) ?? 0;

      final calc = InterestCalculator.calculate(
        principal: principal,
        fromDate: pledgeDate,
        toDate: today,
        ratePercent: rate,
      );

      final name = row['customer_name'] as String?;
      return AgeingPledge(
        id: (row['id'] as int?) ?? 0,
        pledgeNumber: row['pledge_no'] as String? ?? '',
        pledgeDate: row['start_date'] as String? ?? '',
        loanAmount: principal,
        interestRate: rate,
        interestDue: calc.interest,
        totalDue: calc.total,
        daysOld: daysOld,
        customerName: (name != null && name.isNotEmpty) ? name : null,
      );
    }).toList();
  }

  // ── Interest Summary ──────────────────────────────────────────────────────────

  Future<InterestSummary> getInterestSummary() async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now();

    final thisMonthPfx =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final lastMonthDt =
        DateTime(now.year, now.month - 1, 1);
    final lastMonthPfx =
        '${lastMonthDt.year}-${lastMonthDt.month.toString().padLeft(2, '0')}';

    // Indian financial year: April of current year to March of next year
    // If month >= 4, year start = this year; else year start = last year
    final fyStartYear = now.month >= 4 ? now.year : now.year - 1;
    final fyStart = '$fyStartYear-04-01';
    final fyEnd = '${fyStartYear + 1}-03-31';

    final results = await Future.wait([
      db.rawQuery(
          "SELECT COALESCE(SUM(total_interest_paid),0) as s FROM pledges "
          "WHERE closure_date LIKE ? AND status IN ('closed','renewed')",
          ['$thisMonthPfx%']),
      db.rawQuery(
          "SELECT COALESCE(SUM(total_interest_paid),0) as s FROM pledges "
          "WHERE closure_date LIKE ? AND status IN ('closed','renewed')",
          ['$lastMonthPfx%']),
      db.rawQuery(
          "SELECT COALESCE(SUM(total_interest_paid),0) as s FROM pledges "
          "WHERE closure_date BETWEEN ? AND ? AND status IN ('closed','renewed')",
          [fyStart, fyEnd]),
    ]);

    return InterestSummary(
      thisMonth: (results[0].first['s'] as num?)?.toDouble() ?? 0,
      lastMonth: (results[1].first['s'] as num?)?.toDouble() ?? 0,
      thisYear: (results[2].first['s'] as num?)?.toDouble() ?? 0,
    );
  }

  // ── Business Health ───────────────────────────────────────────────────────────

  Future<BusinessHealth> getBusinessHealth() async {
    final db = await AppDatabase.instance.database;

    final results = await Future.wait([
      db.rawQuery(
          "SELECT id, pledge_no, principal_amount, start_date, customer_name, "
          "CAST(julianday('now') - julianday(start_date) AS INTEGER) as days_old "
          "FROM pledges WHERE status='open' "
          "ORDER BY principal_amount DESC LIMIT 5"),
      db.rawQuery(
          "SELECT id, pledge_no, principal_amount, start_date, customer_name, "
          "CAST(julianday('now') - julianday(start_date) AS INTEGER) as days_old "
          "FROM pledges WHERE status='open' "
          "ORDER BY start_date ASC LIMIT 5"),
      db.rawQuery(
          "SELECT created_at FROM backup_log "
          "ORDER BY created_at DESC LIMIT 1"),
    ]);

    String? lastBackupAt;
    int daysSinceBackup = 9999;

    if (results[2].isNotEmpty) {
      lastBackupAt = results[2].first['created_at'] as String?;
      if (lastBackupAt != null) {
        final backupDt = DateTime.tryParse(lastBackupAt);
        if (backupDt != null) {
          daysSinceBackup = DateTime.now().difference(backupDt).inDays;
        }
      }
    }

    return BusinessHealth(
      topLargest: results[0].map((r) => Map<String, dynamic>.from(r)).toList(),
      topOldest: results[1].map((r) => Map<String, dynamic>.from(r)).toList(),
      lastBackupAt: lastBackupAt,
      daysSinceBackup: daysSinceBackup,
    );
  }

  // ── Reports ───────────────────────────────────────────────────────────────────

  Future<ReportData> getReportData(String fromDate, String toDate) async {
    final db = await AppDatabase.instance.database;

    final results = await Future.wait([
      // New pledges in period
      db.rawQuery(
          "SELECT COUNT(*) as c, COALESCE(SUM(principal_amount),0) as s "
          "FROM pledges WHERE start_date BETWEEN ? AND ?",
          [fromDate, toDate]),
      // Closed pledges in period
      db.rawQuery(
          "SELECT COUNT(*) as c, COALESCE(SUM(total_amount_collected),0) as s "
          "FROM pledges WHERE closure_date BETWEEN ? AND ? AND status='closed'",
          [fromDate, toDate]),
      // Renewed pledges in period
      db.rawQuery(
          "SELECT COUNT(*) as c, COALESCE(SUM(total_amount_collected),0) as s "
          "FROM pledges WHERE closure_date BETWEEN ? AND ? AND status='renewed'",
          [fromDate, toDate]),
      // Closing open pledges (open as of toDate)
      db.rawQuery(
          "SELECT COUNT(*) as c, COALESCE(SUM(principal_amount),0) as s "
          "FROM pledges WHERE status='open' AND start_date <= ?",
          [toDate]),
      // Gold received (from items of pledges created in period)
      db.rawQuery(
          "SELECT COALESCE(SUM(pi.net_weight),0) as g "
          "FROM pledge_items pi JOIN pledges p ON pi.pledge_id=p.id "
          "WHERE p.start_date BETWEEN ? AND ?",
          [fromDate, toDate]),
      // Gold released (from items of pledges closed in period)
      db.rawQuery(
          "SELECT COALESCE(SUM(pi.net_weight),0) as g "
          "FROM pledge_items pi JOIN pledges p ON pi.pledge_id=p.id "
          "WHERE p.closure_date BETWEEN ? AND ? AND p.status IN ('closed','renewed')",
          [fromDate, toDate]),
      // Current gold stock
      db.rawQuery(
          "SELECT COALESCE(SUM(pi.net_weight),0) as g "
          "FROM pledge_items pi JOIN pledges p ON pi.pledge_id=p.id "
          "WHERE p.status='open'"),
      // Gold by purity for new pledges in period
      db.rawQuery(
          "SELECT p.purity, COALESCE(SUM(pi.net_weight),0) as g, COUNT(DISTINCT p.id) as c "
          "FROM pledge_items pi JOIN pledges p ON pi.pledge_id=p.id "
          "WHERE p.start_date BETWEEN ? AND ? "
          "GROUP BY p.purity ORDER BY g DESC",
          [fromDate, toDate]),
      // Total disbursed in period (transactions)
      db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) as s FROM transactions "
          "WHERE type='loan_disbursed' AND transaction_date BETWEEN ? AND ?",
          [fromDate, toDate]),
      // Total collected in period
      db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) as s FROM transactions "
          "WHERE type='payment_received' AND transaction_date BETWEEN ? AND ?",
          [fromDate, toDate]),
      // Interest earned in period
      db.rawQuery(
          "SELECT COALESCE(SUM(total_interest_paid),0) as s FROM pledges "
          "WHERE closure_date BETWEEN ? AND ? AND status IN ('closed','renewed')",
          [fromDate, toDate]),
      // Expenses in period
      db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) as s FROM transactions "
          "WHERE type='expense' AND transaction_date BETWEEN ? AND ?",
          [fromDate, toDate]),
      // Expense by category
      db.rawQuery(
          "SELECT ec.name, COALESCE(SUM(t.amount),0) as s "
          "FROM transactions t LEFT JOIN expense_categories ec ON t.expense_category_id=ec.id "
          "WHERE t.type='expense' AND t.transaction_date BETWEEN ? AND ? "
          "GROUP BY ec.id ORDER BY s DESC",
          [fromDate, toDate]),
    ]);

    final disbursed = (results[8].first['s'] as num?)?.toDouble() ?? 0;
    final collected = (results[9].first['s'] as num?)?.toDouble() ?? 0;
    final expenses = (results[11].first['s'] as num?)?.toDouble() ?? 0;

    return ReportData(
      newPledgesCount: (results[0].first['c'] as int?) ?? 0,
      newPledgesAmount: (results[0].first['s'] as num?)?.toDouble() ?? 0,
      closedCount: (results[1].first['c'] as int?) ?? 0,
      closedAmount: (results[1].first['s'] as num?)?.toDouble() ?? 0,
      renewedCount: (results[2].first['c'] as int?) ?? 0,
      renewedAmount: (results[2].first['s'] as num?)?.toDouble() ?? 0,
      closingOpenCount: (results[3].first['c'] as int?) ?? 0,
      closingOpenAmount: (results[3].first['s'] as num?)?.toDouble() ?? 0,
      goldReceived: (results[4].first['g'] as num?)?.toDouble() ?? 0,
      goldReleased: (results[5].first['g'] as num?)?.toDouble() ?? 0,
      goldStock: (results[6].first['g'] as num?)?.toDouble() ?? 0,
      purityBreakdown:
          results[7].map((r) => Map<String, dynamic>.from(r)).toList(),
      totalDisbursed: disbursed,
      totalCollected: collected,
      totalInterest: (results[10].first['s'] as num?)?.toDouble() ?? 0,
      totalExpenses: expenses,
      expenseBreakdown:
          results[12].map((r) => Map<String, dynamic>.from(r)).toList(),
      netPosition: collected - disbursed - expenses,
    );
  }

  // ── Day Unlock ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getDayBalance(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'daily_balance',
      where: 'business_date = ?',
      whereArgs: [date],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<void> unlockDay(String date, String reason) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.update(
        'daily_balance',
        {
          'is_locked': 0,
          'locked_at': null,
          'locked_by': null,
          'updated_at': now,
        },
        where: 'business_date = ?',
        whereArgs: [date],
      );

      await txn.insert('audit_log', {
        'entity_type': 'daily_balance',
        'entity_id': date,
        'action': 'unlock_day',
        'old_value_json': null,
        'new_value_json': null,
        'reason': reason,
        'created_by': null,
        'created_at': now,
      });
    });
  }
}
