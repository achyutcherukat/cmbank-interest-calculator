import 'package:sqflite/sqflite.dart';

import 'database_tables.dart';
import 'seed_data.dart';

class DatabaseMigrations {
  const DatabaseMigrations._();

  static Future<void> upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _migrateV1toV2(db);
    }
    if (oldVersion < 3) {
      await _migrateV2toV3(db);
    }
    if (oldVersion < 4) {
      await _migrateV3toV4(db);
    }
    if (oldVersion < 5) {
      await _migrateV4toV5(db);
    }
    if (oldVersion < 6) {
      await _migrateV5toV6(db);
    }
    if (oldVersion < 7) {
      await _migrateV6toV7(db);
    }
    if (oldVersion < 8) {
      await _migrateV7toV8(db);
    }
  }

  static Future<void> _migrateV7toV8(Database db) async {
    await db.execute(
      'ALTER TABLE daily_stock ADD COLUMN opening_gross_weight REAL NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE daily_stock ADD COLUMN gold_in_gross_weight REAL',
    );
    await db.execute(
      'ALTER TABLE daily_stock ADD COLUMN gold_out_gross_weight REAL',
    );
    await db.execute(
      'ALTER TABLE daily_stock ADD COLUMN adjustment_gross_weight REAL',
    );
    await db.execute(
      'ALTER TABLE daily_stock ADD COLUMN closing_gross_weight REAL',
    );
  }

  /// Major schema overhaul (Step 1). Test data only — all existing rows are
  /// discarded. Every legacy table is dropped and recreated fresh from the
  /// canonical schema in [DatabaseSchema], then default data is re-seeded.
  /// App code is updated in later steps; the app may not work correctly
  /// against this schema until then.
  static Future<void> _migrateV6toV7(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');

    // Drop every legacy table (clears all data in the process).
    for (final table in DatabaseSchema.legacyTables) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
    // Drop any new tables too, in case a partial v7 was applied previously.
    await db.execute('DROP TABLE IF EXISTS stock_adjustments');
    await db.execute('DROP TABLE IF EXISTS photo_sync_log');
    await db.execute('DROP TABLE IF EXISTS item_types');
    await db.execute('DROP TABLE IF EXISTS purity_types');

    // Recreate all tables fresh from the canonical schema.
    for (final statement in DatabaseSchema.allCreateStatements) {
      await db.execute(statement);
    }

    // Re-seed default data.
    await SeedData.insertDefaults(db);

    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _migrateV5toV6(Database db) async {
    await db.execute('ALTER TABLE customers ADD COLUMN district TEXT');
    await db.execute('ALTER TABLE customers ADD COLUMN state TEXT');
    await db.execute('ALTER TABLE customers ADD COLUMN pin_code TEXT');
  }

  static Future<void> _migrateV4toV5(Database db) async {
    await db.execute(DatabaseSchema.createDailyStock);
  }

  static Future<void> _migrateV3toV4(Database db) async {
    await db.execute(
      'ALTER TABLE pledges ADD COLUMN form_photo_paths TEXT',
    );
  }

  static Future<void> _migrateV2toV3(Database db) async {
    await db.execute(
      'ALTER TABLE pledges ADD COLUMN actual_item_value REAL NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE customers ADD COLUMN id_proof_photo_paths TEXT',
    );
    await db.execute(
      'ALTER TABLE pledge_items ADD COLUMN photo_paths TEXT',
    );
    await db.execute(
      'ALTER TABLE pledge_items ADD COLUMN notes TEXT',
    );
  }

  static Future<void> _migrateV1toV2(Database db) async {
    // Disable foreign keys during table recreation
    await db.execute('PRAGMA foreign_keys = OFF');

    // --- pledges: recreate table to fix status CHECK and add missing columns ---
    await db.execute('''
CREATE TABLE pledges_v2 (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pledge_no TEXT NOT NULL UNIQUE,
  customer_id INTEGER,
  customer_name TEXT NOT NULL,
  customer_phone TEXT,
  customer_address TEXT,
  gross_weight REAL NOT NULL DEFAULT 0,
  stone_weight REAL NOT NULL DEFAULT 0,
  net_weight REAL NOT NULL DEFAULT 0,
  purity TEXT NOT NULL DEFAULT '22K',
  gold_rate REAL NOT NULL DEFAULT 0,
  pledge_rate REAL NOT NULL DEFAULT 0,
  principal_amount REAL NOT NULL DEFAULT 0,
  interest_rate REAL NOT NULL DEFAULT 18,
  start_date TEXT NOT NULL,
  due_date TEXT,
  status TEXT NOT NULL DEFAULT 'open'
    CHECK(status IN ('open', 'closed', 'renewed', 'migrated')),
  closed_at TEXT,
  closure_date TEXT,
  source TEXT,
  renewal_parent_id INTEGER,
  total_interest_paid REAL NOT NULL DEFAULT 0,
  total_amount_collected REAL NOT NULL DEFAULT 0,
  notes TEXT,
  created_by INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(customer_id) REFERENCES customers(id),
  FOREIGN KEY(created_by) REFERENCES users(id)
)
''');

    await db.execute('''
INSERT INTO pledges_v2 (
  id, pledge_no, customer_id, customer_name, customer_phone, customer_address,
  gross_weight, stone_weight, net_weight, purity, gold_rate, pledge_rate,
  principal_amount, interest_rate, start_date, due_date,
  status, closed_at, closure_date, source, renewal_parent_id,
  total_interest_paid, total_amount_collected, notes, created_by, created_at, updated_at
)
SELECT
  id, pledge_no, customer_id, customer_name, customer_phone, customer_address,
  gross_weight, stone_weight, net_weight, purity, gold_rate, pledge_rate,
  principal_amount, interest_rate, start_date, due_date,
  CASE WHEN status = 'auctioned' THEN 'migrated' ELSE status END,
  closed_at, NULL, NULL, NULL,
  0, 0, notes, created_by, created_at, updated_at
FROM pledges
''');

    await db.execute('DROP TABLE pledges');
    await db.execute('ALTER TABLE pledges_v2 RENAME TO pledges');

    // Recreate indexes that were on the old pledges table
    await db.execute('CREATE INDEX idx_pledges_status ON pledges(status)');
    await db.execute('CREATE INDEX idx_pledges_pledge_no ON pledges(pledge_no)');
    await db.execute('CREATE INDEX idx_pledges_customer_phone ON pledges(customer_phone)');

    // --- payments: recreate to fix payment_mode CHECK and add cash_amount/upi_amount ---
    await db.execute('''
CREATE TABLE payments_v2 (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pledge_id INTEGER NOT NULL,
  payment_type TEXT NOT NULL
    CHECK(payment_type IN ('interest', 'principal', 'closure', 'renewal')),
  amount REAL NOT NULL,
  cash_amount REAL NOT NULL DEFAULT 0,
  upi_amount REAL NOT NULL DEFAULT 0,
  interest_amount REAL NOT NULL DEFAULT 0,
  principal_amount REAL NOT NULL DEFAULT 0,
  payment_mode TEXT NOT NULL DEFAULT 'cash' CHECK(payment_mode IN ('cash', 'upi', 'split', 'bank')),
  paid_at TEXT NOT NULL,
  notes TEXT,
  created_by INTEGER,
  created_at TEXT NOT NULL,
  FOREIGN KEY(pledge_id) REFERENCES pledges(id),
  FOREIGN KEY(created_by) REFERENCES users(id)
)
''');

    await db.execute('''
INSERT INTO payments_v2 (
  id, pledge_id, payment_type, amount, cash_amount, upi_amount,
  interest_amount, principal_amount, payment_mode, paid_at, notes, created_by, created_at
)
SELECT
  id, pledge_id, payment_type, amount, amount, 0,
  interest_amount, principal_amount, payment_mode, paid_at, notes, created_by, created_at
FROM payments
''');

    await db.execute('DROP TABLE payments');
    await db.execute('ALTER TABLE payments_v2 RENAME TO payments');
    await db.execute('CREATE INDEX idx_payments_pledge_id ON payments(pledge_id)');

    // --- gold_rates: add pledge_rate column ---
    await db.execute('ALTER TABLE gold_rates ADD COLUMN pledge_rate REAL NOT NULL DEFAULT 0');

    // --- calc_history: new table for calculator history ---
    await db.execute(DatabaseSchema.createCalcHistory);

    await db.execute('PRAGMA foreign_keys = ON');
  }
}
