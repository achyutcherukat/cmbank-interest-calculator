import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'database_migrations.dart';
import 'database_tables.dart';
import 'seed_data.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _databaseName = 'cm_bank.db';
  static const _databaseVersion = 9;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    return initialize();
  }

  /// Absolute path to the SQLite database file (used by the backup services).
  Future<String> get databaseFilePath async {
    final databasesPath = await getDatabasesPath();
    return path.join(databasesPath, _databaseName);
  }

  String get databaseFileName => _databaseName;

  /// Runs `PRAGMA integrity_check` on an already-open database and returns
  /// true when the result is `ok`. Returns true immediately if the database
  /// has not been opened yet (initialization is handled separately in startup).
  Future<bool> isHealthy() async {
    final db = _database;
    if (db == null) return true;
    try {
      final rows = await db.rawQuery('PRAGMA integrity_check');
      if (rows.isEmpty) return false;
      final first = rows.first.values.first;
      return (first?.toString().toLowerCase() ?? '') == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<Database> initialize() async {
    if (_database != null) return _database!;

    final databasesPath = await getDatabasesPath();
    final dbPath = path.join(databasesPath, _databaseName);

    _database = await openDatabase(
      dbPath,
      version: _databaseVersion,
      onConfigure: (db) async {
        // rawQuery is required for WAL because the PRAGMA returns a result row;
        // execute() maps to Android execSQL() which rejects result-returning statements.
        await db.rawQuery('PRAGMA journal_mode = WAL');
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

    // Idempotent — backfills future-proof backup settings keys on existing DBs.
    await SeedData.ensureBackupSettings(_database!);

    return _database!;
  }

  Future<void> close() async {
    final db = _database;
    if (db == null) return;
    await db.close();
    _database = null;
  }
}
