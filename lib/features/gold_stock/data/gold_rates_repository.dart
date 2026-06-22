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

  /// The latest gold rate and pledge rate, or null if none recorded yet.
  Future<({double? goldRate, double pledgeRate})?> getCurrentRates() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'gold_rates',
      columns: ['gold_rate', 'pledge_rate'],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (
      goldRate: (rows.first['gold_rate'] as num?)?.toDouble(),
      pledgeRate: (rows.first['pledge_rate'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Records a new rate row (never updates existing rows).
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

  Future<List<GoldRateRecord>> getRateHistory({int limit = 200}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('gold_rates',
        orderBy: 'created_at DESC', limit: limit);
    return rows.map(GoldRateRecord.fromMap).toList();
  }
}
