import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/database/app_database.dart';

class CalcHistoryRepository {
  CalcHistoryRepository._();

  static final CalcHistoryRepository instance = CalcHistoryRepository._();

  Future<int> insert(Map<String, dynamic> entry) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    return db.insert('calc_history', {
      'calculated_at': entry['calculatedOn'] ?? now,
      'principal': entry['principal'],
      'from_date': entry['fromDate'],
      'to_date': entry['toDate'],
      'number_of_days': entry['numberOfDays'],
      'interest_rate': entry['interestRate'],
      'simple_interest': entry['simpleInterest'],
      'total_amount': entry['totalAmount'],
      'minimum_charge_note': entry['minimumChargeNote'] ?? '',
      'notes': entry['notes'] ?? '',
      'created_at': now,
    });
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('calc_history', orderBy: 'id DESC');
    // Return camelCase-compatible maps so existing UI code works without changes
    return rows.map((row) => {
      'id': row['id'],
      'calculatedOn': row['calculated_at'],
      'principal': row['principal'],
      'fromDate': row['from_date'],
      'toDate': row['to_date'],
      'numberOfDays': row['number_of_days'],
      'interestRate': row['interest_rate'],
      'simpleInterest': row['simple_interest'],
      'totalAmount': row['total_amount'],
      'minimumChargeNote': row['minimum_charge_note'],
      'notes': row['notes'],
    }).toList();
  }

  Future<void> delete(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('calc_history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    final db = await AppDatabase.instance.database;
    await db.delete('calc_history');
  }

  // One-time migration from SharedPreferences to SQLite. Idempotent.
  Future<void> migrateFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('calculation_history');
    if (raw == null || raw.isEmpty) return;

    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      for (final jsonStr in raw) {
        try {
          final map = json.decode(jsonStr) as Map<String, dynamic>;
          final now = map['calculatedOn'] as String? ?? DateTime.now().toIso8601String();
          await txn.insert('calc_history', {
            'calculated_at': now,
            'principal': (map['principal'] as num?)?.toDouble() ?? 0.0,
            'from_date': map['fromDate'] as String? ?? '',
            'to_date': map['toDate'] as String? ?? '',
            'number_of_days': (map['numberOfDays'] as num?)?.toInt() ?? 0,
            'interest_rate': (map['interestRate'] as num?)?.toDouble() ?? 18.0,
            'simple_interest': (map['simpleInterest'] as num?)?.toDouble() ?? 0.0,
            'total_amount': (map['totalAmount'] as num?)?.toDouble() ?? 0.0,
            'minimum_charge_note': map['minimumChargeNote'] as String? ?? '',
            'notes': map['notes'] as String? ?? '',
            'created_at': now,
          });
        } catch (_) {
          // Skip malformed entries
        }
      }
    });

    await prefs.remove('calculation_history');
  }
}
