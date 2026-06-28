class BankAccount {
  const BankAccount({
    this.id,
    required this.name,
    required this.openingBalance,
    required this.startDate,
    required this.isDefault,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final double openingBalance; // DB: opening_balance
  final String startDate; // DB: start_date (ISO 8601 YYYY-MM-DD)
  final bool isDefault; // DB: is_default (1 = default, 0 = not)
  final bool isActive; // DB: is_active (1 = active, 0 = inactive)
  final String createdAt;
  final String updatedAt;

  factory BankAccount.fromMap(Map<String, dynamic> map) {
    return BankAccount(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0.0,
      startDate: map['start_date'] as String? ?? '',
      isDefault: (map['is_default'] as int?) == 1,
      isActive: (map['is_active'] as int?) == 1,
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'opening_balance': openingBalance,
      'start_date': startDate,
      'is_default': isDefault ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  BankAccount copyWith({
    String? name,
    double? openingBalance,
    String? startDate,
    bool? isDefault,
    bool? isActive,
  }) {
    return BankAccount(
      id: id,
      name: name ?? this.name,
      openingBalance: openingBalance ?? this.openingBalance,
      startDate: startDate ?? this.startDate,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: DateTime.now().toIso8601String(),
    );
  }
}
