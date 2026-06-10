class PaymentModel {
  const PaymentModel({
    this.id,
    required this.pledgeId,
    required this.paymentDate,
    required this.amount,
    this.cashAmount = 0.0,
    this.upiAmount = 0.0,
    required this.paymentType,
    this.paymentMode = 'cash',
    this.notes,
    required this.createdAt,
  });

  final int? id;
  final int pledgeId;
  final String paymentDate;   // DB: paid_at (ISO 8601)
  final double amount;
  final double cashAmount;    // DB: cash_amount
  final double upiAmount;     // DB: upi_amount
  final String paymentType;   // interest / principal / closure / renewal
  final String paymentMode;   // cash / upi / split / bank
  final String? notes;
  final String createdAt;

  factory PaymentModel.fromMap(Map<String, dynamic> map) {
    return PaymentModel(
      id: map['id'] as int?,
      pledgeId: map['pledge_id'] as int,
      paymentDate: map['paid_at'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      cashAmount: (map['cash_amount'] as num?)?.toDouble() ?? 0.0,
      upiAmount: (map['upi_amount'] as num?)?.toDouble() ?? 0.0,
      paymentType: map['payment_type'] as String? ?? 'closure',
      paymentMode: map['payment_mode'] as String? ?? 'cash',
      notes: map['notes'] as String?,
      createdAt: map['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'pledge_id': pledgeId,
      'payment_type': paymentType,
      'amount': amount,
      'cash_amount': cashAmount,
      'upi_amount': upiAmount,
      'interest_amount': 0.0,
      'principal_amount': 0.0,
      'payment_mode': paymentMode,
      'paid_at': paymentDate,
      'notes': notes,
      'created_by': null,
      'created_at': createdAt,
    };
  }
}
