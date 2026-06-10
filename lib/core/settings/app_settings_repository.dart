import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class AppSettingsRepository {
  AppSettingsRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<String?> getString(String key) async {
    final db = await _database.database;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<bool> getBool(String key, {bool fallback = false}) async {
    final value = await getString(key);
    if (value == null) return fallback;
    return value.toLowerCase() == 'true';
  }

  Future<void> upsertMany(Map<String, ({String value, String type})> values) async {
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.insert(
          'settings',
          {
            'key': entry.key,
            'value': entry.value.value,
            'value_type': entry.value.type,
            'updated_by': null,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}
