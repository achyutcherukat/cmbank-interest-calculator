/// A single account in the double-entry chart of accounts
/// (`chart_of_accounts` table).
class LedgerAccount {
  const LedgerAccount({
    this.id,
    required this.code,
    required this.name,
    required this.accountType,
    this.linkedTable,
    this.linkedId,
    required this.isSystem,
    required this.isActive,
    this.displayOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String code;
  final String name;
  final String accountType; // 'asset','liability','capital','income','expense'
  final String? linkedTable; // 'bank_accounts' / 'expense_categories' / null
  final int? linkedId;
  final bool isSystem; // protected: cannot delete, type never changes
  final bool isActive;
  final int displayOrder;
  final String createdAt;
  final String updatedAt;

  factory LedgerAccount.fromMap(Map<String, dynamic> map) {
    return LedgerAccount(
      id: map['id'] as int?,
      code: map['code'] as String? ?? '',
      name: map['name'] as String? ?? '',
      accountType: map['account_type'] as String? ?? '',
      linkedTable: map['linked_table'] as String?,
      linkedId: map['linked_id'] as int?,
      isSystem: (map['is_system'] as int? ?? 0) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      displayOrder: map['display_order'] as int? ?? 0,
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
    );
  }
}

/// Canonical `account_type` values (matches the CHECK constraint).
class LedgerAccountType {
  const LedgerAccountType._();

  static const asset = 'asset';
  static const liability = 'liability';
  static const capital = 'capital';
  static const income = 'income';
  static const expense = 'expense';

  static const all = [asset, liability, capital, income, expense];

  static String label(String type) => switch (type) {
        asset => 'Asset',
        liability => 'Liability',
        capital => 'Capital',
        income => 'Income',
        expense => 'Expense',
        _ => type,
      };
}
