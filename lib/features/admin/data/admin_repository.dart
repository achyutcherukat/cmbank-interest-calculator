import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../accounts/data/daily_balance_repository.dart';
import '../../accounts/data/day_reconciliation_repository.dart';
import '../../calculator/data/interest_calculator.dart';
import 'audit_log_repository.dart';

/// Human-readable pledge age.
///
/// * `< 30 days`  → "15 days"
/// * `< 365 days` → "8 months, 10 days" (day part dropped when zero)
/// * `>= 365 days`→ "1 year, 1 month, 5 days" (zero parts dropped)
///
/// Singular/plural handled per unit. Used everywhere age is shown in the
/// ageing section (summary + drill down).
String formatPledgeAge(int days) {
  if (days < 0) days = 0;

  String unit(int n, String singular) =>
      '$n ${n == 1 ? singular : '${singular}s'}';

  if (days < 30) return unit(days, 'day');

  if (days < 365) {
    final months = days ~/ 30;
    final remDays = days % 30;
    final parts = <String>[unit(months, 'month')];
    if (remDays > 0) parts.add(unit(remDays, 'day'));
    return parts.join(', ');
  }

  final years = days ~/ 365;
  final afterYears = days % 365;
  final months = afterYears ~/ 30;
  final remDays = afterYears % 30;
  final parts = <String>[unit(years, 'year')];
  if (months > 0) parts.add(unit(months, 'month'));
  if (remDays > 0) parts.add(unit(remDays, 'day'));
  return parts.join(', ');
}

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

class TodayActivity {
  const TodayActivity({
    required this.newCount,
    required this.newAmount,
    required this.closedCount,
    required this.closedAmount,
    required this.interestCollected,
    required this.activeCustomers,
  });
  final int newCount;
  final double newAmount;
  final int closedCount;
  final double closedAmount;
  final double interestCollected;
  final int activeCustomers;
}

/// One day's row of the gold-account ledger.
class GoldAccountDay {
  const GoldAccountDay({
    required this.date,
    required this.opening,
    required this.moneyIn,
    required this.moneyOut,
    required this.closing,
  });
  final String date; // ISO yyyy-MM-dd
  final double opening;
  final double moneyIn;
  final double moneyOut;
  final double closing;
}

/// Headline gold-account figures for the dashboard card.
class GoldAccountSummary {
  const GoldAccountSummary({
    required this.currentBalance,
    required this.yesterdayBalance,
  });
  final double currentBalance;
  final double yesterdayBalance;
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

  String get ageLabel => formatPledgeAge(daysOld);
}

class ActivityPledge {
  const ActivityPledge({
    required this.id,
    required this.pledgeNumber,
    required this.principalAmount,
    required this.interestPaid,
    required this.status,
    this.customerName,
  });
  final int id;
  final String pledgeNumber;
  final double principalAmount;
  final double interestPaid;
  final String status;
  final String? customerName;
}

class ActivityCustomer {
  const ActivityCustomer({
    required this.id,
    required this.name,
    this.phone,
  });
  final int id;
  final String name;
  final String? phone;
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
    required this.pledgeCount,
    required this.totalDisbursedPledges,
    required this.redeemedCount,
    required this.totalAmountRedeemed,
    required this.maxDayDisbursedAmount,
    required this.maxDayDisbursedDate,
    required this.goldReceived,
    required this.goldReleased,
    required this.goldStock,
    required this.goldStockDate,
    required this.totalInterest,
    required this.totalExpenses,
    required this.expenseBreakdown,
  });

  // Pledge Summary
  final int pledgeCount;              // pledges opened in period (any status, by start_date)
  final double totalDisbursedPledges; // sum of principal_amount for pledges opened in period
  final int redeemedCount;            // pledges closed in period (status='closed', by closure_date)
  final double totalAmountRedeemed;   // sum of principal_amount for pledges closed in period
  final double maxDayDisbursedAmount; // highest single-day principal sum in period
  final String maxDayDisbursedDate;   // ISO date of that day ('' if no data)

  final double goldReceived;
  final double goldReleased;
  final double? goldStock;    // null = no daily_stock record on or before period end
  final String goldStockDate; // ISO date of the daily_stock row used ('' if none)

  final double totalInterest;
  final double totalExpenses;
  final List<Map<String, dynamic>> expenseBreakdown;
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
          "SELECT COALESCE(SUM(net_weight),0) as g "
          "FROM pledges WHERE status='open'"),
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

  // ── Today's Activity ───────────────────────────────────────────────────────

  Future<TodayActivity> getTodayActivity({DateTime? date}) async {
    final db = await AppDatabase.instance.database;
    final d = (date ?? DateTime.now()).toIso8601String().substring(0, 10);

    final results = await Future.wait([
      // 0 — New loans: all pledges started on the given date regardless of status.
      db.rawQuery(
          "SELECT COUNT(*) as c, COALESCE(SUM(principal_amount),0) as s "
          "FROM pledges WHERE DATE(start_date)=?",
          [d]),
      // 1 — Closed loans on the given date (principal only, no interest).
      db.rawQuery(
          "SELECT COUNT(*) as c, COALESCE(SUM(principal_amount),0) as s "
          "FROM pledges WHERE status='closed' AND DATE(closure_date)=?",
          [d]),
      // 2 — Interest collected on the given date (from pledge closures).
      db.rawQuery(
          "SELECT COALESCE(SUM(total_interest_paid),0) as s FROM pledges "
          "WHERE status='closed' AND DATE(closure_date)=?",
          [d]),
      // 3 — Unique customers with open pledge started or closed on the given date.
      db.rawQuery(
          "SELECT COUNT(DISTINCT customer_id) as c FROM pledges "
          "WHERE ((status='open' AND DATE(start_date)=?) "
          "OR (status='closed' AND DATE(closure_date)=?)) "
          "AND customer_id IS NOT NULL",
          [d, d]),
    ]);

    return TodayActivity(
      newCount: (results[0].first['c'] as int?) ?? 0,
      newAmount: (results[0].first['s'] as num?)?.toDouble() ?? 0,
      closedCount: (results[1].first['c'] as int?) ?? 0,
      closedAmount: (results[1].first['s'] as num?)?.toDouble() ?? 0,
      interestCollected: (results[2].first['s'] as num?)?.toDouble() ?? 0,
      activeCustomers: (results[3].first['c'] as int?) ?? 0,
    );
  }

  /// Earliest date any pledge was created — used as the lower bound for
  /// activity date navigation. Uses created_at so backdated start_dates
  /// don't push the floor before the system was actually set up.
  Future<DateTime> getFirstPledgeDate() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
        "SELECT MIN(DATE(created_at)) as d FROM pledges "
        "WHERE created_at IS NOT NULL");
    final raw = rows.first['d'] as String?;
    if (raw == null) return DateTime.now();
    return DateTime.parse(raw);
  }

  // ── Activity Drill-Down ───────────────────────────────────────────────────────

  Future<List<ActivityPledge>> getNewPledgesForDate(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      "SELECT p.id, p.pledge_no, p.principal_amount, p.status, "
      "COALESCE(p.total_interest_paid,0) as tip, c.name "
      "FROM pledges p LEFT JOIN customers c ON c.id = p.customer_id "
      "WHERE DATE(p.start_date)=? "
      "ORDER BY p.pledge_no ASC",
      [date],
    );
    return rows
        .map((r) => ActivityPledge(
              id: r['id'] as int,
              pledgeNumber: r['pledge_no'] as String,
              principalAmount:
                  (r['principal_amount'] as num?)?.toDouble() ?? 0,
              interestPaid: (r['tip'] as num?)?.toDouble() ?? 0,
              status: r['status'] as String? ?? 'open',
              customerName: r['name'] as String?,
            ))
        .toList();
  }

  Future<List<ActivityPledge>> getClosedPledgesForDate(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      "SELECT p.id, p.pledge_no, p.principal_amount, "
      "COALESCE(p.total_interest_paid,0) as tip, c.name "
      "FROM pledges p LEFT JOIN customers c ON c.id = p.customer_id "
      "WHERE p.status='closed' AND DATE(p.closure_date)=? "
      "ORDER BY p.pledge_no ASC",
      [date],
    );
    return rows
        .map((r) => ActivityPledge(
              id: r['id'] as int,
              pledgeNumber: r['pledge_no'] as String,
              principalAmount:
                  (r['principal_amount'] as num?)?.toDouble() ?? 0,
              interestPaid: (r['tip'] as num?)?.toDouble() ?? 0,
              status: 'closed',
              customerName: r['name'] as String?,
            ))
        .toList();
  }

  Future<List<ActivityCustomer>> getCustomersForDate(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT c.id, c.name, c.phone "
      "FROM customers c INNER JOIN pledges p ON c.id = p.customer_id "
      "WHERE (p.status='open' AND DATE(p.start_date)=?) "
      "OR (p.status='closed' AND DATE(p.closure_date)=?) "
      "ORDER BY c.name ASC",
      [date, date],
    );
    return rows
        .map((r) => ActivityCustomer(
              id: r['id'] as int,
              name: r['name'] as String,
              phone: r['phone'] as String?,
            ))
        .toList();
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
      '0': '(julianday(\'now\') - julianday(p.start_date)) <= 180',
      '1':
          '(julianday(\'now\') - julianday(p.start_date)) > 180 AND (julianday(\'now\') - julianday(p.start_date)) <= 365',
      '2':
          '(julianday(\'now\') - julianday(p.start_date)) > 365 AND (julianday(\'now\') - julianday(p.start_date)) <= 730',
      '3': '(julianday(\'now\') - julianday(p.start_date)) > 730',
    };

    final condition = daysConditions[bucket] ?? daysConditions['0']!;
    final rows = await db.rawQuery(
      "SELECT p.*, c.name AS customer_name, "
      "CAST(julianday('now') - julianday(p.start_date) AS INTEGER) as days_old "
      "FROM pledges p LEFT JOIN customers c ON c.id = p.customer_id "
      "WHERE p.status='open' AND $condition "
      "ORDER BY p.start_date ASC",
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

  // ── Gold Account Balance ───────────────────────────────────────────────────

  /// Builds the full gold-account ledger (oldest first) from the opening
  /// balance and the pledges table. Money OUT = principal of new open pledges;
  /// Money IN = principal of closed pledges. Each day's opening is the
  /// previous day's closing. Always starts from the installation date
  /// (opening_gold_account_balance_date setting).
  Future<List<GoldAccountDay>> _goldAccountLedger() async {
    final db = await AppDatabase.instance.database;

    final opening = await _openingGoldAccountBalance();
    final installDateRaw = await AppSettingsRepository()
        .getString('opening_gold_account_balance_date');

    final rows = await db.rawQuery("""
      SELECT d, SUM(in_amt) AS in_amt, SUM(out_amt) AS out_amt FROM (
        SELECT DATE(closure_date) AS d,
               SUM(principal_amount) AS in_amt,
               0.0 AS out_amt
        FROM pledges
        WHERE status='closed' AND closure_date IS NOT NULL
        GROUP BY DATE(closure_date)
        UNION ALL
        SELECT DATE(start_date) AS d,
               0.0 AS in_amt,
               SUM(principal_amount) AS out_amt
        FROM pledges
        WHERE start_date IS NOT NULL
        GROUP BY DATE(start_date)
      )
      GROUP BY d
      ORDER BY d ASC
    """);

    // Build a date → {in, out} map from SQL results
    final byDate = <String, ({double inAmt, double outAmt})>{};
    for (final r in rows) {
      final d = r['d'] as String?;
      if (d == null) continue;
      byDate[d] = (
        inAmt: (r['in_amt'] as num?)?.toDouble() ?? 0,
        outAmt: (r['out_amt'] as num?)?.toDouble() ?? 0,
      );
    }

    // Anchor date: saved installation date → earliest pledge date → today
    final sortedKeys = byDate.keys.toList()..sort();
    final anchor = (installDateRaw != null && installDateRaw.trim().isNotEmpty)
        ? installDateRaw.trim()
        : sortedKeys.isNotEmpty
            ? sortedKeys.first
            : DateTime.now().toIso8601String().substring(0, 10);

    // Ensure anchor date is in the map (may have zero activity)
    byDate.putIfAbsent(anchor, () => (inAmt: 0, outAmt: 0));

    final allDates = byDate.keys.where((d) => d.compareTo(anchor) >= 0).toList()..sort();
    final days = <GoldAccountDay>[];
    double running = opening;
    for (final d in allDates) {
      final entry = byDate[d]!;
      final closing = running + entry.outAmt - entry.inAmt;
      days.add(GoldAccountDay(
        date: d,
        opening: running,
        moneyIn: entry.inAmt,
        moneyOut: entry.outAmt,
        closing: closing,
      ));
      running = closing;
    }
    return days;
  }

  Future<double> _openingGoldAccountBalance() async {
    final raw = await AppSettingsRepository()
        .getString('opening_gold_account_balance');
    return double.tryParse((raw ?? '').replaceAll(',', '')) ?? 0;
  }

  /// Dashboard card: cumulative running balance from the ledger.
  /// yesterdayBalance = prior day's closing, used for trend arrow.
  Future<GoldAccountSummary> getGoldAccountSummary() async {
    final days = await _goldAccountLedger();
    if (days.isEmpty) {
      final opening = await _openingGoldAccountBalance();
      return GoldAccountSummary(currentBalance: opening, yesterdayBalance: opening);
    }
    final current = days.last.closing;
    final yesterday =
        days.length > 1 ? days[days.length - 2].closing : days.last.opening;
    return GoldAccountSummary(currentBalance: current, yesterdayBalance: yesterday);
  }

  /// Full ledger newest-first for the drill-down screen.
  Future<List<GoldAccountDay>> getGoldAccountDays() async {
    final days = await _goldAccountLedger();
    return days.reversed.toList();
  }

  // ── Business Health ───────────────────────────────────────────────────────────

  Future<BusinessHealth> getBusinessHealth() async {
    final db = await AppDatabase.instance.database;

    final results = await Future.wait([
      db.rawQuery(
          "SELECT p.id, p.pledge_no, p.principal_amount, p.start_date, "
          "c.name AS customer_name, "
          "CAST(julianday('now') - julianday(p.start_date) AS INTEGER) as days_old "
          "FROM pledges p LEFT JOIN customers c ON c.id = p.customer_id "
          "WHERE p.status='open' "
          "ORDER BY p.principal_amount DESC LIMIT 5"),
      db.rawQuery(
          "SELECT p.id, p.pledge_no, p.principal_amount, p.start_date, "
          "c.name AS customer_name, "
          "CAST(julianday('now') - julianday(p.start_date) AS INTEGER) as days_old "
          "FROM pledges p LEFT JOIN customers c ON c.id = p.customer_id "
          "WHERE p.status='open' "
          "ORDER BY p.start_date ASC LIMIT 5"),
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
      // 0 — Pledges opened in period (any status, by start_date)
      db.rawQuery(
          "SELECT COUNT(*) as c, COALESCE(SUM(principal_amount),0) as s "
          "FROM pledges WHERE DATE(start_date) BETWEEN ? AND ?",
          [fromDate, toDate]),
      // 1 — Pledges redeemed in period (status='closed', by closure_date)
      db.rawQuery(
          "SELECT COUNT(*) as c, COALESCE(SUM(principal_amount),0) as s "
          "FROM pledges WHERE status='closed' AND DATE(closure_date) BETWEEN ? AND ?",
          [fromDate, toDate]),
      // 2 — Max single-day disbursement in period
      db.rawQuery(
          "SELECT DATE(start_date) as d, COALESCE(SUM(principal_amount),0) as s "
          "FROM pledges WHERE DATE(start_date) BETWEEN ? AND ? "
          "GROUP BY DATE(start_date) ORDER BY s DESC LIMIT 1",
          [fromDate, toDate]),
      // 3 — Gold received (items of pledges created in period)
      db.rawQuery(
          "SELECT COALESCE(SUM(pi.net_weight),0) as g "
          "FROM pledge_items pi JOIN pledges p ON pi.pledge_id=p.id "
          "WHERE DATE(p.start_date) BETWEEN ? AND ?",
          [fromDate, toDate]),
      // 4 — Gold released (items of pledges closed in period)
      db.rawQuery(
          "SELECT COALESCE(SUM(pi.net_weight),0) as g "
          "FROM pledge_items pi JOIN pledges p ON pi.pledge_id=p.id "
          "WHERE p.status='closed' AND DATE(p.closed_at) BETWEEN ? AND ?",
          [fromDate, toDate]),
      // 5 — Closing gold stock from daily_stock (last record on or before period end)
      db.rawQuery(
          "SELECT stock_date, closing_weight FROM daily_stock "
          "WHERE stock_date BETWEEN ? AND ? ORDER BY stock_date DESC LIMIT 1",
          [fromDate, toDate]),
      // 6 — Interest earned in period
      db.rawQuery(
          "SELECT COALESCE(SUM(total_interest_paid),0) as s FROM pledges "
          "WHERE status='closed' AND DATE(closed_at) BETWEEN ? AND ?",
          [fromDate, toDate]),
      // 7 — Expenses in period
      db.rawQuery(
          "SELECT COALESCE(SUM(amount),0) as s FROM payments "
          "WHERE payment_type='EXPENSE' AND DATE(payment_date) BETWEEN ? AND ?",
          [fromDate, toDate]),
      // 8 — Expense by category (sub_category)
      db.rawQuery(
          "SELECT COALESCE(sub_category,'Uncategorised') AS name, "
          "COALESCE(SUM(amount),0) as s FROM payments "
          "WHERE payment_type='EXPENSE' AND DATE(payment_date) BETWEEN ? AND ? "
          "GROUP BY sub_category ORDER BY s DESC",
          [fromDate, toDate]),
    ]);

    final maxRow = results[2].isNotEmpty ? results[2].first : null;
    final maxDayDate = maxRow?['d'] as String? ?? '';
    final maxDayAmount = (maxRow?['s'] as num?)?.toDouble() ?? 0;

    return ReportData(
      pledgeCount: (results[0].first['c'] as int?) ?? 0,
      totalDisbursedPledges: (results[0].first['s'] as num?)?.toDouble() ?? 0,
      redeemedCount: (results[1].first['c'] as int?) ?? 0,
      totalAmountRedeemed: (results[1].first['s'] as num?)?.toDouble() ?? 0,
      maxDayDisbursedAmount: maxDayAmount,
      maxDayDisbursedDate: maxDayDate,
      goldReceived: (results[3].first['g'] as num?)?.toDouble() ?? 0,
      goldReleased: (results[4].first['g'] as num?)?.toDouble() ?? 0,
      goldStock: results[5].isEmpty
          ? null
          : (results[5].first['closing_weight'] as num?)?.toDouble(),
      goldStockDate: results[5].isEmpty
          ? ''
          : (results[5].first['stock_date'] as String? ?? ''),
      totalInterest: (results[6].first['s'] as num?)?.toDouble() ?? 0,
      totalExpenses: (results[7].first['s'] as num?)?.toDouble() ?? 0,
      expenseBreakdown:
          results[8].map((r) => Map<String, dynamic>.from(r)).toList(),
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
    await DailyBalanceRepository.instance.unlockDay(date);
    await DayReconciliationRepository.instance
        .unlockReconciliation(date: date, reason: reason);
    await AuditLogRepository.instance.log(
      actionCategory: AuditCategory.dayManagement,
      action: 'DAY_UNLOCKED',
      entityType: 'daily_balance',
      entityId: date,
      oldValueJson: '{"is_locked":1}',
      newValueJson: '{"is_locked":0}',
      reason: reason,
    );
  }
}
