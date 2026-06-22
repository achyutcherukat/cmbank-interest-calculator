import '../../../core/database/app_database.dart';
import 'lookup_type.dart';

/// Manages the `item_types` lookup table. Item-type dropdowns across the app
/// read [getActiveItemTypes]; admin masters use the remaining methods.
class ItemTypesRepository {
  ItemTypesRepository._();
  static final ItemTypesRepository instance = ItemTypesRepository._();

  static const _table = 'item_types';

  Future<List<String>> getActiveItemTypes() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      _table,
      columns: ['name'],
      where: 'is_active = 1',
      orderBy: 'display_order ASC',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<List<LookupType>> getAllItemTypes() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(_table, orderBy: 'display_order ASC');
    return rows.map(LookupType.fromMap).toList();
  }

  Future<int> addItemType(String name) async {
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

  Future<void> updateItemType(int id, String name) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      _table,
      {'name': name, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleItemType(int id, bool isActive) async {
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

  Future<void> reorderItemType(int id, int newOrder) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      _table,
      {'display_order': newOrder, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
