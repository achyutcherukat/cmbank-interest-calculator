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
    if (oldVersion < 9) {
      await _migrateV8toV9(db);
    }
  }

  static Future<void> _migrateV8toV9(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');

    // 1. Create bank_accounts and daily_account_balance tables.
    await db.execute(DatabaseSchema.createBankAccounts);
    await db.execute(DatabaseSchema.createDailyAccountBalance);

    // 2. Seed the legacy 'UPI' account from existing settings.
    final settingsRows = await db.rawQuery(
      "SELECT key, value FROM settings WHERE key IN ('opening_upi', 'app_use_start_date')",
    );
    final settingsMap = {
      for (final row in settingsRows) row['key'] as String: row['value'] as String,
    };
    final openingUpi = double.tryParse(settingsMap['opening_upi'] ?? '0') ?? 0.0;
    final startDate = settingsMap['app_use_start_date'] ??
        DateTime.now().toIso8601String().substring(0, 10);
    final now = DateTime.now().toIso8601String();

    final bankAccountId = await db.rawInsert(
      'INSERT INTO bank_accounts '
      '(name, opening_balance, start_date, is_default, is_active, created_at, updated_at) '
      'VALUES (?, ?, ?, 1, 1, ?, ?)',
      ['UPI', openingUpi, startDate, now, now],
    );

    // 3. Recreate payments table: rename upi_amount → bank_amount, add bank_account_id.
    //    The INSERT SELECT backfills bank_account_id for all rows that had upi_amount > 0.
    await db.execute(
      DatabaseSchema.createPayments.replaceFirst(
        'CREATE TABLE IF NOT EXISTS payments',
        'CREATE TABLE payments_v9',
      ),
    );
    await db.rawInsert(
      'INSERT INTO payments_v9 '
      '(id, payment_date, payment_type, sub_category, direction, amount, cash_amount, '
      ' bank_amount, bank_account_id, pledge_id, notes, created_by, created_at) '
      'SELECT id, payment_date, payment_type, sub_category, direction, amount, cash_amount, '
      '       upi_amount, '
      '       CASE WHEN upi_amount > 0 THEN ? ELSE NULL END, '
      '       pledge_id, notes, created_by, created_at '
      'FROM payments',
      [bankAccountId],
    );
    await db.execute('DROP TABLE payments');
    await db.execute('ALTER TABLE payments_v9 RENAME TO payments');

    // Recreate indexes on payments.
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_pledge_id ON payments(pledge_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payments_type ON payments(payment_type)');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_bank_account_id ON payments(bank_account_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bank_accounts_is_default ON bank_accounts(is_default, is_active)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_daily_account_balance_daily_balance_id '
      'ON daily_account_balance(daily_balance_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_daily_account_balance_bank_account_id '
      'ON daily_account_balance(bank_account_id)',
    );

    // 4. Backfill daily_account_balance from every existing daily_balance row.
    //    Locked rows get their frozen values; unlocked rows get NULLs (live-calculated going forward).
    await db.rawInsert(
      'INSERT INTO daily_account_balance '
      '(daily_balance_id, bank_account_id, opening_balance, closing_balance, '
      ' amount_in, amount_out, created_at, updated_at) '
      'SELECT '
      '  id, '
      '  ?, '
      '  opening_upi, '
      '  CASE WHEN is_locked = 1 THEN closing_upi ELSE NULL END, '
      '  CASE WHEN is_locked = 1 THEN upi_in ELSE NULL END, '
      '  CASE WHEN is_locked = 1 THEN upi_out ELSE NULL END, '
      '  ?, '
      '  ? '
      'FROM daily_balance',
      [bankAccountId, now, now],
    );

    // 5. Verify migration integrity (logged to debug console).
    final dabCount = (await db.rawQuery(
      'SELECT COUNT(*) as c FROM daily_account_balance',
    )).first['c'] as int? ?? 0;
    final dbCount = (await db.rawQuery(
      'SELECT COUNT(*) as c FROM daily_balance',
    )).first['c'] as int? ?? 0;
    final unmappedPayments = (await db.rawQuery(
      'SELECT COUNT(*) as c FROM payments WHERE bank_amount > 0 AND bank_account_id IS NULL',
    )).first['c'] as int? ?? 0;

    // ignore: avoid_print
    print('[v8→v9 migration] daily_balance rows: $dbCount, '
        'daily_account_balance rows created: $dabCount, '
        'payments with bank_amount > 0 and null bank_account_id: $unmappedPayments');

    await db.execute('PRAGMA foreign_keys = ON');
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
