import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'database_migrations.dart';
import 'database_tables.dart';
import 'seed_data.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _databaseName = 'cm_bank.db';
  static const _databaseVersion = 1;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    return initialize();
  }

  Future<Database> initialize() async {
    if (_database != null) return _database!;

    final databasesPath = await getDatabasesPath();
    final dbPath = path.join(databasesPath, _databaseName);

    _database = await openDatabase(
      dbPath,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final statement in DatabaseSchema.allCreateStatements) {
          await db.execute(statement);
        }
        await SeedData.insertDefaults(db);
      },
      onUpgrade: DatabaseMigrations.upgrade,
    );

    return _database!;
  }

  Future<void> close() async {
    final db = _database;
    if (db == null) return;
    await db.close();
    _database = null;
  }
}
