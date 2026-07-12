import '../../../core/database/app_database.dart';

class GoldRateRecord {
  const GoldRateRecord({
    required this.id,
    required this.rateDate,
    this.goldRate,
    required this.pledgeRate,
    this.createdBy,
    required this.createdAt,
  });

  final int id;
  final String rateDate;
  final double? goldRate;
  final double pledgeRate;
  final int? createdBy;
  final String createdAt;

  factory GoldRateRecord.fromMap(Map<String, dynamic> map) {
    return GoldRateRecord(
      id: map['id'] as int,
      rateDate: map['rate_date'] as String? ?? '',
      goldRate: (map['gold_rate'] as num?)?.toDouble(),
      pledgeRate: (map['pledge_rate'] as num?)?.toDouble() ?? 0.0,
      createdBy: map['created_by'] as int?,
      createdAt: map['created_at'] as String? ?? '',
    );
  }
}

/// Manages the `gold_rates` table. Rates are append-only: every change inserts
/// a new row, and the current rate is the most recently created one.
class GoldRatesRepository {
  GoldRatesRepository._();
  static final GoldRatesRepository instance = GoldRatesRepository._();

  /// The latest universal gold rate and pledge rate, or null if none recorded
  /// yet. Scoped to rows with no purity type so per-purity edits (see
  /// [saveRateForPurity]) never change what this returns — legacy readers
  /// (New Loan, Stock, first-launch seeding) keep working off the pre-existing
  /// universal rate until they are migrated to purity-specific rates.
  Future<({double? goldRate, double pledgeRate})?> getCurrentRates() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'gold_rates',
      columns: ['gold_rate', 'pledge_rate'],
      where: 'purity_type_id IS NULL',
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (
      goldRate: (rows.first['gold_rate'] as num?)?.toDouble(),
      pledgeRate: (rows.first['pledge_rate'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Records a new universal rate row (never updates existing rows).
  Future<int> saveRates({
    double? goldRate,
    required double pledgeRate,
    int? userId,
    String? rateDate,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    return db.insert('gold_rates', {
      'rate_date': rateDate ?? now.substring(0, 10),
      'gold_rate': goldRate,
      'pledge_rate': pledgeRate,
      'created_by': userId,
      'created_at': now,
    });
  }

  /// The latest gold rate and pledge rate for one purity type, or null if
  /// that purity has no rate recorded yet.
  Future<({double? goldRate, double pledgeRate})?> getCurrentRateForPurity(
      int purityTypeId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'gold_rates',
      columns: ['gold_rate', 'pledge_rate'],
      where: 'purity_type_id = ?',
      whereArgs: [purityTypeId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (
      goldRate: (rows.first['gold_rate'] as num?)?.toDouble(),
      pledgeRate: (rows.first['pledge_rate'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// The latest gold rate and pledge rate for every purity type that has at
  /// least one rate recorded, keyed by `purity_type_id`.
  Future<Map<int, ({double? goldRate, double pledgeRate})>>
      getCurrentRatesByPurity() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT gr.purity_type_id AS purity_type_id,
             gr.gold_rate AS gold_rate,
             gr.pledge_rate AS pledge_rate
      FROM gold_rates gr
      INNER JOIN (
        SELECT purity_type_id, MAX(created_at) AS max_created_at
        FROM gold_rates
        WHERE purity_type_id IS NOT NULL
        GROUP BY purity_type_id
      ) latest
        ON gr.purity_type_id = latest.purity_type_id
        AND gr.created_at = latest.max_created_at
    ''');
    return {
      for (final row in rows)
        (row['purity_type_id'] as int): (
          goldRate: (row['gold_rate'] as num?)?.toDouble(),
          pledgeRate: (row['pledge_rate'] as num?)?.toDouble() ?? 0.0,
        ),
    };
  }

  /// Records a new rate row scoped to one purity type (never updates existing
  /// rows). Updating one purity's rate never affects another purity's current
  /// rate, since each reads only its own latest row.
  Future<int> saveRateForPurity({
    required int purityTypeId,
    double? goldRate,
    required double pledgeRate,
    int? userId,
    String? rateDate,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    return db.insert('gold_rates', {
      'rate_date': rateDate ?? now.substring(0, 10),
      'gold_rate': goldRate,
      'pledge_rate': pledgeRate,
      'purity_type_id': purityTypeId,
      'created_by': userId,
      'created_at': now,
    });
  }

  Future<List<GoldRateRecord>> getRateHistory({int limit = 200}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('gold_rates',
        orderBy: 'created_at DESC', limit: limit);
    return rows.map(GoldRateRecord.fromMap).toList();
  }
}
