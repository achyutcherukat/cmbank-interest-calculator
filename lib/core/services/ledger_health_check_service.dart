import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'ledger_report_service.dart';

/// One Cash/Bank account whose ledger balance disagrees with the independently
/// maintained Cash Book figure as of the most recent locked business date.
class CashBankMismatch {
  const CashBankMismatch({
    required this.accountName,
    required this.ledgerBalance,
    required this.cashBookBalance,
    required this.asOfDate,
  });

  final String accountName;
  final double ledgerBalance;
  final double cashBookBalance;
  final String asOfDate; // ISO YYYY-MM-DD

  /// Ledger minus Cash Book (signed).
  double get difference => ledgerBalance - cashBookBalance;
}

/// One transaction that should have a journal entry on a locked date but does
/// not — a posting gap Check B's anti-join found.
class MissingPosting {
  const MissingPosting({
    required this.sourceType,
    required this.sourceId,
    required this.date,
    required this.typeLabel,
    required this.amount,
    this.pledgeId,
    this.pledgeNo,
    this.pledgeClosed = false,
  });

  final String sourceType; // 'payment' | 'pledge'
  final int sourceId;
  final String date; // ISO YYYY-MM-DD (payment_date / closure_date)
  final String typeLabel; // human-ish type/subtype
  final double amount;

  /// The pledge this record can navigate to (null for non-pledge payments
  /// such as EXPENSE / CAPITAL / cash adjustments).
  final int? pledgeId;
  final String? pledgeNo;

  /// Whether [pledgeId] is a closed pledge (→ ClosedPledgeDetailScreen) rather
  /// than an open one (→ PledgeDetailScreen).
  final bool pledgeClosed;
}

/// Combined outcome of both background checks run when Trial Balance opens.
class HealthCheckResult {
  const HealthCheckResult({
    required this.cashBankMismatches,
    required this.missingPostings,
    required this.lockedDate,
  });

  final List<CashBankMismatch> cashBankMismatches;
  final List<MissingPosting> missingPostings;

  /// The most recent locked business date the checks ran against, or null if
  /// no locked day exists yet (Check A skipped).
  final String? lockedDate;

  bool get hasIssues =>
      cashBankMismatches.isNotEmpty || missingPostings.isNotEmpty;

  /// Distinct locked dates that have a missing posting — the input to the
  /// idempotent "Re-run Posting for Affected Dates" remedy.
  List<String> get affectedDates {
    final set = <String>{for (final m in missingPostings) m.date};
    final list = set.toList()..sort();
    return list;
  }
}

/// Two silent, read-only integrity checks that run every time the Trial
/// Balance screen opens (Prompt 10).
///
/// Trial Balance only proves internal consistency of what is posted (Dr = Cr);
/// it cannot see a transaction that was never posted at all. These checks
/// cover that blind spot:
///  * Check A — reconciles the ledger's Cash/Bank balances against the Cash
///    Book as of the latest locked day.
///  * Check B — anti-joins locked-date payments/renewals against
///    `journal_entries` to find records that should be posted but are not.
///
/// Nothing is written; the only remedy (re-running [LedgerPostingService.
/// postForDate]) is invoked explicitly from the detail screen.
class LedgerHealthCheckService {
  LedgerHealthCheckService._();
  static final LedgerHealthCheckService instance =
      LedgerHealthCheckService._();

  /// Half a paisa either way is float noise, not a real discrepancy — same
  /// caution as the ledger amount comparisons (Prompt 6a). ₹0.01 tolerance.
  static const double _tolerance = 0.01;

  Future<HealthCheckResult> run() async {
    final db = await AppDatabase.instance.database;
    final lockedDate = await _latestLockedDate(db);
    final cashBank = lockedDate == null
        ? const <CashBankMismatch>[]
        : await _checkCashBank(db, lockedDate);
    final missing = await _checkPostingCompleteness(db);
    return HealthCheckResult(
      cashBankMismatches: cashBank,
      missingPostings: missing,
      lockedDate: lockedDate,
    );
  }

  // ─── Check A — Cash/Bank reconciliation ─────────────────────────────────────

  Future<String?> _latestLockedDate(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
        'SELECT MAX(business_date) AS d FROM daily_balance WHERE is_locked = 1');
    return rows.first['d'] as String?;
  }

  Future<List<CashBankMismatch>> _checkCashBank(
      DatabaseExecutor db, String date) async {
    final result = <CashBankMismatch>[];
    final service = LedgerReportService.instance;

    final dayRows = await db.query('daily_balance',
        where: 'business_date = ?', whereArgs: [date], limit: 1);
    if (dayRows.isEmpty) return result;
    final dayRow = dayRows.first;
    final dailyBalanceId = dayRow['id'] as int;

    // Cash in Hand (system account, code 1001) vs closing_cash.
    final cashRows = await db.query('chart_of_accounts',
        where: 'code = ?', whereArgs: ['1001'], limit: 1);
    if (cashRows.isNotEmpty) {
      final coaId = cashRows.first['id'] as int;
      final ledger = await service.getAccountBalance(coaId, date);
      final cashBook = (dayRow['closing_cash'] as num?)?.toDouble() ?? 0.0;
      if ((ledger - cashBook).abs() > _tolerance) {
        result.add(CashBankMismatch(
          accountName: cashRows.first['name'] as String? ?? 'Cash in Hand',
          ledgerBalance: ledger,
          cashBookBalance: cashBook,
          asOfDate: date,
        ));
      }
    }

    // Each active bank account with a linked ledger account.
    final banks = await db.rawQuery('''
      SELECT ba.id AS bank_id, ba.name AS bank_name, coa.id AS coa_id
      FROM bank_accounts ba
      JOIN chart_of_accounts coa
        ON coa.linked_table = 'bank_accounts' AND coa.linked_id = ba.id
      WHERE ba.is_active = 1
      ORDER BY ba.id ASC
    ''');
    for (final b in banks) {
      final coaId = b['coa_id'] as int;
      final bankId = b['bank_id'] as int;
      final ledger = await service.getAccountBalance(coaId, date);
      final dab = await db.query('daily_account_balance',
          columns: ['closing_balance'],
          where: 'daily_balance_id = ? AND bank_account_id = ?',
          whereArgs: [dailyBalanceId, bankId],
          limit: 1);
      final cashBook = dab.isEmpty
          ? 0.0
          : (dab.first['closing_balance'] as num?)?.toDouble() ?? 0.0;
      if ((ledger - cashBook).abs() > _tolerance) {
        result.add(CashBankMismatch(
          accountName: b['bank_name'] as String? ?? 'Bank',
          ledgerBalance: ledger,
          cashBookBalance: cashBook,
          asOfDate: date,
        ));
      }
    }
    return result;
  }

  // ─── Check B — posting completeness (anti-join) ─────────────────────────────

  Future<List<MissingPosting>> _checkPostingCompleteness(
      DatabaseExecutor db) async {
    final missing = <MissingPosting>[];

    // 1. Payments on a locked date with no non-reversed 'payment' entry.
    //    Retired cash top-ups (ADJUSTMENT / ADD_CASH|ADD_UPI|ADD_BANK) never
    //    post, so they are excluded rather than flagged.
    //    Two-row transfer adjustments (CASH_TO_UPI, UPI_TO_CASH, CASH_TO_BANK,
    //    BANK_TO_CASH, BANK_TO_BANK) post as ONE journal entry per pair, keyed
    //    to the OUT row's id (see _postAdjustment in ledger_posting_service.dart)
    //    — so the row that isn't the OUT row never has an entry under its own
    //    id even when correctly posted. Such a row is only flagged if NEITHER
    //    it nor its inferred transfer partner (same date/sub_category/amount,
    //    opposite direction — same matching approach as getAdjustmentPartner
    //    in payments_repository.dart) has a posted entry.
    final payments = await db.rawQuery('''
      SELECT p.id, p.payment_date, p.payment_type, p.sub_category, p.amount,
             p.pledge_id, pl.pledge_no, pl.status AS pledge_status
      FROM payments p
      JOIN daily_balance d
        ON d.business_date = DATE(p.payment_date) AND d.is_locked = 1
      LEFT JOIN pledges pl ON pl.id = p.pledge_id
      WHERE NOT (p.payment_type = 'ADJUSTMENT'
                 AND p.sub_category IN ('ADD_CASH', 'ADD_UPI', 'ADD_BANK'))
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries je
          WHERE je.source_type = 'payment' AND je.source_id = p.id
            AND je.is_reversed = 0
        )
        AND NOT (
          p.payment_type = 'ADJUSTMENT'
          AND p.sub_category IN ('CASH_TO_UPI', 'UPI_TO_CASH', 'CASH_TO_BANK',
                                  'BANK_TO_CASH', 'BANK_TO_BANK')
          AND EXISTS (
            SELECT 1 FROM payments partner
            JOIN journal_entries pje
              ON pje.source_type = 'payment' AND pje.source_id = partner.id
              AND pje.is_reversed = 0
            WHERE partner.id != p.id
              AND partner.payment_type = 'ADJUSTMENT'
              AND partner.sub_category = p.sub_category
              AND DATE(partner.payment_date) = DATE(p.payment_date)
              AND ABS(partner.amount - p.amount) < 0.01
              AND partner.direction != p.direction
          )
        )
      ORDER BY p.payment_date ASC, p.id ASC
    ''');
    for (final r in payments) {
      missing.add(MissingPosting(
        sourceType: 'payment',
        sourceId: r['id'] as int,
        date: _isoDate(r['payment_date']),
        typeLabel: _paymentLabel(
            r['payment_type'] as String?, r['sub_category'] as String?),
        amount: (r['amount'] as num?)?.toDouble() ?? 0.0,
        pledgeId: r['pledge_id'] as int?,
        pledgeNo: r['pledge_no'] as String?,
        pledgeClosed: (r['pledge_status'] as String?) == 'closed',
      ));
    }

    // 2. Interest-capitalised closures on a locked date with no entry.
    //    A closure posts under source 'pledge' (no cash) OR 'payment' (when a
    //    LOAN_INCREASE disbursement supplies the cash leg), so the anti-join
    //    must clear on either — checking only 'pledge' would false-flag every
    //    loan-increase capitalisation that was correctly posted via its
    //    payment. The payment side is any payment on this pledge or its
    //    successor (loan-increase rows carry the new pledge's id).
    final closures = await db.rawQuery('''
      SELECT p.id, p.closure_date, p.renew_type, p.renew_subtype, p.pledge_no,
             p.total_interest_paid
      FROM pledges p
      JOIN daily_balance d
        ON d.business_date = DATE(p.closure_date) AND d.is_locked = 1
      WHERE p.renew_subtype = 'INTEREST_CAPITALISED'
        AND p.renew_type IN ('RENEWED', 'LOAN_INCREASE')
        AND NOT EXISTS (
          SELECT 1 FROM journal_entries je
          WHERE je.is_reversed = 0
            AND (
              (je.source_type = 'pledge' AND je.source_id = p.id)
              OR (je.source_type = 'payment' AND je.source_id IN (
                    SELECT pay.id FROM payments pay
                    WHERE pay.pledge_id = p.id
                       OR pay.pledge_id IN (
                            SELECT s.id FROM pledges s
                            WHERE s.renewal_parent_id = p.id)
                  ))
            )
        )
      ORDER BY p.closure_date ASC, p.id ASC
    ''');
    for (final r in closures) {
      missing.add(MissingPosting(
        sourceType: 'pledge',
        sourceId: r['id'] as int,
        date: _isoDate(r['closure_date']),
        typeLabel: _renewLabel(
            r['renew_type'] as String?, r['renew_subtype'] as String?),
        amount: (r['total_interest_paid'] as num?)?.toDouble() ?? 0.0,
        pledgeId: r['id'] as int,
        pledgeNo: r['pledge_no'] as String?,
        pledgeClosed: true, // a renewed/loan-increased pledge is always closed
      ));
    }

    return missing;
  }

  // ─── Formatting helpers ─────────────────────────────────────────────────────

  static String _isoDate(Object? raw) =>
      (raw as String? ?? '').split('T').first.split(' ').first;

  static String _paymentLabel(String? type, String? sub) {
    final t = type ?? '';
    return (sub == null || sub.isEmpty) ? t : '$t · $sub';
  }

  static String _renewLabel(String? renewType, String? sub) {
    final t = renewType ?? '';
    return (sub == null || sub.isEmpty) ? t : '$t · $sub';
  }
}
