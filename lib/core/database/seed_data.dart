import 'package:sqflite/sqflite.dart';

class SeedData {
  const SeedData._();

  static Future<void> insertDefaults(Database db) async {
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();

    batch.insert('users', {
      'name': 'Admin',
      'role': 'admin',
      'pin_hash': null,
      'biometric_enabled': 0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });

    for (final name in _expenseCategories) {
      batch.insert('expense_categories', {
        'name': name,
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
  }

  static const _expenseCategories = <String>[
    'Rent',
    'Salary',
    'Utilities',
    'Stationery',
    'Bank Charges',
    'Other',
  ];

  static const _settings = <String, (String, String)>{
    'business_name': ('CM Bank', 'string'),
    'common_pin_hash': ('', 'string'),
    'admin_pin_hash': ('', 'string'),
    'biometric_enabled': ('false', 'bool'),
    'default_interest_rate': ('18.0', 'double'),
    'default_pledge_rate': ('0.0', 'double'),
    'staff_history_days': ('10', 'int'),
    'first_launch_completed': ('false', 'bool'),
    'starting_pledge_number': ('3200', 'int'),
    'opening_cash': ('0.00', 'double'),
    'opening_upi': ('0.00', 'double'),
  };
}
