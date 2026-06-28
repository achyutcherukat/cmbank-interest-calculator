/// A single entry in the accounts ledger (`payments` table). Every cash/bank
/// movement in the business is one row: loan disbursements, closures, renewal
/// interest, part payments, loan increases, expenses and balance adjustments.
class PaymentModel {
  const PaymentModel({
    this.id,
    required this.paymentDate,
    required this.paymentType,
    this.subCategory,
    required this.direction,
    this.amount = 0.0,
    this.cashAmount = 0.0,
    this.bankAmount = 0.0,
    this.bankAccountId,
    this.pledgeId,
    this.notes,
    this.createdBy,
    required this.createdAt,
  });

  final int? id;
  final String paymentDate; // DB: payment_date (ISO 8601 YYYY-MM-DD)
  final String paymentType; // DB: payment_type (see PaymentType)
  final String? subCategory; // DB: sub_category
  final String direction; // DB: direction ('in' / 'out')
  final double amount;
  final double cashAmount; // DB: cash_amount
  final double bankAmount; // DB: bank_amount (formerly upi_amount)
  final int? bankAccountId; // DB: bank_account_id (null when bank_amount = 0)
  final int? pledgeId; // DB: pledge_id (null for EXPENSE / ADJUSTMENT)
  final String? notes;
  final int? createdBy; // DB: created_by
  final String createdAt;

  factory PaymentModel.fromMap(Map<String, dynamic> map) {
    return PaymentModel(
      id: map['id'] as int?,
      paymentDate: map['payment_date'] as String? ?? '',
      paymentType: map['payment_type'] as String? ?? '',
      subCategory: map['sub_category'] as String?,
      direction: map['direction'] as String? ?? 'in',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      cashAmount: (map['cash_amount'] as num?)?.toDouble() ?? 0.0,
      bankAmount: (map['bank_amount'] as num?)?.toDouble() ?? 0.0,
      bankAccountId: map['bank_account_id'] as int?,
      pledgeId: map['pledge_id'] as int?,
      notes: map['notes'] as String?,
      createdBy: map['created_by'] as int?,
      createdAt: map['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'payment_date': paymentDate,
      'payment_type': paymentType,
      'sub_category': subCategory,
      'direction': direction,
      'amount': amount,
      'cash_amount': cashAmount,
      'bank_amount': bankAmount,
      'bank_account_id': bankAccountId,
      'pledge_id': pledgeId,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt,
    };
  }
}

/// Canonical `payment_type` values (matches the CHECK constraint).
class PaymentType {
  const PaymentType._();

  static const loanDisbursed = 'LOAN_DISBURSED';
  static const loanFullClosure = 'LOAN_FULL_CLOSURE';
  static const renewalInterestPaid = 'RENEWAL_INTEREST_PAID';
  static const partPaymentReceived = 'PART_PAYMENT_RECEIVED';
  static const loanIncreaseDisbursed = 'LOAN_INCREASE_DISBURSED';
  static const expense = 'EXPENSE';
  static const adjustment = 'ADJUSTMENT';
}

/// `direction` values.
class PaymentDirection {
  const PaymentDirection._();

  static const inward = 'in';
  static const outward = 'out';
}

/// Canonical `sub_category` values used by part payments, loan increases and
/// balance adjustments.
class PaymentSubCategory {
  const PaymentSubCategory._();

  // Part payment
  static const principalAndInterest = 'PRINCIPAL_AND_INTEREST';
  static const fixedAmountInclusive = 'FIXED_AMOUNT_INCLUSIVE';

  // Loan increase
  static const interestNotCapitalised = 'INTEREST_NOT_CAPITALISED';
  static const interestCapitalised = 'INTEREST_CAPITALISED';

  // Adjustments (legacy UPI variants kept for backward compat with existing rows)
  static const addCash = 'ADD_CASH';
  static const addUpi = 'ADD_UPI';
  static const cashToUpi = 'CASH_TO_UPI';
  static const upiToCash = 'UPI_TO_CASH';

  // Adjustments (multi-account bank variants)
  static const addBank    = 'ADD_BANK';
  static const cashToBank = 'CASH_TO_BANK';
  static const bankToCash = 'BANK_TO_CASH';
  static const bankToBank = 'BANK_TO_BANK';
}
