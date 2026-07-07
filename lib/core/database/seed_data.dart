import 'package:sqflite/sqflite.dart';

import 'chart_of_accounts_sync.dart';

class SeedData {
  const SeedData._();

  static Future<void> insertDefaults(Database db) async {
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();

    // users — two default users. pin_hash is set during first launch wizard.
    for (final user in _users) {
      batch.insert('users', {
        'name': user.$1,
        'role': user.$2,
        'pin_hash': '',
        'biometric_enabled': 0,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    }

    for (final name in _expenseCategories) {
      batch.insert('expense_categories', {
        'name': name,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    }

    for (var i = 0; i < _itemTypes.length; i++) {
      batch.insert('item_types', {
        'name': _itemTypes[i],
        'display_order': i + 1,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    }

    for (var i = 0; i < _purityTypes.length; i++) {
      batch.insert('purity_types', {
        'name': _purityTypes[i],
        'display_order': i + 1,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    }

    for (final entry in _settings.entries) {
      batch.insert('settings', {
        'key': entry.key,
        'value': entry.value.$1,
        'value_type': entry.value.$2,
        'updated_by': null,
        'updated_at': now,
      });
    }

    await batch.commit(noResult: true);

    // Chart of accounts: fixed + standalone defaults, plus linked ledger
    // accounts for the expense categories seeded above.
    await ChartOfAccountsSync.seedDefaults(db);
  }

  /// Idempotently ensures the future-proof backup settings keys exist on
  /// databases that were created before these keys were added (Part 1).
  /// Safe to call on every launch — uses INSERT OR IGNORE on the key PK.
  static Future<void> ensureBackupSettings(Database db) async {
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    const keys = <String, (String, String)>{
      'device_mode': ('primary', 'string'),
      'device_name': ('Counter', 'string'),
      'last_sync_from_drive': ('', 'string'),
      'last_local_backup': ('', 'string'),
      'last_drive_backup': ('', 'string'),
      'last_photo_backup': ('', 'string'),
      'backup_key_encrypted': ('', 'string'),
      'clean_shutdown': ('true', 'bool'),
    };
    for (final entry in keys.entries) {
      batch.insert(
        'settings',
        {
          'key': entry.key,
          'value': entry.value.$1,
          'value_type': entry.value.$2,
          'updated_by': null,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  static const _users = <(String, String)>[
    ('Admin', 'admin'),
    ('Staff', 'staff'),
  ];

  static const _expenseCategories = <String>[
    'Rent',
    'Electricity',
    'Staff Salary',
    'Office Supplies',
    'Other',
  ];

  static const _itemTypes = <String>[
    'Necklace',
    'Ring',
    'Bangle',
    'Earring',
    'Bracelet',
    'Chain',
    'Anklet',
    'Coin',
    'Bar',
    'Pendant',
    'Waist Belt',
    'Nose Ring',
    'Other',
  ];

  static const _purityTypes = <String>[
    '916',
    '22K',
    'Other',
  ];

  static const _settings = <String, (String, String)>{
    'interest_rate': ('18', 'int'),
    'new_pledge_last_number': ('0', 'int'),
    'migration_last_number': ('0', 'int'),
    'backup_start_time': ('09:00', 'string'),
    'backup_end_time': ('17:30', 'string'),
    'backup_frequency': ('30', 'int'),
    'backup_retention_days': ('7', 'int'),
    'opening_stock_weight': ('0', 'int'),
    'opening_stock_count': ('0', 'int'),
    'device_setup_complete': ('false', 'bool'),
    // --- One-off production data-fix tracking (see data_fix_script.dart) ---
    'last_data_fix_applied': ('0', 'int'),
    // --- Future-proof multi-device keys (Part 1; no active functionality yet) ---
    'device_mode': ('primary', 'string'),
    'device_name': ('Counter', 'string'),
    'last_sync_from_drive': ('', 'string'),
    'last_local_backup': ('', 'string'),
    'last_drive_backup': ('', 'string'),
    'last_photo_backup': ('', 'string'),
    // --- Backup key recovery (set on first launch by EncryptionService) ---
    'backup_key_encrypted': ('', 'string'),
    // --- Crash recovery: 'true' when last run shut down cleanly (Part 7) ---
    'clean_shutdown': ('true', 'bool'),
    // --- Ledger (reserved for the Opening Balance Wizard, later prompt) ---
    'ledger_start_date': ('2026-06-30', 'string'),
    'ledger_opening_posted': ('false', 'bool'),
  };
}
