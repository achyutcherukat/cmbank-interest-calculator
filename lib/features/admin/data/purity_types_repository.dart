import '../../../core/database/app_database.dart';
import 'lookup_type.dart';

/// Manages the `purity_types` lookup table. Purity dropdowns across the app
/// read [getActivePurityTypes]; admin masters use the remaining methods.
class PurityTypesRepository {
  PurityTypesRepository._();
  static final PurityTypesRepository instance = PurityTypesRepository._();

  static const _table = 'purity_types';

  Future<List<String>> getActivePurityTypes() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      _table,
      columns: ['name'],
      where: 'is_active = 1',
      orderBy: 'display_order ASC',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<List<LookupType>> getAllPurityTypes() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(_table, orderBy: 'display_order ASC');
    return rows.map(LookupType.fromMap).toList();
  }

  Future<int> addPurityType(String name) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final maxRow = await db
        .rawQuery('SELECT COALESCE(MAX(display_order), 0) AS m FROM $_table');
    final nextOrder = ((maxRow.first['m'] as int?) ?? 0) + 1;
    return db.insert(_table, {
      'name': name,
      'display_order': nextOrder,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updatePurityType(int id, String name) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      _table,
      {'name': name, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> togglePurityType(int id, bool isActive) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      _table,
      {
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> reorderPurityType(int id, int newOrder) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      _table,
      {'display_order': newOrder, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
