import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings_repository.dart';

// ─── Data classes ──────────────────────────────────────────────────────────────

class DailyStockRecord {
  const DailyStockRecord({
    this.stockId,
    required this.stockDate,
    required this.openingWeight,
    required this.openingCount,
    required this.goldInWeight,
    required this.goldInCount,
    required this.goldOutWeight,
    required this.goldOutCount,
    required this.adjustmentWeight,
    required this.adjustmentCount,
    required this.closingWeight,
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
  final int openingCount;
  final double goldInWeight;
  final int goldInCount;
  final double goldOutWeight;
  final int goldOutCount;
  final double adjustmentWeight;
  final int adjustmentCount;
  final double closingWeight;
  final int closingCount;
  final bool isLocked;
  final String? lockedAt;
  final String? lockedBy;
  final String? discrepancyNote;
  final String? unlockedBy;
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
  final String? closureType;
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

// ─── Repository ────────────────────────────────────────────────────────────────

class GoldStockRepository {
  GoldStockRepository._();
  static final GoldStockRepository instance = GoldStockRepository._();

  final _settingsRepo = AppSettingsRepository();

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
    final adjWeight = (row['adjustment_weight'] as num?)?.toDouble() ?? 0;
    final adjCount = (row['adjustment_count'] as int?) ?? 0;

    final closingWeight = opening.weight + goldIn.weight - goldOut.weight + adjWeight;
    final closingCount = opening.count + goldIn.count - goldOut.count + adjCount;
    final safeClosing = closingWeight < 0 ? 0.0 : closingWeight;
    final safeClosingCount = closingCount < 0 ? 0 : closingCount;

    final now = DateTime.now().toIso8601String();
    await db.update(
      'daily_stock',
      {
        'opening_weight': opening.weight,
        'opening_count': opening.count,
        'gold_in_weight': goldIn.weight,
        'gold_in_count': goldIn.count,
        'gold_out_weight': goldOut.weight,
        'gold_out_count': goldOut.count,
        'closing_weight': safeClosing,
        'closing_count': safeClosingCount,
        'updated_at': now,
      },
      where: 'stock_date = ?',
      whereArgs: [date],
    );

    return DailyStockRecord(
      stockId: row['stock_id'] as int?,
      stockDate: date,
      openingWeight: opening.weight,
      openingCount: opening.count,
      goldInWeight: goldIn.weight,
      goldInCount: goldIn.count,
      goldOutWeight: goldOut.weight,
      goldOutCount: goldOut.count,
      adjustmentWeight: adjWeight,
      adjustmentCount: adjCount,
      closingWeight: safeClosing,
      closingCount: safeClosingCount,
      isLocked: false,
      lockedAt: row['locked_at'] as String?,
      lockedBy: row['locked_by'] as String?,
      discrepancyNote: row['discrepancy_note'] as String?,
      unlockedBy: row['unlocked_by'] as String?,
      unlockReason: row['unlock_reason'] as String?,
      unlockedAt: row['unlocked_at'] as String?,
    );
  }

  Future<DailyStockRecord> _createRecord(Database db, String date) async {
    final opening = await _previousDayClosing(db, date);
    final goldIn = await _computeGoldIn(db, date);
    final goldOut = await _computeGoldOut(db, date);

    final closingWeight = opening.weight + goldIn.weight - goldOut.weight;
    final closingCount = opening.count + goldIn.count - goldOut.count;
    final safeClosing = closingWeight < 0 ? 0.0 : closingWeight;
    final safeClosingCount = closingCount < 0 ? 0 : closingCount;

    final now = DateTime.now().toIso8601String();
    final id = await db.insert('daily_stock', {
      'stock_date': date,
      'opening_weight': opening.weight,
      'opening_count': opening.count,
      'gold_in_weight': goldIn.weight,
      'gold_in_count': goldIn.count,
      'gold_out_weight': goldOut.weight,
      'gold_out_count': goldOut.count,
      'adjustment_weight': 0.0,
      'adjustment_count': 0,
      'closing_weight': safeClosing,
      'closing_count': safeClosingCount,
      'is_locked': 0,
      'locked_at': null,
      'locked_by': null,
      'discrepancy_note': null,
      'unlocked_by': null,
      'unlock_reason': null,
      'unlocked_at': null,
      'created_at': now,
      'updated_at': now,
    });

    return DailyStockRecord(
      stockId: id,
      stockDate: date,
      openingWeight: opening.weight,
      openingCount: opening.count,
      goldInWeight: goldIn.weight,
      goldInCount: goldIn.count,
      goldOutWeight: goldOut.weight,
      goldOutCount: goldOut.count,
      adjustmentWeight: 0,
      adjustmentCount: 0,
      closingWeight: safeClosing,
      closingCount: safeClosingCount,
      isLocked: false,
    );
  }

  // ─── Opening stock ─────────────────────────────────────────────────────────

  Future<({double weight, int count})> _previousDayClosing(
    Database db,
    String date,
  ) async {
    final rows = await db.rawQuery('''
      SELECT closing_weight, closing_count
      FROM daily_stock
      WHERE stock_date < ?
      ORDER BY stock_date DESC
      LIMIT 1
    ''', [date]);

    if (rows.isNotEmpty) {
      return (
        weight: (rows.first['closing_weight'] as num?)?.toDouble() ?? 0,
        count: (rows.first['closing_count'] as int?) ?? 0,
      );
    }

    final weightStr = await _settingsRepo.getString('opening_stock_weight');
    final countStr = await _settingsRepo.getString('opening_stock_count');
    return (
      weight: double.tryParse(weightStr ?? '') ?? 0,
      count: int.tryParse(countStr ?? '') ?? 0,
    );
  }

  // ─── Gold IN computation ───────────────────────────────────────────────────

  Future<({double weight, int count})> _computeGoldIn(
    Database db,
    String date,
  ) async {
    final rows = await db.rawQuery('''
      SELECT p.id, p.net_weight AS pledge_net,
             COALESCE(SUM(pi.net_weight), 0) AS item_weight,
             COUNT(pi.id) AS item_count
      FROM pledges p
      LEFT JOIN pledge_items pi ON pi.pledge_id = p.id
      WHERE DATE(p.created_at) = ?
        AND (p.source IS NULL OR p.source != 'manual')
      GROUP BY p.id
    ''', [date]);

    double totalWeight = 0;
    int totalCount = 0;
    for (final row in rows) {
      final itemCount = (row['item_count'] as int?) ?? 0;
      if (itemCount > 0) {
        totalWeight += (row['item_weight'] as num?)?.toDouble() ?? 0;
        totalCount += itemCount;
      } else {
        totalWeight += (row['pledge_net'] as num?)?.toDouble() ?? 0;
        totalCount += 1;
      }
    }
    return (weight: totalWeight, count: totalCount);
  }

  // ─── Gold OUT computation ──────────────────────────────────────────────────

  Future<({double weight, int count})> _computeGoldOut(
    Database db,
    String date,
  ) async {
    final rows = await db.rawQuery('''
      SELECT p.id, p.net_weight AS pledge_net,
             COALESCE(SUM(pi.net_weight), 0) AS item_weight,
             COUNT(pi.id) AS item_count
      FROM pledges p
      LEFT JOIN pledge_items pi ON pi.pledge_id = p.id
      WHERE p.closure_date = ?
        AND p.status IN ('closed', 'renewed')
      GROUP BY p.id
    ''', [date]);

    double totalWeight = 0;
    int totalCount = 0;
    for (final row in rows) {
      final itemCount = (row['item_count'] as int?) ?? 0;
      if (itemCount > 0) {
        totalWeight += (row['item_weight'] as num?)?.toDouble() ?? 0;
        totalCount += itemCount;
      } else {
        totalWeight += (row['pledge_net'] as num?)?.toDouble() ?? 0;
        totalCount += 1;
      }
    }
    return (weight: totalWeight, count: totalCount);
  }

  // ─── Drill-down entries ────────────────────────────────────────────────────

  Future<List<GoldMovementEntry>> getGoldInEntries(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS pledge_id, p.pledge_no, p.created_at,
             p.net_weight AS pledge_net, p.purity AS pledge_purity,
             pi.id AS item_id, pi.item_type, pi.purity AS item_purity,
             pi.net_weight AS item_net
      FROM pledges p
      LEFT JOIN pledge_items pi ON pi.pledge_id = p.id
      WHERE DATE(p.created_at) = ?
        AND (p.source IS NULL OR p.source != 'manual')
      ORDER BY p.created_at ASC, pi.id ASC
    ''', [date]);

    return _buildEntries(rows, forGoldOut: false);
  }

  Future<List<GoldMovementEntry>> getGoldOutEntries(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS pledge_id, p.pledge_no, p.closed_at, p.status,
             p.net_weight AS pledge_net, p.purity AS pledge_purity,
             pi.id AS item_id, pi.item_type, pi.purity AS item_purity,
             pi.net_weight AS item_net
      FROM pledges p
      LEFT JOIN pledge_items pi ON pi.pledge_id = p.id
      WHERE p.closure_date = ?
        AND p.status IN ('closed', 'renewed')
      ORDER BY p.closed_at ASC, pi.id ASC
    ''', [date]);

    return _buildEntries(rows, forGoldOut: true);
  }

  List<GoldMovementEntry> _buildEntries(
    List<Map<String, dynamic>> rows, {
    required bool forGoldOut,
  }) {
    final entries = <GoldMovementEntry>[];
    final seenPledges = <int>{};

    for (final row in rows) {
      final pledgeId = row['pledge_id'] as int;
      final hasItem = row['item_id'] != null;
      final timeCol = forGoldOut ? row['closed_at'] : row['created_at'];
      final time = _extractTime(timeCol as String?);

      String? closureType;
      if (forGoldOut) {
        final status = row['status'] as String? ?? 'closed';
        closureType = status == 'renewed' ? 'RENEWED' : 'CLOSED';
      }

      if (hasItem) {
        entries.add(GoldMovementEntry(
          pledgeId: pledgeId,
          pledgeNumber: row['pledge_no'] as String? ?? '',
          itemType: row['item_type'] as String? ?? 'other',
          purity: (row['item_purity'] as String?) ?? '',
          netWeight: (row['item_net'] as num?)?.toDouble() ?? 0,
          time: time,
          closureType: closureType,
        ));
      } else if (!seenPledges.contains(pledgeId)) {
        seenPledges.add(pledgeId);
        entries.add(GoldMovementEntry(
          pledgeId: pledgeId,
          pledgeNumber: row['pledge_no'] as String? ?? '',
          itemType: 'Gold',
          purity: (row['pledge_purity'] as String?) ?? '',
          netWeight: (row['pledge_net'] as num?)?.toDouble() ?? 0,
          time: time,
          closureType: closureType,
        ));
      }
    }

    return entries;
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

  Future<void> adjustStock({
    required String date,
    required double weight,
    required int count,
    required String reason,
    required bool isAdd,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    final record = await getOrCreateDayRecord(date);
    final sign = isAdd ? 1.0 : -1.0;
    final newAdjWeight = record.adjustmentWeight + weight * sign;
    final newAdjCount = record.adjustmentCount + (count * sign).round();
    final newClosing = record.openingWeight +
        record.goldInWeight -
        record.goldOutWeight +
        newAdjWeight;
    final newClosingCount = record.openingCount +
        record.goldInCount -
        record.goldOutCount +
        newAdjCount;

    await db.update(
      'daily_stock',
      {
        'adjustment_weight': newAdjWeight,
        'adjustment_count': newAdjCount,
        'closing_weight': newClosing < 0 ? 0.0 : newClosing,
        'closing_count': newClosingCount < 0 ? 0 : newClosingCount,
        'updated_at': now,
      },
      where: 'stock_date = ?',
      whereArgs: [date],
    );

    await db.insert('audit_log', {
      'entity_type': 'daily_stock',
      'entity_id': date,
      'action': isAdd ? 'stock_add' : 'stock_remove',
      'old_value_json': null,
      'new_value_json':
          '{"weight":${weight * sign},"count":${(count * sign).round()}}',
      'reason': reason,
      'created_by': null,
      'created_at': now,
    });
  }

  // ─── Verify and lock ───────────────────────────────────────────────────────

  Future<void> verifyAndLock({
    required String date,
    required double actualWeight,
    required int actualCount,
    String? discrepancyNote,
    required String lockedBy,
  }) async {
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

    await db.insert('audit_log', {
      'entity_type': 'daily_stock',
      'entity_id': date,
      'action': 'stock_locked',
      'old_value_json': null,
      'new_value_json':
          '{"actual_weight":$actualWeight,"actual_count":$actualCount}',
      'reason': discrepancyNote ?? 'Stock verified',
      'created_by': null,
      'created_at': now,
    });
  }

  // ─── Unlock (admin only) ───────────────────────────────────────────────────

  Future<void> unlockDay({
    required String date,
    required String reason,
    required String unlockedBy,
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

    await db.insert('audit_log', {
      'entity_type': 'daily_stock',
      'entity_id': date,
      'action': 'stock_unlocked',
      'old_value_json': null,
      'new_value_json': null,
      'reason': reason,
      'created_by': null,
      'created_at': now,
    });
  }

  // ─── Gold rate ─────────────────────────────────────────────────────────────

  Future<double> getGoldRate() async {
    final rateStr = await _settingsRepo.getString('gold_rate');
    return double.tryParse(rateStr ?? '') ?? 0;
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  DailyStockRecord _fromMap(Map<String, dynamic> row) {
    return DailyStockRecord(
      stockId: row['stock_id'] as int?,
      stockDate: row['stock_date'] as String? ?? '',
      openingWeight: (row['opening_weight'] as num?)?.toDouble() ?? 0,
      openingCount: (row['opening_count'] as int?) ?? 0,
      goldInWeight: (row['gold_in_weight'] as num?)?.toDouble() ?? 0,
      goldInCount: (row['gold_in_count'] as int?) ?? 0,
      goldOutWeight: (row['gold_out_weight'] as num?)?.toDouble() ?? 0,
      goldOutCount: (row['gold_out_count'] as int?) ?? 0,
      adjustmentWeight: (row['adjustment_weight'] as num?)?.toDouble() ?? 0,
      adjustmentCount: (row['adjustment_count'] as int?) ?? 0,
      closingWeight: (row['closing_weight'] as num?)?.toDouble() ?? 0,
      closingCount: (row['closing_count'] as int?) ?? 0,
      isLocked: (row['is_locked'] as int?) == 1,
      lockedAt: row['locked_at'] as String?,
      lockedBy: row['locked_by'] as String?,
      discrepancyNote: row['discrepancy_note'] as String?,
      unlockedBy: row['unlocked_by'] as String?,
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
