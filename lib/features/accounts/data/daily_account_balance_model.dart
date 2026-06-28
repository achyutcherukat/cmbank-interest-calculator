import 'bank_account_model.dart';

/// Per-account balance snapshot for one business day (`daily_account_balance` table).
/// closing_balance / amount_in / amount_out are null until the parent
/// daily_balance row is locked (same before/after-lock pattern as daily_balance itself).
class DailyAccountBalance {
  const DailyAccountBalance({
    this.id,
    required this.dailyBalanceId,
    required this.bankAccountId,
    required this.openingBalance,
    this.closingBalance,
    this.amountIn,
    this.amountOut,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int dailyBalanceId; // DB: daily_balance_id
  final int bankAccountId; // DB: bank_account_id
  final double openingBalance; // DB: opening_balance
  final double? closingBalance; // DB: closing_balance (null = not yet locked)
  final double? amountIn; // DB: amount_in (null = not yet locked)
  final double? amountOut; // DB: amount_out (null = not yet locked)
  final String createdAt;
  final String updatedAt;

  factory DailyAccountBalance.fromMap(Map<String, dynamic> map) {
    return DailyAccountBalance(
      id: map['id'] as int?,
      dailyBalanceId: map['daily_balance_id'] as int? ?? 0,
      bankAccountId: map['bank_account_id'] as int? ?? 0,
      openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0.0,
      closingBalance: (map['closing_balance'] as num?)?.toDouble(),
      amountIn: (map['amount_in'] as num?)?.toDouble(),
      amountOut: (map['amount_out'] as num?)?.toDouble(),
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
    );
  }
}

/// Live or frozen totals for a single bank account on one business day,
/// enriched with the account's display name. Used by the drill-down view.
class DailyAccountTotals {
  const DailyAccountTotals({
    required this.bankAccount,
    required this.openingBalance,
    required this.amountIn,
    required this.amountOut,
  });

  final BankAccount bankAccount;
  final double openingBalance;
  final double amountIn;
  final double amountOut;

  double get closingBalance => openingBalance + amountIn - amountOut;
}
