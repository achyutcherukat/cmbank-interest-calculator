import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/photo_sync_repository.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../accounts/data/daily_balance_repository.dart';
import '../../admin/data/audit_log_repository.dart';
import '../../gold_stock/data/gold_stock_repository.dart';
import 'payment_model.dart';
import 'payments_repository.dart';
import 'pledge_item_model.dart';
import 'pledge_model.dart';

/// Repository for pledges, their items, and the pledge-level lifecycle
/// operations (create / migrate / close / renew). Accounts-ledger rows are
/// written through [PaymentsRepository]; lifecycle events are recorded through
/// [AuditLogRepository].
class PledgeRepository {
  PledgeRepository._();

  static final PledgeRepository instance = PledgeRepository._();

  final _settingsRepo = AppSettingsRepository();
  final _payments = PaymentsRepository.instance;
  final _audit = AuditLogRepository.instance;

  /// After a backdated create/close/renew, recompute the affected day and every
  /// following unlocked day for both the cash ledger and the gold-stock
  /// register. A `null` or today's [contextDate] is a no-op (the current day is
  /// recomputed live whenever it is viewed/locked).
  Future<void> _cascadeForContextDate(String? contextDate) async {
    if (contextDate == null) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (contextDate.compareTo(today) >= 0) return;
    await DailyBalanceRepository.instance.cascadeFrom(contextDate);
    await GoldStockRepository.instance.cascadeFrom(contextDate);
  }

  // ─── Pledge Number ───────────────────────────────────────────────────────────

  Future<String> nextPledgeNumber() async {
    final db = await AppDatabase.instance.database;
    final lastNew =
        int.tryParse(await _settingsRepo.getString('new_pledge_last_number') ?? '') ??
            0;
    // Legacy fallback for installs that still hold starting_pledge_number.
    final legacyStart =
        int.tryParse(await _settingsRepo.getString('starting_pledge_number') ?? '') ??
            3200;
    final base = lastNew > 0 ? lastNew + 1 : legacyStart;

    final rows = await db
        .rawQuery('SELECT MAX(CAST(pledge_no AS INTEGER)) as mx FROM pledges');
    final maxFromDb = (rows.first['mx'] as int?) ?? 0;

    return '${maxFromDb >= base ? maxFromDb + 1 : base}';
  }

  Future<bool> pledgeNumberExists(String number) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'pledges',
      columns: ['id'],
      where: 'pledge_no = ?',
      whereArgs: [number],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _advanceNewPledgeCounter(
      DatabaseExecutor txn, String pledgeNo, String now) async {
    final used = int.tryParse(pledgeNo) ?? 0;
    if (used <= 0) return;
    await txn.insert(
      'settings',
      {
        'key': 'new_pledge_last_number',
        'value': '$used',
        'value_type': 'int',
        'updated_by': null,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ─── Create (new pledge) ─────────────────────────────────────────────────────

  /// Creates a new pledge with its items and the LOAN_DISBURSED ledger entry.
  Future<int> createPledge(
    PledgeModel pledge,
    List<PledgeItemModel> items, {
    double cashAmount = 0,
    double upiAmount = 0,
    int? createdBy,
    String? contextDate,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final paymentDate = contextDate ?? now.substring(0, 10);

    final pledgeId = await db.transaction((txn) async {
      final pledgeMap = pledge.toMap();
      pledgeMap['status'] = 'open';
      pledgeMap['source'] = 'new';
      pledgeMap['renew_type'] = null;
      pledgeMap['renew_subtype'] = null;
      pledgeMap['created_by'] = createdBy;
      pledgeMap['created_at'] = now;
      pledgeMap['updated_at'] = now;
      final pledgeId = await txn.insert('pledges', pledgeMap);

      await _insertItems(txn, pledgeId, items, now);
      await _registerPledgePhotos(txn, pledgeId, pledge);

      await _payments.createLoanDisbursed(
        pledgeId,
        pledge.loanAmount,
        cashAmount,
        upiAmount,
        paymentDate,
        notes: 'Loan for pledge #${pledge.pledgeNumber}',
        createdBy: createdBy,
        txn: txn,
      );

      await _advanceNewPledgeCounter(txn, pledge.pledgeNumber, now);

      await _audit.log(
        actionCategory: AuditCategory.pledge,
        action: 'PLEDGE_CREATED',
        entityType: 'pledges',
        entityId: '$pledgeId',
        createdBy: createdBy,
        txn: txn,
      );

      return pledgeId;
    });

    await _cascadeForContextDate(contextDate);
    return pledgeId;
  }

  // ─── Create (migrated pledge) ────────────────────────────────────────────────

  /// Loads an existing/physical pledge into the system. No ledger entry is
  /// created (the loan was disbursed before migration).
  Future<int> createMigratedPledge(
    PledgeModel pledge,
    List<PledgeItemModel> items, {
    int? createdBy,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    return db.transaction((txn) async {
      final pledgeMap = pledge.toMap();
      pledgeMap['status'] = 'open';
      pledgeMap['source'] = 'migrated';
      pledgeMap['created_by'] = createdBy;
      pledgeMap['created_at'] = now;
      pledgeMap['updated_at'] = now;
      final pledgeId = await txn.insert('pledges', pledgeMap);

      await _insertItems(txn, pledgeId, items, now);
      await _registerPledgePhotos(txn, pledgeId, pledge);

      await _audit.log(
        actionCategory: AuditCategory.pledge,
        action: 'PLEDGE_CREATED',
        entityType: 'pledges',
        entityId: '$pledgeId',
        createdBy: createdBy,
        txn: txn,
      );

      return pledgeId;
    });
  }

  /// Records gold + scanned-form photos in photo_sync_log for backup (Part 10).
  /// Runs inside the pledge-create transaction so rows roll back together.
  Future<void> _registerPledgePhotos(
    DatabaseExecutor txn,
    int pledgeId,
    PledgeModel pledge,
  ) async {
    await PhotoSyncRepository.instance.insertPhotos(
      pledgeId: pledgeId,
      photoType: PhotoType.gold,
      localPaths: pledge.goldPhotoPaths ?? const [],
      txn: txn,
    );
    await PhotoSyncRepository.instance.insertPhotos(
      pledgeId: pledgeId,
      photoType: PhotoType.document,
      localPaths: pledge.formPhotoPaths ?? const [],
      txn: txn,
    );
  }

  Future<void> _insertItems(
    DatabaseExecutor txn,
    int pledgeId,
    List<PledgeItemModel> items,
    String now,
  ) async {
    for (final item in items) {
      final itemMap = item.toMap();
      itemMap.remove('id');
      itemMap['pledge_id'] = pledgeId;
      itemMap['created_at'] = now;
      await txn.insert('pledge_items', itemMap);
    }
  }

  // ─── Read ─────────────────────────────────────────────────────────────────

  Future<PledgeModel?> getPledgeByNumber(String number) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('pledges',
        where: 'pledge_no = ?', whereArgs: [number], limit: 1);
    if (rows.isEmpty) return null;
    return PledgeModel.fromMap(rows.first);
  }

  Future<PledgeModel?> getPledgeById(int id) async {
    final db = await AppDatabase.instance.database;
    final rows =
        await db.query('pledges', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return PledgeModel.fromMap(rows.first);
  }

  Future<PledgeModel?> getSuccessorPledge(int pledgeId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('pledges',
        where: 'renewal_parent_id = ?',
        whereArgs: [pledgeId],
        orderBy: 'id ASC',
        limit: 1);
    if (rows.isEmpty) return null;
    return PledgeModel.fromMap(rows.first);
  }

  /// Open pledges, newest pledge number first. Supports paging via [offset]
  /// for the Open Pledge endless-scroll list.
  Future<List<PledgeModel>> getOpenPledges({int limit = 50, int offset = 0}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('pledges',
        where: "status = 'open'",
        orderBy: 'CAST(pledge_no AS INTEGER) DESC, id DESC',
        limit: limit,
        offset: offset);
    return rows.map(PledgeModel.fromMap).toList();
  }

  Future<List<PledgeModel>> getClosedPledges({int limit = 50}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('pledges',
        where: "status = 'closed'",
        orderBy: 'closure_date DESC, id DESC',
        limit: limit);
    return rows.map(PledgeModel.fromMap).toList();
  }

  Future<Map<String, dynamic>?> getCustomerById(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('customers',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<PledgeItemModel>> getItemsForPledge(int pledgeId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db
        .query('pledge_items', where: 'pledge_id = ?', whereArgs: [pledgeId]);
    return rows.map(PledgeItemModel.fromMap).toList();
  }

  Future<List<PaymentModel>> getPaymentsForPledge(int pledgeId) =>
      _payments.getPaymentsForPledge(pledgeId);

  // ─── Close / renew primitives ────────────────────────────────────────────────

  /// Updates a pledge row to its closed state. Used by normal closure and by
  /// every renewal flow (with the appropriate [renewType] / [renewSubtype]).
  /// Does NOT create ledger entries — callers add those as needed.
  Future<void> markPledgeClosed(
    DatabaseExecutor txn, {
    required int pledgeId,
    String? renewType,
    String? renewSubtype,
    required double totalInterestPaid,
    required double totalAmountCollected,
    String? closureDate,
    String? closedAt,
  }) async {
    final now = closedAt ?? DateTime.now().toIso8601String();
    await txn.update(
      'pledges',
      {
        'status': 'closed',
        'renew_type': renewType,
        'renew_subtype': renewSubtype,
        'closure_date': closureDate ?? now.substring(0, 10),
        'closed_at': now,
        'total_interest_paid': totalInterestPaid,
        'total_amount_collected': totalAmountCollected,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [pledgeId],
    );
  }

  /// Inserts a new pledge that inherits gold/customer details from [old] and is
  /// linked to it through `renewal_parent_id`. Copies the old pledge's items.
  /// Returns the new pledge id. Must be called inside a transaction.
  Future<int> createRenewalPledge(
    DatabaseExecutor txn, {
    required PledgeModel old,
    required String newPledgeNo,
    required double newPrincipal,
    required String now,
    int? createdBy,
    String? startDate,
  }) async {
    final newPledge = old.copyWith(
      id: null,
      pledgeNumber: newPledgeNo,
      pledgeDate: startDate ?? now.substring(0, 10),
      loanAmount: newPrincipal,
      status: 'open',
      source: 'new',
      renewType: null,
      renewSubtype: null,
      closureDate: null,
      closedAt: null,
      totalInterestPaid: 0,
      totalAmountCollected: 0,
      renewalParentId: old.id,
    );
    final map = newPledge.toMap();
    map.remove('id');
    map['created_by'] = createdBy;
    map['created_at'] = now;
    map['updated_at'] = now;
    final newPledgeId = await txn.insert('pledges', map);

    // Copy items.
    final items = await txn
        .query('pledge_items', where: 'pledge_id = ?', whereArgs: [old.id]);
    for (final item in items) {
      final copy = Map<String, dynamic>.from(item);
      copy.remove('id');
      copy['pledge_id'] = newPledgeId;
      copy['created_at'] = now;
      await txn.insert('pledge_items', copy);
    }

    await _advanceNewPledgeCounter(txn, newPledgeNo, now);
    return newPledgeId;
  }

  // ─── Normal closure ──────────────────────────────────────────────────────────

  /// Normal full closure: marks the pledge closed (renew_type = null), records
  /// a LOAN_FULL_CLOSURE ledger entry, and audits the event.
  Future<void> closePledge({
    required int pledgeId,
    required double totalInterestPaid,
    required double totalAmountCollected,
    required double cashAmount,
    required double upiAmount,
    int? createdBy,
    String? contextDate,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    // closed_at carries the context date (so the gold-OUT register attributes
    // the item to that day) but keeps a real time-of-day component.
    final closedAt = contextDate != null
        ? '${contextDate}T${now.substring(11)}'
        : now;
    final paymentDate = contextDate ?? now.substring(0, 10);

    await db.transaction((txn) async {
      await markPledgeClosed(
        txn,
        pledgeId: pledgeId,
        renewType: null,
        renewSubtype: null,
        totalInterestPaid: totalInterestPaid,
        totalAmountCollected: totalAmountCollected,
        closureDate: contextDate,
        closedAt: closedAt,
      );

      await _payments.createLoanFullClosure(
        pledgeId,
        totalAmountCollected,
        cashAmount,
        upiAmount,
        paymentDate,
        notes: 'Closure of pledge',
        createdBy: createdBy,
        txn: txn,
      );

      await _audit.log(
        actionCategory: AuditCategory.pledge,
        action: 'PLEDGE_CLOSED',
        entityType: 'pledges',
        entityId: '$pledgeId',
        createdBy: createdBy,
        txn: txn,
      );
    });

    await _cascadeForContextDate(contextDate);
  }

  // ─── Manual close (legacy/calculator records) ────────────────────────────────

  /// Records a pledge that was opened and closed outside the system (entered via
  /// the interest calculator). Stored as a migrated, already-closed pledge with
  /// a LOAN_FULL_CLOSURE ledger entry.
  Future<void> createManualClosedPledge({
    required String pledgeNumber,
    required String pledgeDate,
    required String closureDate,
    required double principal,
    required double interest,
    required double total,
    required double interestRate,
    required double cashAmount,
    required double upiAmount,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final today = now.substring(0, 10);

    await db.transaction((txn) async {
      final pledgeId = await txn.insert('pledges', {
        'pledge_no': pledgeNumber,
        'start_date': pledgeDate,
        'principal_amount': principal,
        'interest_rate': interestRate,
        'status': 'closed',
        'renew_type': null,
        'renew_subtype': null,
        'closure_date': closureDate,
        'closed_at': now,
        'total_interest_paid': interest,
        'total_amount_collected': total,
        'source': 'migrated',
        'renewal_parent_id': null,
        'gross_weight': 0.0,
        'net_weight': 0.0,
        'pledge_rate': 0.0,
        'gold_rate': 0.0,
        'actual_item_value': 0.0,
        'notes': 'Closed via interest calculator',
        'created_by': null,
        'created_at': now,
        'updated_at': now,
      });

      await _payments.createLoanFullClosure(
        pledgeId,
        total,
        cashAmount,
        upiAmount,
        today,
        notes: 'Manual closure of pledge #$pledgeNumber',
        txn: txn,
      );
    });
  }

  // ─── Renewal / part-payment / loan-increase flows (Step 3) ───────────────────

  /// Shared orchestration for every renewal-style flow: close the old pledge
  /// with the given renew type/subtype, create the successor pledge (copying
  /// gold/customer/items), optionally record a ledger entry, and audit.
  /// In every flow `total_interest_paid = interest` and
  /// `total_amount_collected = oldPrincipal + interest`. Returns the new
  /// pledge number.
  Future<String> _runRenewalFlow({
    required int oldPledgeId,
    required double newPrincipal,
    required double interest,
    required String renewType,
    required String renewSubtype,
    required String auditAction,
    int? createdBy,
    String? contextDate,
    Future<void> Function(
      DatabaseExecutor txn,
      int oldPledgeId,
      int newPledgeId,
      String today,
    )? onPayment,
  }) async {
    final old = await getPledgeById(oldPledgeId);
    if (old == null) throw Exception('Pledge not found');

    final newNo = await nextPledgeNumber();
    final now = DateTime.now().toIso8601String();
    // Old-pledge closure and new-pledge start both attributed to contextDate,
    // and renewal payments land on that day's ledger.
    final closedAt = contextDate != null
        ? '${contextDate}T${now.substring(11)}'
        : now;
    final paymentDate = contextDate ?? now.substring(0, 10);
    final totalAmountCollected = old.loanAmount + interest;

    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await markPledgeClosed(
        txn,
        pledgeId: oldPledgeId,
        renewType: renewType,
        renewSubtype: renewSubtype,
        totalInterestPaid: interest,
        totalAmountCollected: totalAmountCollected,
        closureDate: contextDate,
        closedAt: closedAt,
      );

      final newPledgeId = await createRenewalPledge(
        txn,
        old: old,
        newPledgeNo: newNo,
        newPrincipal: newPrincipal,
        now: now,
        startDate: contextDate,
        createdBy: createdBy,
      );

      if (onPayment != null) {
        await onPayment(txn, oldPledgeId, newPledgeId, paymentDate);
      }

      await _audit.log(
        actionCategory: AuditCategory.pledge,
        action: auditAction,
        entityType: 'pledges',
        entityId: '$oldPledgeId',
        createdBy: createdBy,
        txn: txn,
      );
    });

    await _cascadeForContextDate(contextDate);
    return newNo;
  }

  /// 3D — Renew, pay interest now (collected on the OLD pledge).
  Future<String> renewPayInterest({
    required int oldPledgeId,
    required double newPrincipal,
    required double interest,
    required double cashAmount,
    required double upiAmount,
    int? createdBy,
    String? contextDate,
  }) {
    return _runRenewalFlow(
      oldPledgeId: oldPledgeId,
      newPrincipal: newPrincipal,
      interest: interest,
      renewType: RenewType.renewed,
      renewSubtype: RenewSubtype.interestPaid,
      auditAction: 'PLEDGE_RENEWED',
      createdBy: createdBy,
      contextDate: contextDate,
      onPayment: (txn, oldId, newId, today) =>
          _payments.createRenewalInterestPaid(
              oldId, interest, cashAmount, upiAmount, today,
              createdBy: createdBy, txn: txn),
    );
  }

  /// 3E — Renew, capitalise interest (no cash movement).
  Future<String> renewCapitaliseInterest({
    required int oldPledgeId,
    required double newPrincipal,
    required double interest,
    int? createdBy,
    String? contextDate,
  }) {
    return _runRenewalFlow(
      oldPledgeId: oldPledgeId,
      newPrincipal: newPrincipal,
      interest: interest,
      renewType: RenewType.renewed,
      renewSubtype: RenewSubtype.interestCapitalised,
      auditAction: 'PLEDGE_RENEWED',
      createdBy: createdBy,
      contextDate: contextDate,
    );
  }

  /// 3F — Part payment: principal & interest.
  Future<String> partPaymentPrincipalAndInterest({
    required int oldPledgeId,
    required double newPrincipal,
    required double interest,
    required double totalPaid,
    required double cashAmount,
    required double upiAmount,
    int? createdBy,
    String? contextDate,
  }) {
    return _runRenewalFlow(
      oldPledgeId: oldPledgeId,
      newPrincipal: newPrincipal,
      interest: interest,
      renewType: RenewType.partPayment,
      renewSubtype: RenewSubtype.principalAndInterest,
      auditAction: 'PLEDGE_PART_PAYMENT',
      createdBy: createdBy,
      contextDate: contextDate,
      onPayment: (txn, oldId, newId, today) => _payments.createPartPayment(
          oldId, totalPaid, cashAmount, upiAmount,
          PaymentSubCategory.principalAndInterest, today,
          createdBy: createdBy, txn: txn),
    );
  }

  /// 3G — Part payment: fixed amount inclusive.
  Future<String> partPaymentFixedAmount({
    required int oldPledgeId,
    required double newPrincipal,
    required double interest,
    required double fixedAmount,
    required double cashAmount,
    required double upiAmount,
    int? createdBy,
    String? contextDate,
  }) {
    return _runRenewalFlow(
      oldPledgeId: oldPledgeId,
      newPrincipal: newPrincipal,
      interest: interest,
      renewType: RenewType.partPayment,
      renewSubtype: RenewSubtype.fixedAmountInclusive,
      auditAction: 'PLEDGE_PART_PAYMENT',
      createdBy: createdBy,
      contextDate: contextDate,
      onPayment: (txn, oldId, newId, today) => _payments.createPartPayment(
          oldId, fixedAmount, cashAmount, upiAmount,
          PaymentSubCategory.fixedAmountInclusive, today,
          createdBy: createdBy, txn: txn),
    );
  }

  /// 3H — Increase loan, interest not capitalised. The extra cash disbursed is
  /// recorded on the NEW pledge.
  Future<String> increaseLoanInterestNotCapitalised({
    required int oldPledgeId,
    required double newPrincipal,
    required double interest,
    required double extraCashOut,
    required double cashAmount,
    required double upiAmount,
    int? createdBy,
    String? contextDate,
  }) {
    return _runRenewalFlow(
      oldPledgeId: oldPledgeId,
      newPrincipal: newPrincipal,
      interest: interest,
      renewType: RenewType.loanIncrease,
      renewSubtype: RenewSubtype.interestNotCapitalised,
      auditAction: 'PLEDGE_LOAN_INCREASED',
      createdBy: createdBy,
      contextDate: contextDate,
      onPayment: extraCashOut > 0
          ? (txn, oldId, newId, today) =>
              _payments.createLoanIncreaseDisbursed(
                  newId, extraCashOut, cashAmount, upiAmount,
                  PaymentSubCategory.interestNotCapitalised, today,
                  createdBy: createdBy, txn: txn)
          : null,
    );
  }

  /// 3I — Increase loan, interest capitalised.
  Future<String> increaseLoanInterestCapitalised({
    required int oldPledgeId,
    required double newPrincipal,
    required double interest,
    required double extraCashOut,
    required double cashAmount,
    required double upiAmount,
    int? createdBy,
    String? contextDate,
  }) {
    return _runRenewalFlow(
      oldPledgeId: oldPledgeId,
      newPrincipal: newPrincipal,
      interest: interest,
      renewType: RenewType.loanIncrease,
      renewSubtype: RenewSubtype.loanIncreaseInterestCapitalised,
      auditAction: 'PLEDGE_LOAN_INCREASED',
      createdBy: createdBy,
      contextDate: contextDate,
      onPayment: extraCashOut > 0
          ? (txn, oldId, newId, today) =>
              _payments.createLoanIncreaseDisbursed(
                  newId, extraCashOut, cashAmount, upiAmount,
                  PaymentSubCategory.interestCapitalised, today,
                  createdBy: createdBy, txn: txn)
          : null,
    );
  }

  // ─── Admin edit ──────────────────────────────────────────────────────────────

  /// Admin correction of an existing open pledge. Updates the pledges row,
  /// replaces pledge_items, syncs photo_sync_log, proportionally adjusts the
  /// linked disbursal payment if the principal changed, then cascades
  /// daily_stock (always) and daily_balance (if principal changed).
  Future<void> editPledge({
    required int pledgeId,
    required PledgeModel updatedPledge,
    required List<PledgeItemModel> updatedItems,
    required List<String> newGoldPhotoPaths,
    required List<String> newFormPhotoPaths,
    required double originalPrincipal,
    required String editReason,
    required String oldValueJson,
    required String newValueJson,
    int? createdBy,
    // When provided (new-loan edit path), the payment entry is updated with
    // these exact values. When null (migrated-loan edit path), the split is
    // adjusted proportionally if the principal changed.
    double? newCashAmount,
    double? newUpiAmount,
    // Set to false for migrated-pledge edits: their dates are before
    // app_use_start_date so no daily_stock rows exist for them and the
    // cascade is always a no-op anyway.
    bool cascadeGoldStock = true,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final pledgeDate = updatedPledge.pledgeDate;
    final principalChanged =
        (updatedPledge.loanAmount - originalPrincipal).abs() > 0.01;
    final hasExplicitSplit = newCashAmount != null && newUpiAmount != null;

    await db.transaction((txn) async {
      // 1. UPDATE pledges row
      final updateMap = updatedPledge.toMap();
      updateMap.remove('id');
      updateMap['updated_at'] = now;
      await txn.update('pledges', updateMap,
          where: 'id = ?', whereArgs: [pledgeId]);

      // 2. Replace pledge_items
      await txn.delete('pledge_items',
          where: 'pledge_id = ?', whereArgs: [pledgeId]);
      await _insertItems(txn, pledgeId, updatedItems, now);

      // 3. Sync photo_sync_log
      final existingRows = await txn.query(
        'photo_sync_log',
        where: 'pledge_id = ?',
        whereArgs: [pledgeId],
      );
      final existingPaths =
          existingRows.map((r) => r['local_path'] as String).toSet();
      final newPaths = <String>{...newGoldPhotoPaths, ...newFormPhotoPaths};

      // Remove rows for photos no longer present
      for (final row in existingRows) {
        final path = row['local_path'] as String;
        if (!newPaths.contains(path)) {
          await txn.delete('photo_sync_log',
              where: 'id = ?', whereArgs: [row['id']]);
        }
      }
      // Register newly added gold photos
      for (final path in newGoldPhotoPaths) {
        if (!existingPaths.contains(path)) {
          await PhotoSyncRepository.instance.insertPhoto(
            pledgeId: pledgeId,
            photoType: PhotoType.gold,
            localPath: path,
            txn: txn,
          );
        }
      }
      // Register newly added document photos
      for (final path in newFormPhotoPaths) {
        if (!existingPaths.contains(path)) {
          await PhotoSyncRepository.instance.insertPhoto(
            pledgeId: pledgeId,
            photoType: PhotoType.document,
            localPath: path,
            txn: txn,
          );
        }
      }

      // 4. Update disbursal payment: exact values (new-loan edit) or
      //    proportional rescaling (migrated-loan edit when principal changed).
      if (principalChanged || hasExplicitSplit) {
        final payRows = await txn.query(
          'payments',
          where: 'pledge_id = ? AND payment_type IN (?, ?)',
          whereArgs: [
            pledgeId,
            PaymentType.loanDisbursed,
            PaymentType.loanIncreaseDisbursed,
          ],
          orderBy: 'created_at ASC',
          limit: 1,
        );
        if (payRows.isNotEmpty) {
          final double finalCash, finalUpi, finalAmt;
          if (hasExplicitSplit) {
            finalCash = newCashAmount;
            finalUpi = newUpiAmount;
            finalAmt = finalCash + finalUpi;
          } else {
            // Proportional rescaling for migrated-loan edit path.
            final oldAmt = (payRows.first['amount'] as num?)?.toDouble() ??
                originalPrincipal;
            final oldCash =
                (payRows.first['cash_amount'] as num?)?.toDouble() ?? oldAmt;
            final oldUpi =
                (payRows.first['upi_amount'] as num?)?.toDouble() ?? 0.0;
            final newAmt = updatedPledge.loanAmount;
            double scaledCash, scaledUpi;
            if (oldAmt > 0) {
              scaledCash = double.parse(
                  ((oldCash / oldAmt) * newAmt).toStringAsFixed(2));
              scaledUpi = double.parse(
                  ((oldUpi / oldAmt) * newAmt).toStringAsFixed(2));
              scaledCash += newAmt - scaledCash - scaledUpi;
            } else {
              scaledCash = newAmt;
              scaledUpi = 0;
            }
            finalCash = scaledCash;
            finalUpi = scaledUpi;
            finalAmt = newAmt;
          }
          await txn.update(
            'payments',
            {
              'amount': finalAmt,
              'cash_amount': finalCash,
              'upi_amount': finalUpi,
            },
            where: 'id = ?',
            whereArgs: [payRows.first['id']],
          );
        }
      }

      // 5. Audit log
      await _audit.log(
        actionCategory: AuditCategory.admin,
        action: 'PLEDGE_EDITED',
        entityType: 'pledges',
        entityId: '$pledgeId',
        oldValueJson: oldValueJson,
        newValueJson: newValueJson,
        reason: editReason,
        createdBy: createdBy,
        txn: txn,
      );
    });

    // 6. Cascade recalculations. Gold stock skipped when cascadeGoldStock is
    //    false (migrated pledges whose dates predate daily_stock coverage).
    //    Daily balance cascades whenever the payment entry was touched.
    if (cascadeGoldStock) {
      await GoldStockRepository.instance.cascadeFrom(pledgeDate);
    }
    if (principalChanged || hasExplicitSplit) {
      await DailyBalanceRepository.instance.cascadeFrom(pledgeDate);
    }
  }
}
