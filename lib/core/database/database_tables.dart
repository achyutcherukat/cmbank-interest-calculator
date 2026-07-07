class DatabaseTables {
  const DatabaseTables._();

  static const customers = 'customers';
  static const pledges = 'pledges';
  static const pledgeItems = 'pledge_items';
  static const payments = 'payments';
  static const dailyBalance = 'daily_balance';
  static const bankAccounts = 'bank_accounts';
  static const dailyAccountBalance = 'daily_account_balance';
  static const dayReconciliation = 'day_reconciliation';
  static const dailyStock = 'daily_stock';
  static const stockAdjustments = 'stock_adjustments';
  static const users = 'users';
  static const goldRates = 'gold_rates';
  static const expenseCategories = 'expense_categories';
  static const settings = 'settings';
  static const auditLog = 'audit_log';
  static const backupLog = 'backup_log';
  static const photoSyncLog = 'photo_sync_log';
  static const itemTypes = 'item_types';
  static const purityTypes = 'purity_types';
  static const calcHistory = 'calc_history';
  static const chartOfAccounts = 'chart_of_accounts';
  static const journalEntries = 'journal_entries';
  static const journalLines = 'journal_lines';
  static const ledgerYearEndClosures = 'ledger_year_end_closures';
}

class DatabaseSchema {
  const DatabaseSchema._();

  static const createUsers = '''
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('admin','staff')),
  pin_hash TEXT NOT NULL,
  biometric_enabled INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
)
''';

  static const createCustomers = '''
CREATE TABLE IF NOT EXISTS customers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone TEXT NOT NULL,
  name TEXT NOT NULL,
  address TEXT,
  district TEXT,
  state TEXT,
  pin_code TEXT,
  id_proof_type TEXT,
  id_proof_number TEXT,
  id_proof_photo_paths TEXT,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  UNIQUE(name, phone)
)
''';

  static const createPledges = '''
CREATE TABLE IF NOT EXISTS pledges (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pledge_no TEXT NOT NULL UNIQUE,
  start_date DATE NOT NULL,
  principal_amount REAL NOT NULL,
  interest_rate REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'open'
    CHECK(status IN ('open','closed')),
  renew_type TEXT
    CHECK(renew_type IN
    ('RENEWED','PART_PAYMENT','LOAN_INCREASE')),
  renew_subtype TEXT,
  closure_date DATE,
  closed_at DATETIME,
  total_interest_paid REAL NOT NULL DEFAULT 0,
  total_amount_collected REAL NOT NULL DEFAULT 0,
  source TEXT NOT NULL DEFAULT 'new'
    CHECK(source IN ('new','migrated')),
  renewal_parent_id INTEGER REFERENCES pledges(id),
  gross_weight REAL NOT NULL DEFAULT 0,
  net_weight REAL NOT NULL DEFAULT 0,
  pledge_rate REAL NOT NULL DEFAULT 0,
  gold_rate REAL NOT NULL DEFAULT 0,
  actual_item_value REAL NOT NULL DEFAULT 0,
  gold_photo_paths TEXT,
  form_photo_paths TEXT,
  customer_id INTEGER REFERENCES customers(id),
  customer_snapshot TEXT,
  notes TEXT,
  created_by INTEGER REFERENCES users(id),
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
)
''';

  static const createPledgeItems = '''
CREATE TABLE IF NOT EXISTS pledge_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pledge_id INTEGER NOT NULL REFERENCES pledges(id),
  item_type TEXT NOT NULL,
  description TEXT,
  quantity INTEGER NOT NULL DEFAULT 1,
  gross_weight REAL NOT NULL DEFAULT 0,
  net_weight REAL NOT NULL DEFAULT 0,
  purity TEXT,
  notes TEXT,
  created_at DATETIME NOT NULL
)
''';

  static const createPayments = '''
CREATE TABLE IF NOT EXISTS payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  payment_date DATE NOT NULL,
  payment_type TEXT NOT NULL
    CHECK(payment_type IN (
    'LOAN_DISBURSED',
    'LOAN_FULL_CLOSURE',
    'RENEWAL_INTEREST_PAID',
    'PART_PAYMENT_RECEIVED',
    'LOAN_INCREASE_DISBURSED',
    'EXPENSE',
    'ADJUSTMENT',
    'CAPITAL')),
  sub_category TEXT,
  ledger_account_id INTEGER REFERENCES chart_of_accounts(id),
  direction TEXT NOT NULL
    CHECK(direction IN ('in','out')),
  amount REAL NOT NULL DEFAULT 0,
  cash_amount REAL NOT NULL DEFAULT 0,
  bank_amount REAL NOT NULL DEFAULT 0,
  bank_account_id INTEGER REFERENCES bank_accounts(id),
  pledge_id INTEGER REFERENCES pledges(id),
  notes TEXT,
  created_by INTEGER REFERENCES users(id),
  created_at DATETIME NOT NULL,
  updated_at DATETIME
)
''';

  static const createBankAccounts = '''
CREATE TABLE IF NOT EXISTS bank_accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  opening_balance REAL NOT NULL DEFAULT 0,
  start_date DATE NOT NULL,
  is_default INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
)
''';

  static const createDailyAccountBalance = '''
CREATE TABLE IF NOT EXISTS daily_account_balance (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  daily_balance_id INTEGER NOT NULL REFERENCES daily_balance(id),
  bank_account_id INTEGER NOT NULL REFERENCES bank_accounts(id),
  opening_balance REAL NOT NULL DEFAULT 0,
  closing_balance REAL,
  amount_in REAL,
  amount_out REAL,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  UNIQUE(daily_balance_id, bank_account_id)
)
''';

  static const createDailyBalance = '''
CREATE TABLE IF NOT EXISTS daily_balance (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  business_date DATE NOT NULL UNIQUE,
  opening_cash REAL NOT NULL DEFAULT 0,
  opening_upi REAL NOT NULL DEFAULT 0,
  closing_cash REAL,
  closing_upi REAL,
  cash_in REAL,
  upi_in REAL,
  cash_out REAL,
  upi_out REAL,
  is_locked INTEGER NOT NULL DEFAULT 0,
  locked_at DATETIME,
  locked_by INTEGER REFERENCES users(id),
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
)
''';

  static const createDayReconciliation = '''
CREATE TABLE IF NOT EXISTS day_reconciliation (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  business_date DATE NOT NULL UNIQUE,
  expected_cash REAL NOT NULL DEFAULT 0,
  expected_upi REAL NOT NULL DEFAULT 0,
  actual_cash REAL NOT NULL DEFAULT 0,
  actual_upi REAL NOT NULL DEFAULT 0,
  is_locked INTEGER NOT NULL DEFAULT 0,
  locked_at DATETIME,
  locked_by INTEGER REFERENCES users(id),
  remarks TEXT,
  unlocked_by INTEGER REFERENCES users(id),
  unlock_reason TEXT,
  unlocked_at DATETIME
)
''';

  static const createDailyStock = '''
CREATE TABLE IF NOT EXISTS daily_stock (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  stock_date DATE NOT NULL UNIQUE,
  opening_weight REAL NOT NULL DEFAULT 0,
  opening_gross_weight REAL NOT NULL DEFAULT 0,
  opening_count INTEGER NOT NULL DEFAULT 0,
  gold_in_weight REAL,
  gold_in_gross_weight REAL,
  gold_in_count INTEGER,
  gold_out_weight REAL,
  gold_out_gross_weight REAL,
  gold_out_count INTEGER,
  adjustment_weight REAL,
  adjustment_gross_weight REAL,
  adjustment_count INTEGER,
  closing_weight REAL,
  closing_gross_weight REAL,
  closing_count INTEGER,
  is_locked INTEGER NOT NULL DEFAULT 0,
  locked_at DATETIME,
  locked_by INTEGER REFERENCES users(id),
  discrepancy_note TEXT,
  unlocked_by INTEGER REFERENCES users(id),
  unlock_reason TEXT,
  unlocked_at DATETIME,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
)
''';

  static const createStockAdjustments = '''
CREATE TABLE IF NOT EXISTS stock_adjustments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  adjustment_date DATE NOT NULL,
  weight REAL NOT NULL,
  gross_weight REAL NOT NULL DEFAULT 0,
  count INTEGER NOT NULL,
  reason TEXT NOT NULL,
  created_by INTEGER REFERENCES users(id),
  created_at DATETIME NOT NULL
)
''';

  static const createGoldRates = '''
CREATE TABLE IF NOT EXISTS gold_rates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rate_date DATE NOT NULL,
  gold_rate REAL,
  pledge_rate REAL NOT NULL DEFAULT 0,
  created_by INTEGER REFERENCES users(id),
  created_at DATETIME NOT NULL
)
''';

  static const createExpenseCategories = '''
CREATE TABLE IF NOT EXISTS expense_categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
)
''';

  static const createSettings = '''
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  value_type TEXT NOT NULL
    CHECK(value_type IN ('string','int','bool','json')),
  updated_by INTEGER REFERENCES users(id),
  updated_at DATETIME NOT NULL
)
''';

  static const createAuditLog = '''
CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  action_category TEXT NOT NULL
    CHECK(action_category IN (
    'PLEDGE','SETTINGS','DAY_MANAGEMENT','ADMIN')),
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  old_value_json TEXT,
  new_value_json TEXT,
  reason TEXT,
  created_by INTEGER REFERENCES users(id),
  created_at DATETIME NOT NULL
)
''';

  static const createBackupLog = '''
CREATE TABLE IF NOT EXISTS backup_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  operation TEXT NOT NULL
    CHECK(operation IN ('backup','restore')),
  backup_type TEXT NOT NULL
    CHECK(backup_type IN ('database','photo')),
  destination TEXT NOT NULL
    CHECK(destination IN ('local','drive')),
  status TEXT NOT NULL
    CHECK(status IN ('success','failed')),
  file_name TEXT,
  file_size REAL,
  drive_storage_free REAL,
  message TEXT,
  created_by INTEGER REFERENCES users(id),
  created_at DATETIME NOT NULL
)
''';

  static const createPhotoSyncLog = '''
CREATE TABLE IF NOT EXISTS photo_sync_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pledge_id INTEGER REFERENCES pledges(id),
  customer_id INTEGER REFERENCES customers(id),
  photo_type TEXT NOT NULL
    CHECK(photo_type IN ('id_proof','gold','document')),
  local_path TEXT NOT NULL,
  drive_path TEXT,
  is_synced INTEGER NOT NULL DEFAULT 0,
  synced_at DATETIME,
  sync_error TEXT,
  created_at DATETIME NOT NULL
)
''';

  static const createItemTypes = '''
CREATE TABLE IF NOT EXISTS item_types (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  display_order INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
)
''';

  static const createPurityTypes = '''
CREATE TABLE IF NOT EXISTS purity_types (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  display_order INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
)
''';

  static const createCalcHistory = '''
CREATE TABLE IF NOT EXISTS calc_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  calculated_at DATETIME NOT NULL,
  principal REAL NOT NULL,
  from_date DATE NOT NULL,
  to_date DATE NOT NULL,
  number_of_days INTEGER NOT NULL,
  interest_rate REAL NOT NULL,
  simple_interest REAL NOT NULL,
  total_amount REAL NOT NULL,
  minimum_charge_note TEXT,
  notes TEXT,
  created_at DATETIME NOT NULL
)
''';

  static const createChartOfAccounts = '''
CREATE TABLE IF NOT EXISTS chart_of_accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  account_type TEXT NOT NULL CHECK(account_type IN
    ('asset','liability','capital','income','expense')),
  linked_table TEXT,
  linked_id INTEGER,
  is_system INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
)
''';

  static const createJournalEntries = '''
CREATE TABLE IF NOT EXISTS journal_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entry_date DATE NOT NULL,
  entry_type TEXT NOT NULL CHECK(entry_type IN ('AUTO','MANUAL')),
  source_type TEXT NOT NULL CHECK(source_type IN
    ('payment','pledge','manual','opening_balance')),
  source_id INTEGER,
  narration TEXT NOT NULL,
  is_reversed INTEGER NOT NULL DEFAULT 0,
  reversed_by_entry_id INTEGER REFERENCES journal_entries(id),
  created_by INTEGER NOT NULL REFERENCES users(id),
  created_at DATETIME NOT NULL
)
''';

  static const createJournalLines = '''
CREATE TABLE IF NOT EXISTS journal_lines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  journal_entry_id INTEGER NOT NULL REFERENCES journal_entries(id),
  account_id INTEGER NOT NULL REFERENCES chart_of_accounts(id),
  pledge_id INTEGER REFERENCES pledges(id),
  debit REAL NOT NULL DEFAULT 0,
  credit REAL NOT NULL DEFAULT 0,
  is_virtual INTEGER NOT NULL DEFAULT 0,
  narration TEXT,
  created_at DATETIME NOT NULL
)
''';

  static const createLedgerYearEndClosures = '''
CREATE TABLE IF NOT EXISTS ledger_year_end_closures (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  financial_year TEXT NOT NULL UNIQUE,
  journal_entry_id INTEGER NOT NULL REFERENCES journal_entries(id),
  total_income REAL NOT NULL,
  total_expenses REAL NOT NULL,
  net_result REAL NOT NULL,
  closed_by INTEGER NOT NULL REFERENCES users(id),
  closed_at DATETIME NOT NULL
)
''';

  static const createIndexes = <String>[
    'CREATE INDEX IF NOT EXISTS idx_pledges_status ON pledges(status)',
    'CREATE INDEX IF NOT EXISTS idx_pledges_pledge_no ON pledges(pledge_no)',
    'CREATE INDEX IF NOT EXISTS idx_pledges_customer_id ON pledges(customer_id)',
    'CREATE INDEX IF NOT EXISTS idx_pledge_items_pledge_id ON pledge_items(pledge_id)',
    'CREATE INDEX IF NOT EXISTS idx_payments_pledge_id ON payments(pledge_id)',
    'CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date)',
    'CREATE INDEX IF NOT EXISTS idx_payments_type ON payments(payment_type)',
    'CREATE INDEX IF NOT EXISTS idx_payments_bank_account_id ON payments(bank_account_id)',
    'CREATE INDEX IF NOT EXISTS idx_bank_accounts_is_default ON bank_accounts(is_default, is_active)',
    'CREATE INDEX IF NOT EXISTS idx_daily_account_balance_daily_balance_id ON daily_account_balance(daily_balance_id)',
    'CREATE INDEX IF NOT EXISTS idx_daily_account_balance_bank_account_id ON daily_account_balance(bank_account_id)',
    'CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON audit_log(entity_type, entity_id)',
    'CREATE INDEX IF NOT EXISTS idx_photo_sync_log_synced ON photo_sync_log(is_synced)',
    'CREATE INDEX IF NOT EXISTS idx_chart_of_accounts_linked ON chart_of_accounts(linked_table, linked_id)',
    'CREATE INDEX IF NOT EXISTS idx_journal_entries_date ON journal_entries(entry_date)',
    'CREATE INDEX IF NOT EXISTS idx_journal_entries_source ON journal_entries(source_type, source_id)',
    'CREATE INDEX IF NOT EXISTS idx_journal_lines_entry_id ON journal_lines(journal_entry_id)',
    'CREATE INDEX IF NOT EXISTS idx_journal_lines_account_id ON journal_lines(account_id)',
    'CREATE INDEX IF NOT EXISTS idx_journal_lines_pledge_id ON journal_lines(pledge_id)',
    'CREATE INDEX IF NOT EXISTS idx_payments_ledger_account_id ON payments(ledger_account_id)',
  ];

  /// All table names that existed in schema version 6 and earlier. Used by the
  /// v6 -> v7 migration to drop every legacy table before recreating fresh.
  static const legacyTables = <String>[
    'transactions',
    'payments',
    'pledge_items',
    'pledges',
    'customers',
    'daily_balance',
    'day_reconciliation',
    'daily_stock',
    'gold_rates',
    'calc_history',
    'audit_log',
    'backup_log',
    'settings',
    'users',
    'expense_categories',
  ];

  static const allCreateStatements = <String>[
    createUsers,
    createCustomers,
    createPledges,
    createPledgeItems,
    createBankAccounts,
    createPayments,
    createDailyBalance,
    createDailyAccountBalance,
    createDayReconciliation,
    createDailyStock,
    createStockAdjustments,
    createGoldRates,
    createExpenseCategories,
    createSettings,
    createAuditLog,
    createBackupLog,
    createPhotoSyncLog,
    createItemTypes,
    createPurityTypes,
    createCalcHistory,
    createChartOfAccounts,
    createJournalEntries,
    createJournalLines,
    createLedgerYearEndClosures,
    ...createIndexes,
  ];
}
