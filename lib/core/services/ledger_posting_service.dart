import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../features/admin/data/audit_log_repository.dart';
import '../database/app_database.dart';

/// Thrown when lock-time journal posting cannot complete. The Day End & Close
/// transaction rolls back on this, so the day stays unlocked and the user can
/// fix the underlying data and lock again.
class LedgerPostingException implements Exception {
  LedgerPostingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One line of the opening-balance entry, as collected by the Opening
/// Balance Wizard. Exactly one of [debit]/[credit] is non-zero per line.
class OpeningBalanceLine {
  const OpeningBalanceLine({
    required this.accountId,
    this.debit = 0,
    this.credit = 0,
  });

  final int accountId;
  final double debit;
  final double credit;
}

/// One line of a manual journal entry, as collected by the Manual Journal
/// Entry screen. Exactly one of [debit]/[credit] is non-zero per line.
class ManualJournalLine {
  const ManualJournalLine({
    required this.accountId,
    this.debit = 0,
    this.credit = 0,
    this.pledgeId,
  });

  final int accountId;
  final double debit;
  final double credit;
  final int? pledgeId;
}

/// One line of the year-end closing entry: an Income/Expense account being
/// zeroed, or a Partner Capital account receiving (profit) / absorbing (loss)
/// its CA-provided share. [accountName] is carried for the preview and audit
/// trail only.
class YearEndClosingLine {
  const YearEndClosingLine({
    required this.accountId,
    required this.accountName,
    this.debit = 0,
    this.credit = 0,
  });

  final int accountId;
  final String accountName;
  final double debit;
  final double credit;
}

/// One journal line being assembled for an entry (pre-insert).
class _Line {
  const _Line(
    this.accountId, {
    this.pledgeId,
    this.debit = 0,
    this.credit = 0,
    this.isVirtual = false,
    this.narration,
  });

  final int accountId;
  final int? pledgeId;
  final double debit;
  final double credit;
  final bool isVirtual;
  final String? narration;
}

/// Resolved chart_of_accounts ids needed by the posting rules.
class _Accounts {
  _Accounts({
    required this.cash,
    required this.goldLoanReceivable,
    required this.interestCollected,
    required this.bankByLinkedId,
    required this.expenseByLinkedId,
    required this.nameById,
  });

  final int cash;
  final int goldLoanReceivable;
  final int interestCollected;
  final Map<int, int> bankByLinkedId; // bank_accounts.id → chart id
  final Map<int, int> expenseByLinkedId; // expense_categories.id → chart id
  final Map<int, String> nameById;

  int bankAccount(int bankAccountId) {
    final id = bankByLinkedId[bankAccountId];
    if (id == null) {
      throw LedgerPostingException(
          'Bank account #$bankAccountId has no linked ledger account. '
          'Re-save it in Manage Bank Accounts, then close the day again.');
    }
    return id;
  }
}

/// Lock-time auto-posting engine (double-entry ledger, Prompt 2).
///
/// Journal entries are generated once per day, at Day End & Close — not in
/// real time as payments happen — so same-day corrections settle before the
/// ledger reads the final state. [postForDate] is idempotent: events whose
/// non-reversed journal entry already exists are skipped, so re-running for
/// a date never duplicates entries. Unlock-edit-relock is handled surgically
/// by a staleness pass that runs first: only entries whose source record was
/// edited (payments/pledges `updated_at` newer than the entry) or deleted
/// are auto-reversed and then reposted by the normal loop — every untouched
/// entry stays exactly as it was.
class LedgerPostingService {
  LedgerPostingService._();
  static final LedgerPostingService instance = LedgerPostingService._();

  static const _tolerance = 0.01;

  /// Posts all journal entries for [date] (a `YYYY-MM-DD` business date).
  /// Runs inside [txn] when provided — the Day End & Close lock transaction —
  /// otherwise opens its own transaction. Throws [LedgerPostingException] on
  /// any unmapped account or unbalanced entry; nothing is committed then.
  /// Returns the number of journal entries created.
  Future<int> postForDate(String date, {int? createdBy, DatabaseExecutor? txn}) async {
    if (txn != null) return _postForDate(txn, date, createdBy);
    final db = await AppDatabase.instance.database;
    return db.transaction((t) => _postForDate(t, date, createdBy));
  }

  /// Posts the one-time opening-balance entry (Opening Balance Wizard):
  /// one MANUAL journal entry dated `settings.ledger_start_date`, one line
  /// per non-zero field, `settings.ledger_opening_posted` flipped to true and
  /// the audit trail written — all in one transaction, rolled back entirely
  /// on any failure. Throws [LedgerPostingException] if already posted, if
  /// the lines do not balance, or if every line is zero.
  Future<void> postOpeningBalance({
    required List<OpeningBalanceLine> lines,
    required String auditJson,
    int? createdBy,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final settingsRows = await txn.query('settings',
          where: "key IN ('ledger_start_date', 'ledger_opening_posted')");
      final settings = {
        for (final r in settingsRows)
          r['key'] as String: r['value'] as String? ?? '',
      };
      final alreadyFlagged =
          settings['ledger_opening_posted']?.toLowerCase() == 'true';
      final existing = await txn.query('journal_entries',
          where: "source_type = 'opening_balance'", limit: 1);
      if (alreadyFlagged || existing.isNotEmpty) {
        throw LedgerPostingException(
            'The opening balance has already been posted.');
      }
      final date = settings['ledger_start_date'] ?? '';
      if (date.isEmpty) {
        throw LedgerPostingException(
            'The ledger_start_date setting is missing.');
      }

      final userId = createdBy ?? await _fallbackUserId(txn);
      final now = DateTime.now().toIso8601String();
      final created = await _insertEntry(
        txn,
        date,
        now,
        userId,
        entryType: 'MANUAL',
        sourceType: 'opening_balance',
        sourceId: null,
        narration: 'Opening Balance as of ${_formatDate(date)}',
        lines: [
          for (final l in lines)
            _Line(l.accountId, debit: l.debit, credit: l.credit),
        ],
      );
      if (created == 0) {
        throw LedgerPostingException(
            'Nothing to post — every field is zero.');
      }

      await txn.insert(
        'settings',
        {
          'key': 'ledger_opening_posted',
          'value': 'true',
          'value_type': 'bool',
          'updated_by': userId,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await AuditLogRepository.instance.log(
        actionCategory: AuditCategory.admin,
        action: 'LEDGER_OPENING_BALANCE_POSTED',
        entityType: 'journal_entries',
        entityId: date,
        newValueJson: auditJson,
        createdBy: userId,
        txn: txn,
      );
    });
  }

  /// Posts a general-purpose manual journal entry (Manual Journal Entry
  /// screen): one MANUAL/'manual' entry dated [entryDate] with the given
  /// lines, plus the audit trail — one transaction. Lines must balance
  /// (validated paise-exact) or the whole thing rolls back.
  Future<void> postManualEntry({
    required String entryDate,
    required String narration,
    required List<ManualJournalLine> lines,
    required String auditJson,
    int? createdBy,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final userId = createdBy ?? await _fallbackUserId(txn);
      final now = DateTime.now().toIso8601String();
      final created = await _insertEntry(
        txn,
        entryDate,
        now,
        userId,
        entryType: 'MANUAL',
        sourceType: 'manual',
        sourceId: null,
        narration: narration,
        lines: [
          for (final l in lines)
            _Line(l.accountId,
                debit: l.debit, credit: l.credit, pledgeId: l.pledgeId),
        ],
      );
      if (created == 0) {
        throw LedgerPostingException('Nothing to post — every line is zero.');
      }
      await AuditLogRepository.instance.log(
        actionCategory: AuditCategory.admin,
        action: 'MANUAL_JOURNAL_ENTRY_POSTED',
        entityType: 'journal_entries',
        entityId: entryDate,
        newValueJson: auditJson,
        createdBy: userId,
        txn: txn,
      );
    });
  }

  /// Posts a financial year's closing entry (Year-End Closing Wizard): zeroes
  /// every Income/Expense account for the year and transfers the net result to
  /// the two Partner Capital accounts per the CA-provided split — one atomic
  /// transaction that also records the closure and its audit trail.
  ///
  /// [lines] is the exact, pre-built and previewed list (Income Dr, Expense Cr,
  /// two Capital lines). It must balance paise-exact — which it always does
  /// when the split sums to the net result — or the whole thing rolls back.
  /// Re-closing a year is blocked here as a second line of defence beyond the
  /// UI check.
  Future<void> postYearEndClosing({
    required String financialYear,
    required String entryDate,
    required String narration,
    required List<YearEndClosingLine> lines,
    required double totalIncome,
    required double totalExpenses,
    required double netResult,
    required String auditJson,
    int? createdBy,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final already = await txn.query('ledger_year_end_closures',
          where: 'financial_year = ?', whereArgs: [financialYear], limit: 1);
      if (already.isNotEmpty) {
        throw LedgerPostingException(
            'Financial year $financialYear is already closed.');
      }

      final nonZero = lines
          .where((l) => l.debit > 0.005 || l.credit > 0.005)
          .toList();
      if (nonZero.isEmpty) {
        throw LedgerPostingException(
            'Nothing to close — no income or expense balances for this year.');
      }
      final drTotal = nonZero.fold(0.0, (s, l) => s + l.debit);
      final crTotal = nonZero.fold(0.0, (s, l) => s + l.credit);
      if (((drTotal - crTotal) * 100).round() != 0) {
        throw LedgerPostingException(
            'Closing entry does not balance: debits '
            '${drTotal.toStringAsFixed(2)} vs credits '
            '${crTotal.toStringAsFixed(2)}. The partner split must sum to the '
            'net result exactly.');
      }

      final userId = createdBy ?? await _fallbackUserId(txn);
      final now = DateTime.now().toIso8601String();

      final entryId = await txn.insert('journal_entries', {
        'entry_date': entryDate,
        'entry_type': 'MANUAL',
        'source_type': 'manual',
        'source_id': null,
        'narration': narration,
        'is_reversed': 0,
        'reversed_by_entry_id': null,
        'created_by': userId,
        'created_at': now,
      });
      for (final l in nonZero) {
        await txn.insert('journal_lines', {
          'journal_entry_id': entryId,
          'account_id': l.accountId,
          'pledge_id': null,
          'debit': l.debit,
          'credit': l.credit,
          'is_virtual': 0,
          'narration': null,
          'created_at': now,
        });
      }

      await txn.insert('ledger_year_end_closures', {
        'financial_year': financialYear,
        'journal_entry_id': entryId,
        'total_income': totalIncome,
        'total_expenses': totalExpenses,
        'net_result': netResult,
        'closed_by': userId,
        'closed_at': now,
      });

      await AuditLogRepository.instance.log(
        actionCategory: AuditCategory.admin,
        action: 'YEAR_END_CLOSING_POSTED',
        entityType: 'ledger_year_end_closures',
        entityId: financialYear,
        newValueJson: auditJson,
        createdBy: userId,
        txn: txn,
      );
    });
  }

  /// Reverses a posted journal entry: inserts a new MANUAL entry dated today
  /// with every original line's debit/credit flipped (same accounts,
  /// pledge tags and virtual flags), marks the original
  /// `is_reversed`/`reversed_by_entry_id`, and writes the audit trail — one
  /// transaction. An entry can be reversed once; a reversal entry can itself
  /// be reversed later by the same mechanism. Returns the reversal entry id.
  Future<int> reverseEntry(int entryId, String reason, {int? createdBy}) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final entries = await txn.query('journal_entries',
          where: 'id = ?', whereArgs: [entryId], limit: 1);
      if (entries.isEmpty) {
        throw LedgerPostingException('Journal entry #$entryId not found.');
      }
      final original = entries.first;
      if ((original['is_reversed'] as int? ?? 0) == 1) {
        throw LedgerPostingException(
            'This entry has already been reversed.');
      }
      final lines = await txn.query('journal_lines',
          where: 'journal_entry_id = ?',
          whereArgs: [entryId],
          orderBy: 'id ASC');
      if (lines.isEmpty) {
        throw LedgerPostingException(
            'Journal entry #$entryId has no lines to reverse.');
      }

      final userId = createdBy ?? await _fallbackUserId(txn);
      final now = DateTime.now().toIso8601String();
      final today = now.substring(0, 10);

      // Manual reversals happen now, regardless of the original's entry_date.
      final reversalId = await _insertReversal(
        txn,
        originalEntryId: entryId,
        lines: lines,
        narration: 'Reversal of: ${original['narration']}',
        entryDate: today,
        userId: userId,
        now: now,
      );

      await AuditLogRepository.instance.log(
        actionCategory: AuditCategory.admin,
        action: 'JOURNAL_ENTRY_REVERSED',
        entityType: 'journal_entries',
        entityId: '$entryId',
        reason: reason,
        oldValueJson: jsonEncode({
          'entry_id': entryId,
          'entry_date': original['entry_date'],
          'narration': original['narration'],
        }),
        newValueJson: jsonEncode({
          'reversal_entry_id': reversalId,
          'entry_date': today,
          'lines_flipped': lines.length,
        }),
        createdBy: userId,
        txn: txn,
      );
      return reversalId;
    });
  }

  /// Core reversal shared by the manual "Reverse This Entry" action (dated
  /// today) and the lock-time staleness pass (dated the business date being
  /// relocked): inserts a MANUAL/'manual' entry mirroring [lines] with
  /// debit/credit flipped — same accounts, pledge tags and virtual flags —
  /// and marks the original reversed. Balance is preserved by construction,
  /// so no re-validation is needed. Returns the reversal entry id.
  Future<int> _insertReversal(
    DatabaseExecutor txn, {
    required int originalEntryId,
    required List<Map<String, Object?>> lines,
    required String narration,
    required String entryDate,
    required int userId,
    required String now,
  }) async {
    final reversalId = await txn.insert('journal_entries', {
      'entry_date': entryDate,
      'entry_type': 'MANUAL',
      'source_type': 'manual',
      'source_id': null,
      'narration': narration,
      'is_reversed': 0,
      'reversed_by_entry_id': null,
      'created_by': userId,
      'created_at': now,
    });
    for (final l in lines) {
      await txn.insert('journal_lines', {
        'journal_entry_id': reversalId,
        'account_id': l['account_id'],
        'pledge_id': l['pledge_id'],
        'debit': l['credit'],
        'credit': l['debit'],
        'is_virtual': l['is_virtual'],
        'created_at': now,
      });
    }
    await txn.update(
      'journal_entries',
      {'is_reversed': 1, 'reversed_by_entry_id': reversalId},
      where: 'id = ?',
      whereArgs: [originalEntryId],
    );
    return reversalId;
  }

  static String _formatDate(String iso) {
    final p = iso.split('-');
    if (p.length < 3) return iso;
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  Future<int> _postForDate(
      DatabaseExecutor txn, String date, int? createdBy) async {
    final accounts = await _loadAccounts(txn);
    final userId = createdBy ?? await _fallbackUserId(txn);
    final now = DateTime.now().toIso8601String();
    var entriesCreated = 0;

    // Surgical staleness pass (unlock-edit-relock): reverses only the
    // entries whose source record changed, so the normal loop below reposts
    // exactly those. A first-ever lock has no entries → no-op.
    entriesCreated += await _reverseStaleEntries(txn, date, userId, now);

    // Every payments row for the day, with a flag for rows already posted.
    // Idempotency counts only NON-REVERSED entries — a stale entry just
    // reversed above must not block its payment from being reposted.
    final payments = await txn.rawQuery('''
      SELECT p.*, EXISTS(
        SELECT 1 FROM journal_entries je
        WHERE je.source_type = 'payment' AND je.source_id = p.id
          AND je.is_reversed = 0
      ) AS already_posted
      FROM payments p
      WHERE DATE(p.payment_date) = ?
      ORDER BY p.id ASC
    ''', [date]);

    Future<int> insertEntry({
      required String sourceType,
      required int? sourceId,
      required String narration,
      required List<_Line> lines,
    }) =>
        _insertEntry(txn, date, now, userId,
            sourceType: sourceType,
            sourceId: sourceId,
            narration: narration,
            lines: lines);

    // ── Renewal-family events — one entry per old-pledge closure ────────────
    //
    // Driven from the pledge closures (not the payments rows) because some
    // subtypes have no payments row at all (RENEWED/INTEREST_CAPITALISED,
    // LOAN_INCREASE with no extra cash). The matching payments row, when one
    // exists, supplies the real cash/bank leg of the SAME entry and is marked
    // consumed so the payments loop below never double-posts it.
    final consumedPaymentIds = <int>{};
    final closures = await txn.rawQuery(
      'SELECT * FROM pledges WHERE closure_date = ? AND renew_type IS NOT NULL '
      'ORDER BY id ASC',
      [date],
    );

    for (final old in closures) {
      final oldId = old['id'] as int;
      final renewType = old['renew_type'] as String;
      final renewSubtype = old['renew_subtype'] as String? ?? '';

      // The payments row for this closure: renewal/part-payment rows carry
      // the OLD pledge's id; loan-increase rows carry the NEW pledge's id.
      final successor = await _successorPledge(txn, oldId);
      final newId = successor['id'] as int;
      final payment = _findRenewalPayment(
          payments, renewType, oldId: oldId, newId: newId);
      if (payment != null) consumedPaymentIds.add(payment['id'] as int);

      // Idempotency: skip if this closure was already posted under either
      // source (payment-triggered or pledge-driven).
      if (payment?['already_posted'] == 1) continue;
      final pledgePosted = await txn.rawQuery(
        "SELECT 1 FROM journal_entries WHERE source_type = 'pledge' "
        'AND source_id = ? AND is_reversed = 0 LIMIT 1',
        [oldId],
      );
      if (pledgePosted.isNotEmpty) continue;

      final lines = _renewalLines(
        accounts,
        renewType: renewType,
        renewSubtype: renewSubtype,
        old: old,
        successor: successor,
        payment: payment,
      );
      entriesCreated += await insertEntry(
        sourceType: payment != null ? 'payment' : 'pledge',
        sourceId: payment != null ? payment['id'] as int : oldId,
        narration: _renewalNarration(renewType, renewSubtype,
            old['pledge_no'] as String?, successor['pledge_no'] as String?),
        lines: lines,
      );
    }

    // ── Simple payment events ───────────────────────────────────────────────
    final consumedAdjustmentIds = <int>{};
    for (final p in payments) {
      final id = p['id'] as int;
      if (consumedPaymentIds.contains(id)) continue;
      if (p['already_posted'] == 1) continue;

      switch (p['payment_type'] as String) {
        case 'LOAN_DISBURSED':
          final pledgeNo = await _pledgeNo(txn, p['pledge_id'] as int?);
          final disbPayMethod = _paymentMethodName(accounts, p);
          entriesCreated += await insertEntry(
            sourceType: 'payment',
            sourceId: id,
            narration: 'Loan Disbursed: Pledge #$pledgeNo',
            lines: [
              _Line(accounts.goldLoanReceivable,
                  pledgeId: p['pledge_id'] as int?,
                  debit: _amount(p, 'amount'),
                  narration: 'To $disbPayMethod : $pledgeNo'),
              ..._realLines(accounts, p, debit: false,
                  pledgeId: p['pledge_id'] as int?,
                  narrationFor: (name) => 'By $name : $pledgeNo',
                  bankOverrideName: 'UPI'),
            ],
          );

        case 'LOAN_FULL_CLOSURE':
          entriesCreated += await _postFullClosure(txn, accounts, p, insertEntry);

        case 'EXPENSE':
          final account = await _expenseAccount(txn, accounts, p);
          final expSubCat = p['sub_category'] as String? ?? 'Uncategorised';
          final expNotes = (p['notes'] as String? ?? '').trim();
          final expNoteSuffix = expNotes.isNotEmpty ? ' : $expNotes' : '';
          final expPayMethod = _paymentMethodName(accounts, p);
          entriesCreated += await insertEntry(
            sourceType: 'payment',
            sourceId: id,
            narration: 'Expense: $expSubCat',
            lines: [
              _Line(account,
                  debit: _amount(p, 'amount'),
                  narration: 'To $expPayMethod$expNoteSuffix'),
              ..._realLines(accounts, p, debit: false, pledgeId: null,
                  narrationFor: (name) => 'By $expSubCat$expNoteSuffix'),
            ],
          );

        case 'ADJUSTMENT':
          entriesCreated += await _postAdjustment(
              accounts, p, payments, consumedAdjustmentIds, insertEntry);

        // Partner money movements. Real cash both ways; the partner side
        // comes from ledger_account_id — never sub_category text. Drawings
        // and TDS debit Partner Capital directly (Option A — no separate
        // Drawings account exists). Account name is read from
        // chart_of_accounts at posting time so renames are reflected.
        case 'CAPITAL':
          final partnerAccount = _ledgerAccount(accounts, p);
          final partnerName = accounts.nameById[partnerAccount] ?? 'Partner';
          final moneyIn = p['sub_category'] == 'CAPITAL_CONTRIBUTION';
          final capSubCat = p['sub_category'] as String? ?? '';
          final capSubDisplay = switch (capSubCat) {
            'CAPITAL_CONTRIBUTION' => 'Capital Contribution',
            'DRAWINGS' => 'Drawings',
            'TDS_PAYMENT' => 'TDS',
            _ => capSubCat,
          };
          final capNotes = (p['notes'] as String? ?? '').trim();
          final capNoteSuffix = capNotes.isNotEmpty ? ' : $capNotes' : '';
          final capPayMethod = _paymentMethodName(accounts, p);
          final capEntryNarration = switch (capSubCat) {
            'CAPITAL_CONTRIBUTION' => 'Capital Contribution: $partnerName',
            'DRAWINGS' => 'To Drawings: $partnerName',
            'TDS_PAYMENT' => 'To TDS: $partnerName',
            final other => throw LedgerPostingException(
                'No posting rule for CAPITAL / "$other" (entry #$id).'),
          };
          final capAccountNarration = switch (capSubCat) {
            'CAPITAL_CONTRIBUTION' => 'By Capital Contribution($capPayMethod)',
            'DRAWINGS' => 'To Drawings($capPayMethod)',
            'TDS_PAYMENT' => 'To TDS($capPayMethod)',
            _ => null,
          };
          // Cash/bank direction: Dr (moneyIn) → "To {partner} : SubCat"
          //                      Cr (moneyOut) → "By {partner} : SubCat"
          final capCashNarrationPrefix = moneyIn ? 'To' : 'By';
          entriesCreated += await insertEntry(
            sourceType: 'payment',
            sourceId: id,
            narration: capEntryNarration,
            lines: moneyIn
                ? [
                    ..._realLines(accounts, p, debit: true, pledgeId: null,
                        narrationFor: (name) =>
                            '$capCashNarrationPrefix $partnerName : $capSubDisplay$capNoteSuffix'),
                    _Line(partnerAccount,
                        credit: _amount(p, 'amount'),
                        narration: capAccountNarration),
                  ]
                : [
                    _Line(partnerAccount,
                        debit: _amount(p, 'amount'),
                        narration: capAccountNarration),
                    ..._realLines(accounts, p, debit: false, pledgeId: null,
                        narrationFor: (name) =>
                            '$capCashNarrationPrefix $partnerName : $capSubDisplay$capNoteSuffix'),
                  ],
          );

        // Renewal-family rows are posted with their pledge closure above; one
        // reaching this point has no closure dated today — a data problem the
        // user must resolve before the day can be locked.
        case 'RENEWAL_INTEREST_PAID':
        case 'PART_PAYMENT_RECEIVED':
        case 'LOAN_INCREASE_DISBURSED':
          throw LedgerPostingException(
              'Renewal payment (entry #$id) has no matching pledge closure '
              'dated $date, so it cannot be posted to the ledger.');

        default:
          throw LedgerPostingException(
              'No posting rule for payment type "${p['payment_type']}" '
              '(entry #$id).');
      }
    }

    return entriesCreated;
  }

  // ─── Staleness pass (unlock-edit-relock) ───────────────────────────────────

  /// Reverses journal entries for [date] whose source record was edited (or
  /// deleted) after the entry was posted — detected by comparing the source's
  /// `updated_at` (NULL = never edited) against the entry's `created_at`.
  /// Every non-stale entry is left completely untouched; the normal posting
  /// loop then reposts only the reversed ones from current data. Reversals
  /// are dated [date] itself (not today) so the relocked day's reports stay
  /// internally consistent — dating them today would double-count the stale
  /// figure on any report between the business date and today.
  ///
  /// Re-runs fresh on every lock attempt, so repeated unlock-edit-relock
  /// cycles each correct exactly what changed that cycle.
  Future<int> _reverseStaleEntries(
      DatabaseExecutor txn, String date, int userId, String now) async {
    final entries = await txn.rawQuery(
      "SELECT * FROM journal_entries WHERE entry_date = ? "
      "AND is_reversed = 0 AND source_type IN ('payment', 'pledge') "
      'ORDER BY id ASC',
      [date],
    );
    var reversed = 0;

    for (final entry in entries) {
      final sourceId = entry['source_id'] as int?;
      if (sourceId == null) continue;
      final sourceType = entry['source_type'] as String;
      final table = sourceType == 'payment' ? 'payments' : 'pledges';

      String? narration;
      final source = await txn.query(table,
          columns: ['updated_at'],
          where: 'id = ?',
          whereArgs: [sourceId],
          limit: 1);
      if (source.isEmpty) {
        // Orphaned (source deleted, e.g. by a Data Fix) — reverse with no
        // replacement; the posting loop finds nothing to repost for it.
        narration =
            'Reversal — source $sourceType deleted: ${entry['narration']}';
      } else {
        final updatedAt = source.first['updated_at'] as String?;
        final postedAt = entry['created_at'] as String? ?? '';
        if (updatedAt != null && updatedAt.compareTo(postedAt) > 0) {
          narration = 'Auto-reversed — source record modified after '
              'posting: ${entry['narration']}';
        }
      }
      if (narration == null) continue;

      final entryId = entry['id'] as int;
      final lines = await txn.query('journal_lines',
          where: 'journal_entry_id = ?',
          whereArgs: [entryId],
          orderBy: 'id ASC');
      await _insertReversal(
        txn,
        originalEntryId: entryId,
        lines: lines,
        narration: narration,
        entryDate: date,
        userId: userId,
        now: now,
      );
      await AuditLogRepository.instance.log(
        actionCategory: AuditCategory.admin,
        action: 'JOURNAL_ENTRY_AUTO_REVERSED',
        entityType: 'journal_entries',
        entityId: '$entryId',
        reason: narration,
        txn: txn,
      );
      reversed++;
    }
    return reversed;
  }

  // ─── Simple-event helpers ──────────────────────────────────────────────────

  Future<int> _postFullClosure(
    DatabaseExecutor txn,
    _Accounts accounts,
    Map<String, dynamic> p,
    Future<int> Function({
      required String sourceType,
      required int? sourceId,
      required String narration,
      required List<_Line> lines,
    }) insertEntry,
  ) async {
    final pledgeId = p['pledge_id'] as int?;
    if (pledgeId == null) {
      throw LedgerPostingException(
          'Closure payment (entry #${p['id']}) has no pledge attached.');
    }
    final pledge = await txn.query('pledges',
        where: 'id = ?', whereArgs: [pledgeId], limit: 1);
    if (pledge.isEmpty) {
      throw LedgerPostingException(
          'Closure payment (entry #${p['id']}) references a missing pledge.');
    }
    final principal =
        (pledge.first['principal_amount'] as num?)?.toDouble() ?? 0.0;
    final collected = _amount(p, 'amount');
    // Interest actually realised = collected − principal (negative only if a
    // discount below principal was given — posted as a debit then).
    final interest = collected - principal;

    final closurePledgeNo = pledge.first['pledge_no'] as String?;
    final closurePayMethod = _paymentMethodName(accounts, p);
    return insertEntry(
      sourceType: 'payment',
      sourceId: p['id'] as int,
      narration: 'Loan Closure: Pledge #$closurePledgeNo',
      lines: [
        ..._realLines(accounts, p, debit: true, pledgeId: pledgeId,
            narrationFor: (name) => 'To $name : $closurePledgeNo',
            bankOverrideName: 'UPI'),
        _Line(accounts.goldLoanReceivable,
            pledgeId: pledgeId,
            credit: principal,
            narration: 'By $closurePayMethod : $closurePledgeNo'),
        if (interest >= 0)
          _Line(accounts.interestCollected,
              pledgeId: pledgeId,
              credit: interest,
              narration: 'By $closurePayMethod : $closurePledgeNo')
        else
          _Line(accounts.interestCollected,
              pledgeId: pledgeId,
              debit: -interest,
              narration: 'By $closurePayMethod : $closurePledgeNo'),
      ],
    );
  }

  /// Transfers post one entry per OUT/IN row pair: Dr destination account,
  /// Cr source account (source_id = the OUT row). Retired ADD_CASH / ADD_UPI /
  /// ADD_BANK rows (historical, plus bank-account opening balances) have no
  /// posting rule — pre-ledger money-in is covered by the opening baseline.
  Future<int> _postAdjustment(
    _Accounts accounts,
    Map<String, dynamic> p,
    List<Map<String, dynamic>> dayPayments,
    Set<int> consumedAdjustmentIds,
    Future<int> Function({
      required String sourceType,
      required int? sourceId,
      required String narration,
      required List<_Line> lines,
    }) insertEntry,
  ) async {
    final id = p['id'] as int;
    if (consumedAdjustmentIds.contains(id)) return 0;

    final sub = p['sub_category'] as String? ?? '';
    if (sub == 'ADD_CASH' || sub == 'ADD_UPI' || sub == 'ADD_BANK') {
      return 0;
    }

    Map<String, dynamic>? partner;
    for (final r in dayPayments) {
      if (r['id'] == id ||
          r['payment_type'] != 'ADJUSTMENT' ||
          (r['sub_category'] as String? ?? '') != sub ||
          r['direction'] == p['direction'] ||
          (_amount(r, 'amount') - _amount(p, 'amount')).abs() > _tolerance ||
          consumedAdjustmentIds.contains(r['id'] as int)) {
        continue;
      }
      partner = r;
      break;
    }
    if (partner == null) {
      throw LedgerPostingException(
          'Transfer adjustment (entry #$id, $sub) has no matching '
          'opposite-direction row, so it cannot be posted.');
    }
    consumedAdjustmentIds
      ..add(id)
      ..add(partner['id'] as int);

    // Pair already posted (under the OUT row's id) → nothing to do.
    if (p['already_posted'] == 1 || partner['already_posted'] == 1) return 0;

    final outRow = p['direction'] == 'out' ? p : partner;
    final inRow = p['direction'] == 'out' ? partner : p;
    final fromAccount = _rowAccount(accounts, outRow);
    final toAccount = _rowAccount(accounts, inRow);

    return insertEntry(
      sourceType: 'payment',
      sourceId: outRow['id'] as int,
      narration: 'Transfer: ${accounts.nameById[fromAccount]} → '
          '${accounts.nameById[toAccount]}',
      lines: [
        _Line(toAccount, debit: _amount(inRow, 'amount')),
        _Line(fromAccount, credit: _amount(outRow, 'amount')),
      ],
    );
  }

  /// Ledger account for a CAPITAL row — resolved by id via
  /// ledger_account_id, never by sub_category text.
  int _ledgerAccount(_Accounts accounts, Map<String, dynamic> p) {
    final id = p['ledger_account_id'] as int?;
    if (id == null || !accounts.nameById.containsKey(id)) {
      throw LedgerPostingException(
          'Partner transaction (entry #${p['id']}) has no partner capital '
          'account attached, so it cannot be posted.');
    }
    return id;
  }

  /// The single account a transfer row moved money through (cash or bank).
  int _rowAccount(_Accounts accounts, Map<String, dynamic> row) {
    if (_amount(row, 'bank_amount') > 0) {
      final bankAccountId = row['bank_account_id'] as int?;
      if (bankAccountId == null) {
        throw LedgerPostingException(
            'Transfer adjustment (entry #${row['id']}) has a bank amount but '
            'no bank account.');
      }
      return accounts.bankAccount(bankAccountId);
    }
    return accounts.cash;
  }

  // ─── Renewal-family line building ──────────────────────────────────────────

  /// Builds the 2–7 lines for one renewal-family closure, exactly per the
  /// mapping: gross Gold Loan Receivable legs, the virtual Cash pair for
  /// MIN(OP, NP) (always Cash, never bank, `is_virtual = 1`), the real
  /// cash/bank leg from the payments row, and the interest recognition.
  List<_Line> _renewalLines(
    _Accounts accounts, {
    required String renewType,
    required String renewSubtype,
    required Map<String, dynamic> old,
    required Map<String, dynamic> successor,
    required Map<String, dynamic>? payment,
  }) {
    final oldId = old['id'] as int;
    final newId = successor['id'] as int;
    final op = (old['principal_amount'] as num?)?.toDouble() ?? 0.0;
    final np = (successor['principal_amount'] as num?)?.toDouble() ?? 0.0;
    final interest = (old['total_interest_paid'] as num?)?.toDouble() ?? 0.0;
    final virtual = min(op, np);
    final oldNo = old['pledge_no'] as String?;
    final newNo = successor['pledge_no'] as String?;
    // Default to 'Cash' when no payment row exists (e.g. INTEREST_CAPITALISED).
    final payMethod =
        payment != null ? _paymentMethodName(accounts, payment) : 'Cash';

    // Legs shared by every subtype.
    // Virtual cash lines always use 'Cash' (they are always accounts.cash).
    final virtualAndGross = <_Line>[
      _Line(accounts.cash,
          pledgeId: oldId, debit: virtual, isVirtual: true,
          narration: 'To Cash : $oldNo'),
      _Line(accounts.goldLoanReceivable,
          pledgeId: oldId, credit: op,
          narration: 'By $payMethod : $oldNo'),
      _Line(accounts.goldLoanReceivable,
          pledgeId: newId, debit: np,
          narration: 'To $payMethod : $newNo'),
      _Line(accounts.cash,
          pledgeId: newId, credit: virtual, isVirtual: true,
          narration: 'By Cash : $newNo'),
    ];

    switch ((renewType, renewSubtype)) {
      case ('RENEWED', 'INTEREST_PAID'):
        return [
          ...virtualAndGross,
          ..._realLines(accounts, payment, debit: true, pledgeId: oldId,
              narrationFor: (name) => 'To $name : $oldNo',
              bankOverrideName: 'UPI'),
          _Line(accounts.interestCollected,
              pledgeId: oldId, credit: interest,
              narration: 'By $payMethod : $oldNo'),
        ];

      case ('RENEWED', 'INTEREST_CAPITALISED'):
        return [
          ...virtualAndGross,
          _Line(accounts.interestCollected,
              pledgeId: newId, credit: interest,
              narration: 'By $payMethod : $newNo'),
        ];

      case ('PART_PAYMENT', 'PRINCIPAL_AND_INTEREST'):
        return [
          ...virtualAndGross,
          ..._realLines(accounts, payment, debit: true, pledgeId: oldId,
              narrationFor: (name) => 'To $name : $oldNo',
              bankOverrideName: 'UPI'),
          _Line(accounts.interestCollected,
              pledgeId: oldId, credit: interest,
              narration: 'By $payMethod : $oldNo'),
        ];

      case ('PART_PAYMENT', 'FIXED_AMOUNT_INCLUSIVE'):
        final fixed = payment == null ? 0.0 : _amount(payment, 'amount');
        return [
          ...virtualAndGross,
          ..._realLines(accounts, payment, debit: true, pledgeId: oldId,
              narrationFor: (name) => 'To $name : $oldNo',
              bankOverrideName: 'UPI'),
          if (fixed >= interest)
            _Line(accounts.interestCollected,
                pledgeId: oldId, credit: interest,
                narration: 'By $payMethod : $oldNo')
          else ...[
            // F < I: F recognised now on the old pledge, the capitalised
            // remainder (I − F) on the new one — total remains I.
            _Line(accounts.interestCollected,
                pledgeId: oldId, credit: fixed,
                narration: 'By $payMethod : $oldNo'),
            _Line(accounts.interestCollected,
                pledgeId: newId, credit: interest - fixed,
                narration: 'By $payMethod : $newNo'),
          ],
        ];

      // Both loan-increase subtypes post identically; the extra cash given is
      // the real leg (credited — money out), on the new pledge.
      case ('LOAN_INCREASE', _):
        return [
          ...virtualAndGross,
          ..._realLines(accounts, payment, debit: false, pledgeId: newId,
              narrationFor: (name) => 'By $name : $newNo',
              bankOverrideName: 'UPI'),
          _Line(accounts.interestCollected,
              pledgeId: newId, credit: interest,
              narration: 'By $payMethod : $newNo'),
        ];

      default:
        throw LedgerPostingException(
            'No posting rule for renewal "$renewType / $renewSubtype" '
            '(pledge #${old['pledge_no']}).');
    }
  }

  String _renewalNarration(
      String renewType, String renewSubtype, String? oldNo, String? newNo) {
    final action = switch (renewType) {
      'RENEWED' => 'Renewal',
      'PART_PAYMENT' => 'Part Payment',
      'LOAN_INCREASE' => 'Loan Increase',
      _ => renewType,
    };
    final subtype = switch (renewSubtype) {
      'INTEREST_PAID' => 'Interest Paid',
      'INTEREST_CAPITALISED' => 'Interest Capitalised',
      'PRINCIPAL_AND_INTEREST' => 'Principal & Interest',
      'FIXED_AMOUNT_INCLUSIVE' => 'Fixed Amount',
      'INTEREST_NOT_CAPITALISED' => 'Interest Not Capitalised',
      _ => renewSubtype,
    };
    return '$action: Pledge #$oldNo → #$newNo ($subtype)';
  }

  /// Renewal/part-payment rows carry the OLD pledge's id; loan-increase rows
  /// carry the NEW pledge's id (see PledgeRepository's renewal flows).
  Map<String, dynamic>? _findRenewalPayment(
    List<Map<String, dynamic>> payments,
    String renewType, {
    required int oldId,
    required int newId,
  }) {
    final (type, pledgeId) = switch (renewType) {
      'RENEWED' => ('RENEWAL_INTEREST_PAID', oldId),
      'PART_PAYMENT' => ('PART_PAYMENT_RECEIVED', oldId),
      _ => ('LOAN_INCREASE_DISBURSED', newId),
    };
    for (final p in payments) {
      if (p['payment_type'] == type && p['pledge_id'] == pledgeId) return p;
    }
    return null;
  }

  Future<Map<String, dynamic>> _successorPledge(
      DatabaseExecutor txn, int oldPledgeId) async {
    final rows = await txn.query('pledges',
        where: 'renewal_parent_id = ?',
        whereArgs: [oldPledgeId],
        orderBy: 'id ASC',
        limit: 1);
    if (rows.isEmpty) {
      throw LedgerPostingException(
          'Renewed pledge (id $oldPledgeId) has no successor pledge — '
          'cannot post its renewal to the ledger.');
    }
    return rows.first;
  }

  // ─── Shared helpers ────────────────────────────────────────────────────────

  /// The real cash/bank leg of [payment]: one line per component actually
  /// used, routed to Cash in Hand and/or the specific bank account.
  /// [narrationFor] receives the account display name ("Cash" or bank name)
  /// and returns the per-line narration to attach; omit for no per-line narration.
  List<_Line> _realLines(
    _Accounts accounts,
    Map<String, dynamic>? payment, {
    required bool debit,
    required int? pledgeId,
    String Function(String accountName)? narrationFor,
    String? bankOverrideName,
  }) {
    if (payment == null) return const [];
    final lines = <_Line>[];
    final cash = _amount(payment, 'cash_amount');
    final bank = _amount(payment, 'bank_amount');
    if (cash > 0) {
      lines.add(_Line(accounts.cash,
          pledgeId: pledgeId,
          debit: debit ? cash : 0,
          credit: debit ? 0 : cash,
          narration: narrationFor?.call('Cash')));
    }
    if (bank > 0) {
      final bankAccountId = payment['bank_account_id'] as int?;
      if (bankAccountId == null) {
        throw LedgerPostingException(
            'Payment entry #${payment['id']} has a bank amount but no bank '
            'account selected.');
      }
      final coaId = accounts.bankAccount(bankAccountId);
      final bankName = bankOverrideName ?? accounts.nameById[coaId] ?? 'Bank';
      lines.add(_Line(coaId,
          pledgeId: pledgeId,
          debit: debit ? bank : 0,
          credit: debit ? 0 : bank,
          narration: narrationFor?.call(bankName)));
    }
    return lines;
  }

  /// Display name for the payment method (Cash / bank name / "Cash & bank").
  String _paymentMethodName(_Accounts accounts, Map<String, dynamic> payment) {
    final hasCash = _amount(payment, 'cash_amount') > 0.005;
    final hasBank = _amount(payment, 'bank_amount') > 0.005;
    final bankAccountId = payment['bank_account_id'] as int?;
    final bankName = bankAccountId != null
        ? (accounts.nameById[accounts.bankByLinkedId[bankAccountId]] ?? 'Bank')
        : 'Bank';
    if (hasCash && hasBank) return 'Cash & $bankName';
    if (hasBank) return bankName;
    return 'Cash';
  }

  /// Inserts one journal entry + lines after validating Dr = Cr. Zero-amount
  /// lines are dropped; an all-zero entry is skipped entirely. Returns 1 when
  /// an entry was created, 0 when skipped.
  Future<int> _insertEntry(
    DatabaseExecutor txn,
    String date,
    String now,
    int userId, {
    required String sourceType,
    required int? sourceId,
    required String narration,
    required List<_Line> lines,
    String entryType = 'AUTO',
  }) async {
    // Half-paisa threshold: drops float noise and true zero lines but keeps
    // a genuine ₹0.01 line (amounts carry paise since the wizard accepts
    // decimals). A larger threshold would silently drop one-paisa lines and
    // leave the entry imbalanced below the validation tolerance.
    final nonZero =
        lines.where((l) => l.debit > 0.005 || l.credit > 0.005);
    if (nonZero.isEmpty) return 0;

    final drTotal = nonZero.fold(0.0, (s, l) => s + l.debit);
    final crTotal = nonZero.fold(0.0, (s, l) => s + l.credit);
    // Paise-exact: rounding removes IEEE-754 representation noise (~1e-12)
    // without masking a real imbalance of one paisa or more.
    if (((drTotal - crTotal) * 100).round() != 0) {
      throw LedgerPostingException(
          'Journal entry does not balance for "$narration": debits '
          '${drTotal.toStringAsFixed(2)} vs credits '
          '${crTotal.toStringAsFixed(2)}. This indicates inconsistent data '
          'for that transaction — correct it and close the day again.');
    }

    final entryId = await txn.insert('journal_entries', {
      'entry_date': date,
      'entry_type': entryType,
      'source_type': sourceType,
      'source_id': sourceId,
      'narration': narration,
      'is_reversed': 0,
      'reversed_by_entry_id': null,
      'created_by': userId,
      'created_at': now,
    });
    for (final line in nonZero) {
      await txn.insert('journal_lines', {
        'journal_entry_id': entryId,
        'account_id': line.accountId,
        'pledge_id': line.pledgeId,
        'debit': line.debit,
        'credit': line.credit,
        'is_virtual': line.isVirtual ? 1 : 0,
        'narration': line.narration,
        'created_at': now,
      });
    }
    return 1;
  }

  Future<_Accounts> _loadAccounts(DatabaseExecutor txn) async {
    final rows = await txn.query('chart_of_accounts');
    int? byCode(String code) {
      for (final r in rows) {
        if (r['code'] == code) return r['id'] as int;
      }
      return null;
    }

    Map<int, int> byLinked(String table) => {
          for (final r in rows)
            if (r['linked_table'] == table && r['linked_id'] != null)
              r['linked_id'] as int: r['id'] as int,
        };

    final cash = byCode('1001');
    final glr = byCode('1101');
    final interest = byCode('4001');
    if (cash == null || glr == null || interest == null) {
      throw LedgerPostingException(
          'A system ledger account (Cash in Hand / Gold Loan Receivable / '
          'Interest Collected) is missing from the chart of accounts.');
    }
    return _Accounts(
      cash: cash,
      goldLoanReceivable: glr,
      interestCollected: interest,
      bankByLinkedId: byLinked('bank_accounts'),
      expenseByLinkedId: byLinked('expense_categories'),
      nameById: {for (final r in rows) r['id'] as int: r['name'] as String},
    );
  }

  /// Ledger account for an EXPENSE row: via ledger_account_id, falling back
  /// to a name match on sub_category for rows created before ids were stored
  /// (pre-ledger production rows awaiting the Data Fix).
  Future<int> _expenseAccount(
    DatabaseExecutor txn,
    _Accounts accounts,
    Map<String, dynamic> p,
  ) async {
    final direct = p['ledger_account_id'] as int?;
    if (direct != null && accounts.nameById.containsKey(direct)) {
      return direct;
    }

    final sub = p['sub_category'] as String? ?? '';
    final rows = await txn.query('expense_categories',
        columns: ['id'], where: 'name = ?', whereArgs: [sub], limit: 1);
    final categoryId = rows.isEmpty ? null : rows.first['id'] as int?;
    final accountId =
        categoryId == null ? null : accounts.expenseByLinkedId[categoryId];
    if (accountId == null) {
      throw LedgerPostingException(
          'Expense "${p['sub_category']}" (entry #${p['id']}) is not linked '
          'to an expense category with a ledger account. Fix the expense via '
          'Edit Transaction, then close the day again.');
    }
    return accountId;
  }

  /// `journal_entries.created_by` is NOT NULL but day locking is not
  /// user-attributed anywhere in the app yet — fall back to the admin user.
  Future<int> _fallbackUserId(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery(
        "SELECT id FROM users ORDER BY CASE role WHEN 'admin' THEN 0 ELSE 1 "
        'END, id ASC LIMIT 1');
    if (rows.isEmpty) {
      throw LedgerPostingException('No users exist to attribute the '
          'journal entries to.');
    }
    return rows.first['id'] as int;
  }

  Future<String> _pledgeNo(DatabaseExecutor txn, int? pledgeId) async {
    if (pledgeId == null) return '?';
    final rows = await txn.query('pledges',
        columns: ['pledge_no'], where: 'id = ?', whereArgs: [pledgeId], limit: 1);
    return rows.isEmpty ? '?' : rows.first['pledge_no'] as String? ?? '?';
  }

  double _amount(Map<String, dynamic> row, String column) =>
      (row[column] as num?)?.toDouble() ?? 0.0;
}
