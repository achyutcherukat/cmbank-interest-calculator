class DatabaseTables {
  const DatabaseTables._();

  static const customers = 'customers';
  static const pledges = 'pledges';
  static const pledgeItems = 'pledge_items';
  static const payments = 'payments';
  static const transactions = 'transactions';
  static const dailyBalance = 'daily_balance';
  static const dayReconciliation = 'day_reconciliation';
  static const users = 'users';
  static const goldRates = 'gold_rates';
  static const expenseCategories = 'expense_categories';
  static const settings = 'settings';
  static const auditLog = 'audit_log';
  static const backupLog = 'backup_log';
  static const calcHistory = 'calc_history';
}

class DatabaseSchema {
  const DatabaseSchema._();

  static const createUsers = '''
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('staff', 'admin')),
  pin_hash TEXT,
  biometric_enabled INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

  static const createPledges = '''
CREATE TABLE pledges (
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
);
''';

  static const createPayments = '''
CREATE TABLE payments (
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
);
''';

  static const createTransactions = '''
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  transaction_date TEXT NOT NULL,
  type TEXT NOT NULL CHECK(type IN (
    'loan_disbursed',
    'payment_received',
    'expense',
    'adjustment',
    'opening_balance'
  )),
  direction TEXT NOT NULL CHECK(direction IN ('in', 'out')),
  amount REAL NOT NULL,
  mode TEXT NOT NULL CHECK(mode IN ('cash', 'upi', 'bank')),
  pledge_id INTEGER,
  payment_id INTEGER,
  expense_category_id INTEGER,
  description TEXT,
  created_by INTEGER,
  created_at TEXT NOT NULL,
  FOREIGN KEY(pledge_id) REFERENCES pledges(id),
  FOREIGN KEY(payment_id) REFERENCES payments(id),
  FOREIGN KEY(expense_category_id) REFERENCES expense_categories(id),
  FOREIGN KEY(created_by) REFERENCES users(id)
);
''';

  static const createDailyBalance = '''
CREATE TABLE daily_balance (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  business_date TEXT NOT NULL UNIQUE,
  opening_cash REAL NOT NULL DEFAULT 0,
  opening_upi REAL NOT NULL DEFAULT 0,
  cash_in REAL NOT NULL DEFAULT 0,
  cash_out REAL NOT NULL DEFAULT 0,
  upi_in REAL NOT NULL DEFAULT 0,
  upi_out REAL NOT NULL DEFAULT 0,
  closing_cash REAL NOT NULL DEFAULT 0,
  closing_upi REAL NOT NULL DEFAULT 0,
  is_locked INTEGER NOT NULL DEFAULT 0,
  locked_at TEXT,
  locked_by INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(locked_by) REFERENCES users(id)
);
''';

  static const createDayReconciliation = '''
CREATE TABLE day_reconciliation (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  business_date TEXT NOT NULL UNIQUE,
  expected_cash REAL NOT NULL DEFAULT 0,
  actual_cash REAL NOT NULL DEFAULT 0,
  cash_difference REAL NOT NULL DEFAULT 0,
  expected_upi REAL NOT NULL DEFAULT 0,
  actual_upi REAL NOT NULL DEFAULT 0,
  upi_difference REAL NOT NULL DEFAULT 0,
  remarks TEXT,
  locked_by INTEGER,
  locked_at TEXT,
  unlocked_by INTEGER,
  unlocked_at TEXT,
  unlock_reason TEXT,
  FOREIGN KEY(locked_by) REFERENCES users(id),
  FOREIGN KEY(unlocked_by) REFERENCES users(id)
);
''';

  static const createGoldRates = '''
CREATE TABLE gold_rates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rate_date TEXT NOT NULL,
  rate_24k REAL NOT NULL,
  rate_22k REAL NOT NULL,
  pledge_rate REAL NOT NULL DEFAULT 0,
  source TEXT NOT NULL DEFAULT 'manual',
  is_manual INTEGER NOT NULL DEFAULT 1,
  created_by INTEGER,
  created_at TEXT NOT NULL,
  FOREIGN KEY(created_by) REFERENCES users(id)
);
''';

  static const createExpenseCategories = '''
CREATE TABLE expense_categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

  static const createSettings = '''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  value_type TEXT NOT NULL DEFAULT 'string',
  updated_by INTEGER,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(updated_by) REFERENCES users(id)
);
''';

  static const createAuditLog = '''
CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  action TEXT NOT NULL,
  old_value_json TEXT,
  new_value_json TEXT,
  reason TEXT,
  created_by INTEGER,
  created_at TEXT NOT NULL,
  FOREIGN KEY(created_by) REFERENCES users(id)
);
''';

  static const createBackupLog = '''
CREATE TABLE backup_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  backup_type TEXT NOT NULL CHECK(backup_type IN ('manual', 'auto')),
  destination TEXT NOT NULL CHECK(destination IN ('local', 'drive')),
  file_name TEXT,
  status TEXT NOT NULL CHECK(status IN ('success', 'failed')),
  message TEXT,
  created_by INTEGER,
  created_at TEXT NOT NULL,
  FOREIGN KEY(created_by) REFERENCES users(id)
);
''';

  static const createCustomers = '''
CREATE TABLE customers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  phone TEXT,
  address TEXT,
  id_proof_type TEXT,
  id_proof_number TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';

  static const createPledgeItems = '''
CREATE TABLE pledge_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pledge_id INTEGER NOT NULL,
  item_type TEXT NOT NULL DEFAULT 'other',
  description TEXT,
  quantity INTEGER NOT NULL DEFAULT 1,
  gross_weight REAL NOT NULL DEFAULT 0,
  stone_weight REAL NOT NULL DEFAULT 0,
  net_weight REAL NOT NULL DEFAULT 0,
  purity TEXT NOT NULL DEFAULT '22K',
  photo_path TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY(pledge_id) REFERENCES pledges(id)
);
''';

  static const createCalcHistory = '''
CREATE TABLE calc_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  calculated_at TEXT NOT NULL,
  principal REAL NOT NULL,
  from_date TEXT NOT NULL,
  to_date TEXT NOT NULL,
  number_of_days INTEGER NOT NULL,
  interest_rate REAL NOT NULL,
  simple_interest REAL NOT NULL,
  total_amount REAL NOT NULL,
  minimum_charge_note TEXT,
  notes TEXT,
  created_at TEXT NOT NULL
);
''';

  static const createIndexes = <String>[
    'CREATE INDEX idx_pledges_status ON pledges(status);',
    'CREATE INDEX idx_pledges_pledge_no ON pledges(pledge_no);',
    'CREATE INDEX idx_pledges_customer_phone ON pledges(customer_phone);',
    'CREATE INDEX idx_payments_pledge_id ON payments(pledge_id);',
    'CREATE INDEX idx_transactions_date ON transactions(transaction_date);',
    'CREATE INDEX idx_transactions_pledge_id ON transactions(pledge_id);',
    'CREATE INDEX idx_audit_log_entity ON audit_log(entity_type, entity_id);',
  ];

  static const allCreateStatements = <String>[
    createCustomers,
    createUsers,
    createExpenseCategories,
    createPledges,
    createPledgeItems,
    createPayments,
    createTransactions,
    createDailyBalance,
    createDayReconciliation,
    createGoldRates,
    createSettings,
    createAuditLog,
    createBackupLog,
    createCalcHistory,
    ...createIndexes,
  ];
}
