import 'package:sqflite/sqflite.dart';

/// Core helpers for the `chart_of_accounts` ledger table.
///
/// Used by seed/migration code and by the sync hooks that keep linked ledger
/// accounts in step with `bank_accounts` and `expense_categories` rows. Every
/// method takes a [DatabaseExecutor] so callers can run it inside the same
/// transaction as the triggering insert/update.
class ChartOfAccountsSync {
  const ChartOfAccountsSync._();

  static const linkedTableBankAccounts = 'bank_accounts';
  static const linkedTableExpenseCategories = 'expense_categories';

  /// Numeric code block per account type (asset 1xxx, liability 2xxx,
  /// capital 3xxx, income 4xxx, expense 5xxx).
  static const _codeBlockBase = <String, int>{
    'asset': 1000,
    'liability': 2000,
    'capital': 3000,
    'income': 4000,
    'expense': 5000,
  };

  /// Next available code in [accountType]'s numeric block.
  static Future<String> nextCode(
      DatabaseExecutor db, String accountType) async {
    final base = _codeBlockBase[accountType];
    if (base == null) {
      throw ArgumentError('Unknown account type: $accountType');
    }
    final rows = await db.rawQuery(
      'SELECT MAX(CAST(code AS INTEGER)) AS max_code FROM chart_of_accounts '
      'WHERE CAST(code AS INTEGER) BETWEEN ? AND ?',
      [base + 1, base + 999],
    );
    final maxCode = rows.first['max_code'] as int?;
    return ((maxCode ?? base) + 1).toString();
  }

  /// Inserts a `chart_of_accounts` row. When [code] is null the next
  /// available code in the type's block is assigned.
  static Future<int> insertAccount(
    DatabaseExecutor db, {
    required String name,
    required String accountType,
    String? code,
    String? linkedTable,
    int? linkedId,
    bool isSystem = false,
    bool isActive = true,
  }) async {
    final now = DateTime.now().toIso8601String();
    return db.insert('chart_of_accounts', {
      'code': code ?? await nextCode(db, accountType),
      'name': name,
      'account_type': accountType,
      'linked_table': linkedTable,
      'linked_id': linkedId,
      'is_system': isSystem ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'display_order': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Flips `is_active` on the ledger account linked to
  /// [linkedTable]/[linkedId] (soft toggle — never deletes).
  static Future<void> setLinkedActive(
    DatabaseExecutor db,
    String linkedTable,
    int linkedId, {
    required bool active,
  }) async {
    await db.update(
      'chart_of_accounts',
      {
        'is_active': active ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'linked_table = ? AND linked_id = ?',
      whereArgs: [linkedTable, linkedId],
    );
  }

  /// Renames the ledger account linked to [linkedTable]/[linkedId] so linked
  /// accounts always mirror their source row's name.
  static Future<void> renameLinked(
    DatabaseExecutor db,
    String linkedTable,
    int linkedId,
    String name,
  ) async {
    await db.update(
      'chart_of_accounts',
      {'name': name, 'updated_at': DateTime.now().toIso8601String()},
      where: 'linked_table = ? AND linked_id = ?',
      whereArgs: [linkedTable, linkedId],
    );
  }

  /// Fixed, system-protected accounts (identical seed for CMB and GMC).
  static const _fixedAccounts = <(String, String, String)>[
    ('1001', 'Cash in Hand', 'asset'),
    ('1101', 'Gold Loan Receivable', 'asset'),
    ('3001', 'Partner A Capital Account', 'capital'),
    ('3002', 'Partner B Capital Account', 'capital'),
    ('4001', 'Interest Collected Account', 'income'),
  ];

  /// Standalone, non-system accounts — editable/deletable later via the
  /// Add Ledger Account screen.
  static const _standaloneAccounts = <(String, String, String)>[
    ('1201', 'Motor Car Account', 'asset'),
    ('1202', 'Furniture and Fittings Account', 'asset'),
    ('1203', 'Security Alarm System Account', 'asset'),
    ('1204', 'Shop Advance Account', 'asset'),
    ('2001', 'Professional Charge Payable Account', 'liability'),
    ('4002', 'Interest Received on Security Deposit', 'income'),
  ];

  /// Seeds the fixed + standalone accounts and creates a linked ledger
  /// account for every existing `bank_accounts` and `expense_categories` row.
  /// Idempotent — already-seeded codes and already-linked rows are skipped.
  static Future<void> seedDefaults(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();

    for (final (code, name, type) in [..._fixedAccounts, ..._standaloneAccounts]) {
      final isSystem = _fixedAccounts.any((a) => a.$1 == code);
      await db.insert(
        'chart_of_accounts',
        {
          'code': code,
          'name': name,
          'account_type': type,
          'linked_table': null,
          'linked_id': null,
          'is_system': isSystem ? 1 : 0,
          'is_active': 1,
          'display_order': 0,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await _syncExistingRows(
      db,
      sourceTable: linkedTableBankAccounts,
      accountType: 'asset',
    );
    await _syncExistingRows(
      db,
      sourceTable: linkedTableExpenseCategories,
      accountType: 'expense',
    );
  }

  static Future<void> _syncExistingRows(
    DatabaseExecutor db, {
    required String sourceTable,
    required String accountType,
  }) async {
    final rows = await db.rawQuery(
      'SELECT s.id, s.name, s.is_active FROM $sourceTable s '
      'WHERE NOT EXISTS (SELECT 1 FROM chart_of_accounts c '
      '  WHERE c.linked_table = ? AND c.linked_id = s.id) '
      'ORDER BY s.id ASC',
      [sourceTable],
    );
    for (final row in rows) {
      await insertAccount(
        db,
        name: row['name'] as String,
        accountType: accountType,
        linkedTable: sourceTable,
        linkedId: row['id'] as int,
        isSystem: true,
        isActive: (row['is_active'] as int? ?? 1) == 1,
      );
    }
  }
}
