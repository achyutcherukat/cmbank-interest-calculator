import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings_repository.dart';
import '../../admin/data/audit_log_repository.dart';
import 'gold_rates_repository.dart';
import 'stock_adjustments_repository.dart';

// ─── Data classes ──────────────────────────────────────────────────────────────

class DailyStockRecord {
  const DailyStockRecord({
    this.stockId,
    required this.stockDate,
    required this.openingWeight,
    required this.openingGrossWeight,
    required this.openingCount,
    required this.goldInWeight,
    required this.goldInGrossWeight,
    required this.goldInCount,
    required this.goldOutWeight,
    required this.goldOutGrossWeight,
    required this.goldOutCount,
    required this.adjustmentWeight,
    required this.adjustmentGrossWeight,
    required this.adjustmentCount,
    required this.closingWeight,
    required this.closingGrossWeight,
    required this.closingCount,
    required this.isLocked,
    this.lockedAt,
    this.lockedBy,
    this.discrepancyNote,
    this.unlockedBy,
    this.unlockReason,
    this.unlockedAt,
  });

  final int? stockId;
  final String stockDate;
  final double openingWeight;
  final double openingGrossWeight;
  final int openingCount;
  final double goldInWeight;
  final double goldInGrossWeight;
  final int goldInCount;
  final double goldOutWeight;
  final double goldOutGrossWeight;
  final int goldOutCount;
  final double adjustmentWeight;
  final double adjustmentGrossWeight;
  final int adjustmentCount;
  final double closingWeight;
  final double closingGrossWeight;
  final int closingCount;
  final bool isLocked;
  final String? lockedAt;
  final int? lockedBy;
  final String? discrepancyNote;
  final int? unlockedBy;
  final String? unlockReason;
  final String? unlockedAt;

  bool get hasDiscrepancy =>
      discrepancyNote != null && discrepancyNote!.isNotEmpty;
}

class GoldMovementEntry {
  const GoldMovementEntry({
    required this.pledgeId,
    required this.pledgeNumber,
    required this.itemType,
    required this.purity,
    required this.netWeight,
    required this.time,
    this.closureType,
  });

  final int pledgeId;
  final String pledgeNumber;
  final String itemType;
  final String purity;
  final double netWeight;
  final String time;
  final String? closureType; // renew_type, or 'CLOSED' for a normal closure
}

class PurityStock {
  const PurityStock({
    required this.purity,
    required this.grams,
    required this.count,
  });
  final String purity;
  final double grams;
  final int count;
}

/// Pledge-level Gold IN / OUT entry — all pledge_items aggregated per pledge.
class GoldPledgeEntry {
  const GoldPledgeEntry({
    required this.pledgeId,
    required this.pledgeNumber,
    required this.itemCount,
    required this.principal,
    required this.netWeight,
    required this.grossWeight,
    required this.purities,
    this.interest,
    this.renewType,
    this.renewSubtype,
  });

  final int pledgeId;
  final String pledgeNumber;
  final int itemCount;       // SUM(pi.quantity)
  final double principal;    // pledges.principal_amount
  final double netWeight;    // SUM(pi.net_weight)
  final double grossWeight;  // SUM(pi.gross_weight)
  final List<String> purities; // DISTINCT non-empty purity values
  final double? interest;    // pledges.total_interest_paid (OUT only)
  final String? renewType;   // pledges.renew_type (OUT only)
  final String? renewSubtype; // pledges.renew_subtype (OUT only)
}

// ─── Repository ────────────────────────────────────────────────────────────────

class GoldStockRepository {
  GoldStockRepository._();
  static final GoldStockRepository instance = GoldStockRepository._();

  final _settingsRepo = AppSettingsRepository();
  final _adjustments = StockAdjustmentsRepository.instance;
  final _audit = AuditLogRepository.instance;

  // ─── Get or create ─────────────────────────────────────────────────────────

  Future<DailyStockRecord> getOrCreateDayRecord(String date) async {
    final db = await AppDatabase.instance.database;

    final existing = await db.query(
      'daily_stock',
      where: 'stock_date = ?',
      whereArgs: [date],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      if ((row['is_locked'] as int?) == 1) return _fromMap(row);
      return _refreshUnlocked(db, row, date);
    }

    return _createRecord(db, date);
  }

  Future<DailyStockRecord> _refreshUnlocked(
    Database db,
    Map<String, dynamic> row,
    String date,
  ) async {
    final opening = await _previousDayClosing(db, date);
    final goldIn = await _computeGoldIn(db, date);
    final goldOut = await _computeGoldOut(db, date);
    final adj = await _adjustments.getTotalAdjustmentForDate(date);

    final closingWeight =
        opening.netWeight + goldIn.netWeight - goldOut.netWeight + adj.weight;
    final closingGrossWeight =
        opening.grossWeight + goldIn.grossWeight - goldOut.grossWeight;
    final closingCount =
        opening.count + goldIn.count - goldOut.count + adj.count;
    final safeClosing = closingWeight < 0 ? 0.0 : closingWeight;
    final safeClosingGross = closingGrossWeight < 0 ? 0.0 : closingGrossWeight;
    final safeClosingCount = closingCount < 0 ? 0 : closingCount;

    final now = DateTime.now().toIso8601String();
    await db.update(
      'daily_stock',
      {
        'opening_weight': opening.netWeight,
        'opening_gross_weight': opening.grossWeight,
        'opening_count': opening.count,
        'gold_in_weight': goldIn.netWeight,
        'gold_in_gross_weight': goldIn.grossWeight,
        'gold_in_count': goldIn.count,
        'gold_out_weight': goldOut.netWeight,
        'gold_out_gross_weight': goldOut.grossWeight,
        'gold_out_count': goldOut.count,
        'adjustment_weight': adj.weight,
        'adjustment_gross_weight': 0.0,
        'adjustment_count': adj.count,
        'closing_weight': safeClosing,
        'closing_gross_weight': safeClosingGross,
        'closing_count': safeClosingCount,
        'updated_at': now,
      },
      where: 'stock_date = ?',
      whereArgs: [date],
    );

    return DailyStockRecord(
      stockId: row['id'] as int?,
      stockDate: date,
      openingWeight: opening.netWeight,
      openingGrossWeight: opening.grossWeight,
      openingCount: opening.count,
      goldInWeight: goldIn.netWeight,
      goldInGrossWeight: goldIn.grossWeight,
      goldInCount: goldIn.count,
      goldOutWeight: goldOut.netWeight,
      goldOutGrossWeight: goldOut.grossWeight,
      goldOutCount: goldOut.count,
      adjustmentWeight: adj.weight,
      adjustmentGrossWeight: 0.0,
      adjustmentCount: adj.count,
      closingWeight: safeClosing,
      closingGrossWeight: safeClosingGross,
      closingCount: safeClosingCount,
      isLocked: false,
      lockedAt: row['locked_at'] as String?,
      lockedBy: row['locked_by'] as int?,
      discrepancyNote: row['discrepancy_note'] as String?,
      unlockedBy: row['unlocked_by'] as int?,
      unlockReason: row['unlock_reason'] as String?,
      unlockedAt: row['unlocked_at'] as String?,
    );
  }

  Future<DailyStockRecord> _createRecord(Database db, String date) async {
    final opening = await _previousDayClosing(db, date);
    final goldIn = await _computeGoldIn(db, date);
    final goldOut = await _computeGoldOut(db, date);
    final adj = await _adjustments.getTotalAdjustmentForDate(date);

    final closingWeight =
        opening.netWeight + goldIn.netWeight - goldOut.netWeight + adj.weight;
    final closingGrossWeight =
        opening.grossWeight + goldIn.grossWeight - goldOut.grossWeight;
    final closingCount =
        opening.count + goldIn.count - goldOut.count + adj.count;
    final safeClosing = closingWeight < 0 ? 0.0 : closingWeight;
    final safeClosingGross = closingGrossWeight < 0 ? 0.0 : closingGrossWeight;
    final safeClosingCount = closingCount < 0 ? 0 : closingCount;

    final now = DateTime.now().toIso8601String();
    final id = await db.insert('daily_stock', {
      'stock_date': date,
      'opening_weight': opening.netWeight,
      'opening_gross_weight': opening.grossWeight,
      'opening_count': opening.count,
      'gold_in_weight': goldIn.netWeight,
      'gold_in_gross_weight': goldIn.grossWeight,
      'gold_in_count': goldIn.count,
      'gold_out_weight': goldOut.netWeight,
      'gold_out_gross_weight': goldOut.grossWeight,
      'gold_out_count': goldOut.count,
      'adjustment_weight': adj.weight,
      'adjustment_gross_weight': 0.0,
      'adjustment_count': adj.count,
      'closing_weight': safeClosing,
      'closing_gross_weight': safeClosingGross,
      'closing_count': safeClosingCount,
      'is_locked': 0,
      'created_at': now,
      'updated_at': now,
    });

    return DailyStockRecord(
      stockId: id,
      stockDate: date,
      openingWeight: opening.netWeight,
      openingGrossWeight: opening.grossWeight,
      openingCount: opening.count,
      goldInWeight: goldIn.netWeight,
      goldInGrossWeight: goldIn.grossWeight,
      goldInCount: goldIn.count,
      goldOutWeight: goldOut.netWeight,
      goldOutGrossWeight: goldOut.grossWeight,
      goldOutCount: goldOut.count,
      adjustmentWeight: adj.weight,
      adjustmentGrossWeight: 0.0,
      adjustmentCount: adj.count,
      closingWeight: safeClosing,
      closingGrossWeight: safeClosingGross,
      closingCount: safeClosingCount,
      isLocked: false,
    );
  }

  // ─── Opening stock ─────────────────────────────────────────────────────────

  Future<({double grossWeight, double netWeight, int count})>
      _previousDayClosing(
    Database db,
    String date,
  ) async {
    final rows = await db.rawQuery('''
      SELECT closing_weight, closing_gross_weight, closing_count
      FROM daily_stock
      WHERE stock_date < ?
      ORDER BY stock_date DESC
      LIMIT 1
    ''', [date]);

    if (rows.isNotEmpty) {
      return (
        grossWeight:
            (rows.first['closing_gross_weight'] as num?)?.toDouble() ?? 0,
        netWeight: (rows.first['closing_weight'] as num?)?.toDouble() ?? 0,
        count: (rows.first['closing_count'] as int?) ?? 0,
      );
    }

    final grossStr =
        await _settingsRepo.getString('opening_stock_gross_weight');
    final netStr = await _settingsRepo.getString('opening_stock_net_weight');
    return (
      grossWeight: double.tryParse(grossStr ?? '') ?? 0,
      netWeight: double.tryParse(netStr ?? '') ?? 0,
      count: 0,
    );
  }

  // ─── Gold IN computation (new pledges created on date) ───────────────────────

  Future<({double grossWeight, double netWeight, int count})> _computeGoldIn(
    Database db,
    String date,
  ) async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(pi.gross_weight), 0) AS gw,
             COALESCE(SUM(pi.net_weight), 0) AS w,
             COUNT(pi.id) AS c
      FROM pledge_items pi
      JOIN pledges p ON pi.pledge_id = p.id
      WHERE DATE(p.start_date) = ? AND p.source = 'new'
    ''', [date]);
    return (
      grossWeight: (rows.first['gw'] as num?)?.toDouble() ?? 0,
      netWeight: (rows.first['w'] as num?)?.toDouble() ?? 0,
      count: (rows.first['c'] as int?) ?? 0,
    );
  }

  // ─── Gold OUT computation (pledges closed on date) ───────────────────────────

  Future<({double grossWeight, double netWeight, int count})> _computeGoldOut(
    Database db,
    String date,
  ) async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(pi.gross_weight), 0) AS gw,
             COALESCE(SUM(pi.net_weight), 0) AS w,
             COUNT(pi.id) AS c
      FROM pledge_items pi
      JOIN pledges p ON pi.pledge_id = p.id
      WHERE DATE(p.closed_at) = ? AND p.status = 'closed'
    ''', [date]);
    return (
      grossWeight: (rows.first['gw'] as num?)?.toDouble() ?? 0,
      netWeight: (rows.first['w'] as num?)?.toDouble() ?? 0,
      count: (rows.first['c'] as int?) ?? 0,
    );
  }

  // ─── Drill-down entries ────────────────────────────────────────────────────

  Future<List<GoldMovementEntry>> getGoldInEntries(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS pledge_id, p.pledge_no, p.start_date,
             pi.item_type, pi.purity AS item_purity, pi.net_weight AS item_net
      FROM pledges p
      JOIN pledge_items pi ON pi.pledge_id = p.id
      WHERE DATE(p.start_date) = ? AND p.source = 'new'
      ORDER BY p.start_date ASC, pi.id ASC
    ''', [date]);

    return rows
        .map((row) => GoldMovementEntry(
              pledgeId: row['pledge_id'] as int,
              pledgeNumber: row['pledge_no'] as String? ?? '',
              itemType: row['item_type'] as String? ?? 'Other',
              purity: (row['item_purity'] as String?) ?? '',
              netWeight: (row['item_net'] as num?)?.toDouble() ?? 0,
              time: _extractTime(row['start_date'] as String?),
            ))
        .toList();
  }

  Future<List<GoldMovementEntry>> getGoldOutEntries(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS pledge_id, p.pledge_no, p.closed_at, p.renew_type,
             pi.item_type, pi.purity AS item_purity, pi.net_weight AS item_net
      FROM pledges p
      JOIN pledge_items pi ON pi.pledge_id = p.id
      WHERE DATE(p.closed_at) = ? AND p.status = 'closed'
      ORDER BY p.closed_at ASC, pi.id ASC
    ''', [date]);

    return rows
        .map((row) => GoldMovementEntry(
              pledgeId: row['pledge_id'] as int,
              pledgeNumber: row['pledge_no'] as String? ?? '',
              itemType: row['item_type'] as String? ?? 'Other',
              purity: (row['item_purity'] as String?) ?? '',
              netWeight: (row['item_net'] as num?)?.toDouble() ?? 0,
              time: _extractTime(row['closed_at'] as String?),
              closureType: (row['renew_type'] as String?) ?? 'CLOSED',
            ))
        .toList();
  }

  // ─── Pledge-level drill-down entries ──────────────────────────────────────

  /// One [GoldPledgeEntry] per pledge opened on [date], with all items
  /// aggregated (quantity sum, weight sum, distinct purities).
  Future<List<GoldPledgeEntry>> getGoldInPledges(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS pledge_id,
             p.pledge_no,
             p.principal_amount,
             COALESCE(SUM(pi.quantity), 0)     AS item_count,
             COALESCE(SUM(pi.net_weight), 0.0)   AS net_weight,
             COALESCE(SUM(pi.gross_weight), 0.0) AS gross_weight,
             GROUP_CONCAT(DISTINCT
               CASE WHEN TRIM(COALESCE(pi.purity,'')) != ''
                    THEN pi.purity ELSE NULL END
             ) AS purities
      FROM pledges p
      LEFT JOIN pledge_items pi ON pi.pledge_id = p.id
      WHERE DATE(p.start_date) = ? AND p.source = 'new'
      GROUP BY p.id
      ORDER BY p.start_date ASC
    ''', [date]);

    return rows
        .map((r) => GoldPledgeEntry(
              pledgeId: r['pledge_id'] as int,
              pledgeNumber: r['pledge_no'] as String? ?? '',
              itemCount: (r['item_count'] as num?)?.toInt() ?? 0,
              principal: (r['principal_amount'] as num?)?.toDouble() ?? 0,
              netWeight: (r['net_weight'] as num?)?.toDouble() ?? 0,
              grossWeight: (r['gross_weight'] as num?)?.toDouble() ?? 0,
              purities: _splitPurities(r['purities'] as String?),
            ))
        .toList();
  }

  /// One [GoldPledgeEntry] per pledge closed on [date], with all items
  /// aggregated and [interest] (total_interest_paid) included.
  Future<List<GoldPledgeEntry>> getGoldOutPledges(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS pledge_id,
             p.pledge_no,
             p.principal_amount,
             p.total_interest_paid,
             p.renew_type,
             p.renew_subtype,
             COALESCE(SUM(pi.quantity), 0)     AS item_count,
             COALESCE(SUM(pi.net_weight), 0.0)   AS net_weight,
             COALESCE(SUM(pi.gross_weight), 0.0) AS gross_weight,
             GROUP_CONCAT(DISTINCT
               CASE WHEN TRIM(COALESCE(pi.purity,'')) != ''
                    THEN pi.purity ELSE NULL END
             ) AS purities
      FROM pledges p
      LEFT JOIN pledge_items pi ON pi.pledge_id = p.id
      WHERE DATE(p.closed_at) = ? AND p.status = 'closed'
      GROUP BY p.id
      ORDER BY p.closed_at ASC
    ''', [date]);

    return rows
        .map((r) => GoldPledgeEntry(
              pledgeId: r['pledge_id'] as int,
              pledgeNumber: r['pledge_no'] as String? ?? '',
              itemCount: (r['item_count'] as num?)?.toInt() ?? 0,
              principal: (r['principal_amount'] as num?)?.toDouble() ?? 0,
              netWeight: (r['net_weight'] as num?)?.toDouble() ?? 0,
              grossWeight: (r['gross_weight'] as num?)?.toDouble() ?? 0,
              purities: _splitPurities(r['purities'] as String?),
              interest: (r['total_interest_paid'] as num?)?.toDouble(),
              renewType: r['renew_type'] as String?,
              renewSubtype: r['renew_subtype'] as String?,
            ))
        .toList();
  }

  static List<String> _splitPurities(String? csv) {
    if (csv == null || csv.isEmpty) return const [];
    return csv
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ─── Purity breakdown (current open stock) ─────────────────────────────────

  Future<List<PurityStock>> getPurityBreakdown() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT pi.purity,
             SUM(pi.net_weight) AS total_weight,
             COUNT(pi.id) AS item_count
      FROM pledge_items pi
      JOIN pledges p ON p.id = pi.pledge_id
      WHERE p.status = 'open'
        AND pi.net_weight > 0
      GROUP BY pi.purity
      ORDER BY total_weight DESC
    ''');

    return rows
        .map((row) => PurityStock(
              purity: (row['purity'] as String?)?.isNotEmpty == true
                  ? row['purity'] as String
                  : '—',
              grams: (row['total_weight'] as num?)?.toDouble() ?? 0,
              count: (row['item_count'] as int?) ?? 0,
            ))
        .toList();
  }

  // ─── Adjust stock ──────────────────────────────────────────────────────────

  /// Records a manual stock adjustment in the `stock_adjustments` table. The
  /// day record is recomputed on next load.
  Future<void> adjustStock({
    required String date,
    required double weight,
    required int count,
    required String reason,
    required bool isAdd,
    int? userId,
  }) async {
    final sign = isAdd ? 1.0 : -1.0;
    final signedWeight = weight * sign;
    final signedCount = (count * sign).round();

    await _adjustments.addAdjustment(
      date: date,
      weight: signedWeight,
      count: signedCount,
      reason: reason,
      userId: userId,
    );

    // Refresh the cached day record.
    await getOrCreateDayRecord(date);

    await _audit.log(
      actionCategory: AuditCategory.dayManagement,
      action: 'STOCK_ADJUSTED',
      entityType: 'daily_stock',
      entityId: date,
      newValueJson: '{"weight":$signedWeight,"count":$signedCount}',
      reason: reason,
      createdBy: userId,
    );
  }

  // ─── Verify and lock ───────────────────────────────────────────────────────

  Future<void> verifyAndLock({
    required String date,
    required double actualGrossWeight,
    required double actualWeight,
    String? discrepancyNote,
    int? lockedBy,
  }) async {
    // Make sure stored values reflect the latest computation before locking.
    await getOrCreateDayRecord(date);

    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.update(
      'daily_stock',
      {
        'is_locked': 1,
        'locked_at': now,
        'locked_by': lockedBy,
        'discrepancy_note': discrepancyNote,
        'updated_at': now,
      },
      where: 'stock_date = ?',
      whereArgs: [date],
    );

    await _audit.log(
      actionCategory: AuditCategory.dayManagement,
      action: 'STOCK_LOCKED',
      entityType: 'daily_stock',
      entityId: date,
      newValueJson:
          '{"actual_gross_weight":$actualGrossWeight,"actual_net_weight":$actualWeight}',
      reason: discrepancyNote ?? 'Stock verified',
      createdBy: lockedBy,
    );
  }

  // ─── Unlock (admin only) ───────────────────────────────────────────────────

  Future<void> unlockDay({
    required String date,
    required String reason,
    int? unlockedBy,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.update(
      'daily_stock',
      {
        'is_locked': 0,
        'unlocked_by': unlockedBy,
        'unlock_reason': reason,
        'unlocked_at': now,
        'updated_at': now,
      },
      where: 'stock_date = ?',
      whereArgs: [date],
    );

    await _audit.log(
      actionCategory: AuditCategory.dayManagement,
      action: 'STOCK_UNLOCKED',
      entityType: 'daily_stock',
      entityId: date,
      reason: reason,
      createdBy: unlockedBy,
    );
  }

  // ─── Lock check & cascade (backdated entries) ───────────────────────────────

  /// Returns the earliest stock_date in daily_stock, or null if no records exist.
  Future<String?> getFirstStockDate() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'daily_stock',
      columns: ['stock_date'],
      orderBy: 'stock_date ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['stock_date'] as String;
  }

  /// Returns the stored record for [date] without recomputing, or null if no
  /// row exists. Used for lock-guard checks where only stored state matters.
  Future<DailyStockRecord?> getForDate(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'daily_stock',
      where: 'stock_date = ?',
      whereArgs: [date],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromMap(rows.first);
  }

  /// True only if a `daily_stock` record exists for [date] and is locked.
  /// A missing record means the register has not been opened/locked yet, so
  /// backdated entries are allowed.
  Future<bool> isDateLocked(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'daily_stock',
      columns: ['is_locked'],
      where: 'stock_date = ?',
      whereArgs: [date],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return (rows.first['is_locked'] as int?) == 1;
  }

  /// Recomputes the stock record for [date] (creating it if needed) and every
  /// following day that is still unlocked, so a backdated gold IN/OUT ripples
  /// forward. Stops at the first locked day. Each day's record is recomputed
  /// from source (pledges/adjustments) and the previous day's stored closing,
  /// so processing in ascending order keeps the chain consistent.
  Future<void> cascadeFrom(String date) async {
    await getOrCreateDayRecord(date);
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'daily_stock',
      columns: ['stock_date', 'is_locked'],
      where: 'stock_date > ?',
      whereArgs: [date],
      orderBy: 'stock_date ASC',
    );
    for (final r in rows) {
      if ((r['is_locked'] as int?) == 1) break;
      await getOrCreateDayRecord(r['stock_date'] as String);
    }
  }

  // ─── Gold rate ─────────────────────────────────────────────────────────────

  Future<double> getGoldRate() async {
    final rates = await GoldRatesRepository.instance.getCurrentRates();
    return rates?.goldRate ?? 0;
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  DailyStockRecord _fromMap(Map<String, dynamic> row) {
    return DailyStockRecord(
      stockId: row['id'] as int?,
      stockDate: row['stock_date'] as String? ?? '',
      openingWeight: (row['opening_weight'] as num?)?.toDouble() ?? 0,
      openingGrossWeight:
          (row['opening_gross_weight'] as num?)?.toDouble() ?? 0,
      openingCount: (row['opening_count'] as int?) ?? 0,
      goldInWeight: (row['gold_in_weight'] as num?)?.toDouble() ?? 0,
      goldInGrossWeight:
          (row['gold_in_gross_weight'] as num?)?.toDouble() ?? 0,
      goldInCount: (row['gold_in_count'] as int?) ?? 0,
      goldOutWeight: (row['gold_out_weight'] as num?)?.toDouble() ?? 0,
      goldOutGrossWeight:
          (row['gold_out_gross_weight'] as num?)?.toDouble() ?? 0,
      goldOutCount: (row['gold_out_count'] as int?) ?? 0,
      adjustmentWeight: (row['adjustment_weight'] as num?)?.toDouble() ?? 0,
      adjustmentGrossWeight:
          (row['adjustment_gross_weight'] as num?)?.toDouble() ?? 0,
      adjustmentCount: (row['adjustment_count'] as int?) ?? 0,
      closingWeight: (row['closing_weight'] as num?)?.toDouble() ?? 0,
      closingGrossWeight:
          (row['closing_gross_weight'] as num?)?.toDouble() ?? 0,
      closingCount: (row['closing_count'] as int?) ?? 0,
      isLocked: (row['is_locked'] as int?) == 1,
      lockedAt: row['locked_at'] as String?,
      lockedBy: row['locked_by'] as int?,
      discrepancyNote: row['discrepancy_note'] as String?,
      unlockedBy: row['unlocked_by'] as int?,
      unlockReason: row['unlock_reason'] as String?,
      unlockedAt: row['unlocked_at'] as String?,
    );
  }

  String _extractTime(String? iso) {
    if (iso == null || iso.length < 16) return '--:--';
    final parts = iso.split('T');
    if (parts.length < 2) return '--:--';
    return parts[1].substring(0, 5);
  }
}
