class PledgeModel {
  const PledgeModel({
    this.id,
    required this.pledgeNumber,
    required this.pledgeDate,
    required this.loanAmount,
    required this.interestRate,
    required this.status,
    this.closureDate,
    this.totalInterestPaid = 0.0,
    this.totalAmountCollected = 0.0,
    this.source,
    this.renewalParentId,
    this.notes,
    required this.createdAt,
    required this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.grossWeight = 0.0,
    this.netWeight = 0.0,
    this.purity = '22K',
    this.goldRate = 0.0,
    this.pledgeRate = 0.0,
  });

  final int? id;
  final String pledgeNumber;    // DB: pledge_no
  final String pledgeDate;      // DB: start_date (ISO 8601 date string YYYY-MM-DD)
  final double loanAmount;      // DB: principal_amount
  final double interestRate;
  final String status;          // open / closed / renewed / migrated
  final String? closureDate;    // DB: closure_date
  final double totalInterestPaid;
  final double totalAmountCollected;
  final String? source;
  final int? renewalParentId;
  final String? notes;
  final String createdAt;
  final String customerName;
  final String? customerPhone;
  final String? customerAddress;
  final double grossWeight;
  final double netWeight;
  final String purity;
  final double goldRate;
  final double pledgeRate;

  factory PledgeModel.fromMap(Map<String, dynamic> map) {
    return PledgeModel(
      id: map['id'] as int?,
      pledgeNumber: map['pledge_no'] as String? ?? '',
      pledgeDate: map['start_date'] as String? ?? '',
      loanAmount: (map['principal_amount'] as num?)?.toDouble() ?? 0.0,
      interestRate: (map['interest_rate'] as num?)?.toDouble() ?? 18.0,
      status: map['status'] as String? ?? 'open',
      closureDate: map['closure_date'] as String?,
      totalInterestPaid:
          (map['total_interest_paid'] as num?)?.toDouble() ?? 0.0,
      totalAmountCollected:
          (map['total_amount_collected'] as num?)?.toDouble() ?? 0.0,
      source: map['source'] as String?,
      renewalParentId: map['renewal_parent_id'] as int?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] as String? ?? '',
      customerName: map['customer_name'] as String? ?? '',
      customerPhone: map['customer_phone'] as String?,
      customerAddress: map['customer_address'] as String?,
      grossWeight: (map['gross_weight'] as num?)?.toDouble() ?? 0.0,
      netWeight: (map['net_weight'] as num?)?.toDouble() ?? 0.0,
      purity: map['purity'] as String? ?? '22K',
      goldRate: (map['gold_rate'] as num?)?.toDouble() ?? 0.0,
      pledgeRate: (map['pledge_rate'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'pledge_no': pledgeNumber,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_address': customerAddress,
      'gross_weight': grossWeight,
      'stone_weight': 0.0,
      'net_weight': netWeight,
      'purity': purity,
      'gold_rate': goldRate,
      'pledge_rate': pledgeRate,
      'principal_amount': loanAmount,
      'interest_rate': interestRate,
      'start_date': pledgeDate,
      'status': status,
      'closed_at': closureDate,
      'closure_date': closureDate,
      'source': source,
      'renewal_parent_id': renewalParentId,
      'total_interest_paid': totalInterestPaid,
      'total_amount_collected': totalAmountCollected,
      'notes': notes,
      'created_by': null,
      'created_at': createdAt,
      'updated_at': createdAt,
    };
  }

  PledgeModel copyWith({
    String? status,
    String? closureDate,
    double? totalInterestPaid,
    double? totalAmountCollected,
  }) {
    return PledgeModel(
      id: id,
      pledgeNumber: pledgeNumber,
      pledgeDate: pledgeDate,
      loanAmount: loanAmount,
      interestRate: interestRate,
      status: status ?? this.status,
      closureDate: closureDate ?? this.closureDate,
      totalInterestPaid: totalInterestPaid ?? this.totalInterestPaid,
      totalAmountCollected:
          totalAmountCollected ?? this.totalAmountCollected,
      source: source,
      renewalParentId: renewalParentId,
      notes: notes,
      createdAt: createdAt,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
      grossWeight: grossWeight,
      netWeight: netWeight,
      purity: purity,
      goldRate: goldRate,
      pledgeRate: pledgeRate,
    );
  }
}
