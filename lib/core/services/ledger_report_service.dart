import '../database/app_database.dart';

/// One journal line for the General Ledger display, joined with its entry
/// header and (when pledge-tagged) the pledge number.
class GeneralLedgerLine {
  const GeneralLedgerLine({
    required this.entryId,
    required this.entryDate,
    required this.narration,
    this.pledgeNo,
    required this.debit,
    required this.credit,
    required this.isVirtual,
    required this.isReversed,
  });

  final int entryId; // journal_entries.id — for the entry-detail tap-through
  final String entryDate; // ISO YYYY-MM-DD
  final String narration;
  final String? pledgeNo;
  final double debit;
  final double credit;
  final bool isVirtual;
  final bool isReversed;
}

/// A full `journal_entries` header for the Entry Detail view.
class JournalEntryHeader {
  const JournalEntryHeader({
    required this.id,
    required this.entryDate,
    required this.entryType,
    required this.sourceType,
    required this.narration,
    required this.isReversed,
    this.reversedByEntryId,
    required this.createdAt,
  });

  final int id;
  final String entryDate;
  final String entryType; // 'AUTO' / 'MANUAL'
  final String sourceType;
  final String narration;
  final bool isReversed;
  final int? reversedByEntryId;
  final String createdAt;
}

/// One line of an entry in the Entry Detail view — across ALL accounts the
/// entry touched, joined with account and pledge info.
class JournalEntryDetailLine {
  const JournalEntryDetailLine({
    required this.accountName,
    required this.accountCode,
    this.pledgeNo,
    required this.debit,
    required this.credit,
    required this.isVirtual,
  });

  final String accountName;
  final String accountCode;
  final String? pledgeNo;
  final double debit;
  final double credit;
  final bool isVirtual;
}

/// One Trial Balance row: an active account and its net balance
/// (debits − credits; positive = net debit) as of the report date.
class TrialBalanceRow {
  const TrialBalanceRow({
    required this.accountId,
    required this.code,
    required this.name,
    required this.accountType,
    required this.net,
  });

  final int accountId;
  final String code;
  final String name;
  final String accountType;
  final double net;
}

/// One aggregated row in the day-grouped General Ledger view used for
/// Gold Loan Receivable (1101) and Interest Collected Account (4001).
/// Each group represents all Dr lines OR all Cr lines on a single date.
class DayGroupedLine {
  const DayGroupedLine({
    required this.date,
    required this.isCredit,
    required this.totalDebit,
    required this.totalCredit,
    required this.priorBalance,
    required this.runningBalance,
    required this.lines,
  });

  final String date;
  final bool isCredit;        // true = Cr group, false = Dr group
  final double totalDebit;
  final double totalCredit;
  final double priorBalance;   // balance BEFORE this group (for drill-down)
  final double runningBalance; // balance AFTER this group (shown on grouped row)
  final List<GeneralLedgerLine> lines;

  String get narration => isCredit ? 'By Cash' : 'To Cash';
  int get count => lines.length;
}

/// Shared read-only queries for the ledger reports (General Ledger, Trial
/// Balance; P&L and Balance Sheet reuse this later).
///
/// Balance sums include every line — reversed entries and their reversals
/// deliberately net to zero when summed together, so filtering
/// `is_reversed = 1` rows out would CORRUPT balances, not clean them.
/// Virtual lines also always net to zero per entry, so balances are correct
/// whether or not the UI displays them.
class LedgerReportService {
  LedgerReportService._();
  static final LedgerReportService instance = LedgerReportService._();

  /// Account codes whose General Ledger view is displayed as daily Dr/Cr groups.
  static const groupedViewCodes = {'1101', '4001'};

  /// Groups [lines] by date then by direction (Dr/Cr). Within each date, Dr
  /// groups appear before Cr groups. Running balance is computed from [openingBalance].
  static List<DayGroupedLine> groupByDay(
      List<GeneralLedgerLine> lines, double openingBalance) {
    final dateOrder = <String>[];
    final byDateDir = <String, Map<bool, List<GeneralLedgerLine>>>{};

    for (final line in lines) {
      final isCredit = line.credit > 0.005;
      if (!byDateDir.containsKey(line.entryDate)) {
        dateOrder.add(line.entryDate);
        byDateDir[line.entryDate] = {};
      }
      byDateDir[line.entryDate]!.putIfAbsent(isCredit, () => []).add(line);
    }

    var balance = openingBalance;
    final result = <DayGroupedLine>[];
    for (final date in dateOrder) {
      for (final isCredit in [false, true]) {
        final dayLines = byDateDir[date]![isCredit];
        if (dayLines == null || dayLines.isEmpty) continue;
        final totalDr = dayLines.fold(0.0, (s, l) => s + l.debit);
        final totalCr = dayLines.fold(0.0, (s, l) => s + l.credit);
        final prior = balance;
        balance += totalDr - totalCr;
        result.add(DayGroupedLine(
          date: date,
          isCredit: isCredit,
          totalDebit: totalDr,
          totalCredit: totalCr,
          priorBalance: prior,
          runningBalance: balance,
          lines: dayLines,
        ));
      }
    }
    return result;
  }

  /// Net balance (debits − credits) of [accountId] across all journal lines
  /// with `entry_date <= asOfDate`. Positive = net debit.
  Future<double> getAccountBalance(int accountId, String asOfDate) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0) AS net
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      WHERE jl.account_id = ? AND je.entry_date <= ?
    ''', [accountId, asOfDate]);
    return (rows.first['net'] as num?)?.toDouble() ?? 0.0;
  }

  /// Lines for [accountId] in [fromDate, toDate] (inclusive), oldest first.
  /// [includeVirtual] only affects which lines are returned for display —
  /// virtual pairs net to zero per entry, so a running balance computed over
  /// the filtered list still closes correctly.
  Future<List<GeneralLedgerLine>> getAccountLines(
    int accountId,
    String fromDate,
    String toDate, {
    bool includeVirtual = false,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT je.id AS entry_id, je.entry_date,
             COALESCE(jl.narration, je.narration) AS narration,
             je.is_reversed,
             jl.debit, jl.credit, jl.is_virtual, p.pledge_no
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      LEFT JOIN pledges p ON p.id = jl.pledge_id
      WHERE jl.account_id = ?
        AND je.entry_date >= ? AND je.entry_date <= ?
        ${includeVirtual ? '' : 'AND jl.is_virtual = 0'}
      ORDER BY je.entry_date ASC, jl.journal_entry_id ASC, jl.id ASC
    ''', [accountId, fromDate, toDate]);
    return [
      for (final r in rows)
        GeneralLedgerLine(
          entryId: r['entry_id'] as int,
          entryDate: r['entry_date'] as String? ?? '',
          narration: r['narration'] as String? ?? '',
          pledgeNo: r['pledge_no'] as String?,
          debit: (r['debit'] as num?)?.toDouble() ?? 0.0,
          credit: (r['credit'] as num?)?.toDouble() ?? 0.0,
          isVirtual: (r['is_virtual'] as int? ?? 0) == 1,
          isReversed: (r['is_reversed'] as int? ?? 0) == 1,
        ),
    ];
  }

  /// The full header of one journal entry, or null if it does not exist.
  Future<JournalEntryHeader?> getEntryHeader(int entryId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('journal_entries',
        where: 'id = ?', whereArgs: [entryId], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return JournalEntryHeader(
      id: r['id'] as int,
      entryDate: r['entry_date'] as String? ?? '',
      entryType: r['entry_type'] as String? ?? '',
      sourceType: r['source_type'] as String? ?? '',
      narration: r['narration'] as String? ?? '',
      isReversed: (r['is_reversed'] as int? ?? 0) == 1,
      reversedByEntryId: r['reversed_by_entry_id'] as int?,
      createdAt: r['created_at'] as String? ?? '',
    );
  }

  /// Every line of one journal entry — across all accounts it touched.
  Future<List<JournalEntryDetailLine>> getEntryLines(int entryId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT jl.debit, jl.credit, jl.is_virtual,
             c.name AS account_name, c.code AS account_code, p.pledge_no
      FROM journal_lines jl
      JOIN chart_of_accounts c ON c.id = jl.account_id
      LEFT JOIN pledges p ON p.id = jl.pledge_id
      WHERE jl.journal_entry_id = ?
      ORDER BY jl.id ASC
    ''', [entryId]);
    return [
      for (final r in rows)
        JournalEntryDetailLine(
          accountName: r['account_name'] as String? ?? '',
          accountCode: r['account_code'] as String? ?? '',
          pledgeNo: r['pledge_no'] as String?,
          debit: (r['debit'] as num?)?.toDouble() ?? 0.0,
          credit: (r['credit'] as num?)?.toDouble() ?? 0.0,
          isVirtual: (r['is_virtual'] as int? ?? 0) == 1,
        ),
    ];
  }

  /// One row per active account of [accountType] with its net movement
  /// (debits − credits) within [fromDate, toDate] inclusive — the P&L's
  /// period figures. Accounts with no activity in the period return net 0.
  Future<List<TrialBalanceRow>> getTypeMovements(
    String accountType,
    String fromDate,
    String toDate,
  ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.id, c.code, c.name, c.account_type,
             COALESCE(t.net, 0) AS net
      FROM chart_of_accounts c
      LEFT JOIN (
        SELECT jl.account_id,
               SUM(jl.debit) - SUM(jl.credit) AS net
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        WHERE je.entry_date >= ? AND je.entry_date <= ?
        GROUP BY jl.account_id
      ) t ON t.account_id = c.id
      WHERE c.is_active = 1 AND c.account_type = ?
      ORDER BY CAST(c.code AS INTEGER) ASC
    ''', [fromDate, toDate, accountType]);
    return [
      for (final r in rows)
        TrialBalanceRow(
          accountId: r['id'] as int,
          code: r['code'] as String? ?? '',
          name: r['name'] as String? ?? '',
          accountType: r['account_type'] as String? ?? '',
          net: (r['net'] as num?)?.toDouble() ?? 0.0,
        ),
    ];
  }

  /// Net earnings (total income − total expenses) for [fromDate, toDate]:
  /// summed over every income and expense account line in the period. Since
  /// income = credits − debits and expenses = debits − credits, this reduces
  /// to SUM(credit) − SUM(debit) across both types. Used by the P&L totals
  /// and by the Balance Sheet's computed (never posted) "Current Year
  /// Earnings" line.
  Future<double> getEarnings(String fromDate, String toDate) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(jl.credit), 0) - COALESCE(SUM(jl.debit), 0) AS net
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      JOIN chart_of_accounts c ON c.id = jl.account_id
      WHERE c.account_type IN ('income', 'expense')
        AND je.entry_date >= ? AND je.entry_date <= ?
    ''', [fromDate, toDate]);
    return (rows.first['net'] as num?)?.toDouble() ?? 0.0;
  }

  /// The year-end closure row for [financialYear] (e.g. '2026-27'), or null if
  /// the year has not been closed. Used by the Year-End Closing Wizard to block
  /// re-closing a year and to show its existing closure summary.
  Future<Map<String, Object?>?> getYearEndClosure(String financialYear) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('ledger_year_end_closures',
        where: 'financial_year = ?', whereArgs: [financialYear], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// One row per active account with its net balance as of [asOfDate],
  /// ordered by code. Accounts with no activity return net 0.
  Future<List<TrialBalanceRow>> getTrialBalance(String asOfDate) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.id, c.code, c.name, c.account_type,
             COALESCE(t.net, 0) AS net
      FROM chart_of_accounts c
      LEFT JOIN (
        SELECT jl.account_id,
               SUM(jl.debit) - SUM(jl.credit) AS net
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        WHERE je.entry_date <= ?
        GROUP BY jl.account_id
      ) t ON t.account_id = c.id
      WHERE c.is_active = 1
      ORDER BY CAST(c.code AS INTEGER) ASC
    ''', [asOfDate]);
    return [
      for (final r in rows)
        TrialBalanceRow(
          accountId: r['id'] as int,
          code: r['code'] as String? ?? '',
          name: r['name'] as String? ?? '',
          accountType: r['account_type'] as String? ?? '',
          net: (r['net'] as num?)?.toDouble() ?? 0.0,
        ),
    ];
  }
}
