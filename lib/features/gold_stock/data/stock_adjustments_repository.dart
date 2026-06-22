import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class StockAdjustment {
  const StockAdjustment({
    required this.id,
    required this.adjustmentDate,
    required this.weight,
    required this.count,
    required this.reason,
    this.createdBy,
    required this.createdAt,
  });

  final int id;
  final String adjustmentDate;
  final double weight; // positive = added, negative = removed
  final int count;
  final String reason;
  final int? createdBy;
  final String createdAt;

  factory StockAdjustment.fromMap(Map<String, dynamic> map) {
    return StockAdjustment(
      id: map['id'] as int,
      adjustmentDate: map['adjustment_date'] as String? ?? '',
      weight: (map['weight'] as num?)?.toDouble() ?? 0.0,
      count: (map['count'] as int?) ?? 0,
      reason: map['reason'] as String? ?? '',
      createdBy: map['created_by'] as int?,
      createdAt: map['created_at'] as String? ?? '',
    );
  }
}

/// Manages the `stock_adjustments` table — manual gold weight/count corrections
/// applied on a given business date.
class StockAdjustmentsRepository {
  StockAdjustmentsRepository._();
  static final StockAdjustmentsRepository instance =
      StockAdjustmentsRepository._();

  Future<int> addAdjustment({
    required String date,
    required double weight,
    required int count,
    required String reason,
    int? userId,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await AppDatabase.instance.database;
    return db.insert('stock_adjustments', {
      'adjustment_date': date,
      'weight': weight,
      'count': count,
      'reason': reason,
      'created_by': userId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<StockAdjustment>> getAdjustmentsForDate(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'stock_adjustments',
      where: 'adjustment_date = ?',
      whereArgs: [date],
      orderBy: 'created_at ASC',
    );
    return rows.map(StockAdjustment.fromMap).toList();
  }

  /// Returns the net (signed) total weight and count of adjustments for [date].
  Future<({double weight, int count})> getTotalAdjustmentForDate(
      String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(weight), 0) AS w, COALESCE(SUM(count), 0) AS c '
      'FROM stock_adjustments WHERE adjustment_date = ?',
      [date],
    );
    return (
      weight: (rows.first['w'] as num?)?.toDouble() ?? 0.0,
      count: (rows.first['c'] as int?) ?? 0,
    );
  }
}
