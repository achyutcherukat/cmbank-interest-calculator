import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class DayReconciliation {
  const DayReconciliation({
    this.id,
    required this.businessDate,
    required this.expectedCash,
    required this.expectedUpi,
    required this.actualCash,
    required this.actualUpi,
    required this.isLocked,
    this.lockedAt,
    this.lockedBy,
    this.remarks,
    this.unlockedBy,
    this.unlockReason,
    this.unlockedAt,
  });

  final int? id;
  final String businessDate;
  final double expectedCash;
  final double expectedUpi;
  final double actualCash;
  final double actualUpi;
  final bool isLocked;
  final String? lockedAt;
  final int? lockedBy;
  final String? remarks;
  final int? unlockedBy;
  final String? unlockReason;
  final String? unlockedAt;

  // Differences are derived, never stored.
  double get cashDifference => actualCash - expectedCash;
  double get upiDifference => actualUpi - expectedUpi;

  factory DayReconciliation.fromMap(Map<String, dynamic> map) {
    return DayReconciliation(
      id: map['id'] as int?,
      businessDate: map['business_date'] as String? ?? '',
      expectedCash: (map['expected_cash'] as num?)?.toDouble() ?? 0.0,
      expectedUpi: (map['expected_upi'] as num?)?.toDouble() ?? 0.0,
      actualCash: (map['actual_cash'] as num?)?.toDouble() ?? 0.0,
      actualUpi: (map['actual_upi'] as num?)?.toDouble() ?? 0.0,
      isLocked: (map['is_locked'] as int?) == 1,
      lockedAt: map['locked_at'] as String?,
      lockedBy: map['locked_by'] as int?,
      remarks: map['remarks'] as String?,
      unlockedBy: map['unlocked_by'] as int?,
      unlockReason: map['unlock_reason'] as String?,
      unlockedAt: map['unlocked_at'] as String?,
    );
  }
}

class DayReconciliationRepository {
  DayReconciliationRepository._();
  static final DayReconciliationRepository instance =
      DayReconciliationRepository._();

  Future<DayReconciliation?> getForDate(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('day_reconciliation',
        where: 'business_date = ?', whereArgs: [date], limit: 1);
    return rows.isEmpty ? null : DayReconciliation.fromMap(rows.first);
  }

  /// Creates (or replaces) the reconciliation record for [date] and locks it.
  Future<void> lockReconciliation({
    required String date,
    required double expectedCash,
    required double expectedUpi,
    required double actualCash,
    required double actualUpi,
    String? remarks,
    int? userId,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final existing = await db.query('day_reconciliation',
        columns: ['id'], where: 'business_date = ?', whereArgs: [date], limit: 1);

    final values = {
      'business_date': date,
      'expected_cash': expectedCash,
      'expected_upi': expectedUpi,
      'actual_cash': actualCash,
      'actual_upi': actualUpi,
      'is_locked': 1,
      'locked_at': now,
      'locked_by': userId,
      'remarks': remarks,
    };

    if (existing.isEmpty) {
      await db.insert('day_reconciliation', values);
    } else {
      await db.update('day_reconciliation', values,
          where: 'business_date = ?', whereArgs: [date]);
    }
  }

  Future<void> unlockReconciliation({
    required String date,
    required String reason,
    int? userId,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await AppDatabase.instance.database;
    await db.update(
      'day_reconciliation',
      {
        'is_locked': 0,
        'unlocked_by': userId,
        'unlock_reason': reason,
        'unlocked_at': DateTime.now().toIso8601String(),
      },
      where: 'business_date = ?',
      whereArgs: [date],
    );
  }
}
