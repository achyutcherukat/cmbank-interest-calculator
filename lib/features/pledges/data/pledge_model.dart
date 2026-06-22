import 'dart:convert';

List<String>? _parseJsonList(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    return (jsonDecode(json) as List).cast<String>();
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _parseJsonMap(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

/// A pledge (`pledges` table).
///
/// Customer identity now lives in the `customers` table (via `customer_id`)
/// with a denormalised `customer_snapshot` JSON kept on the pledge as a
/// fallback. The model still exposes [customerName] / [customerPhone] /
/// [customerAddress] (read from the snapshot) so existing screens keep working,
/// but these are NOT written back as pledge columns.
///
/// Gold photos live on the pledge (`gold_photo_paths`). Item-level purity lives
/// on `pledge_items`, so [purity] here is informational only and defaults to ''.
class PledgeModel {
  const PledgeModel({
    this.id,
    required this.pledgeNumber,
    required this.pledgeDate,
    required this.loanAmount,
    required this.interestRate,
    required this.status,
    this.renewType,
    this.renewSubtype,
    this.closureDate,
    this.closedAt,
    this.totalInterestPaid = 0.0,
    this.totalAmountCollected = 0.0,
    this.source = 'new',
    this.renewalParentId,
    this.notes,
    this.goldPhotoPaths,
    this.formPhotoPaths,
    required this.createdAt,
    this.customerId,
    this.customerSnapshot,
    this.grossWeight = 0.0,
    this.netWeight = 0.0,
    this.purity = '',
    this.goldRate = 0.0,
    this.pledgeRate = 0.0,
    this.actualItemValue = 0.0,
  });

  final int? id;
  final String pledgeNumber; // DB: pledge_no
  final String pledgeDate; // DB: start_date (ISO 8601 YYYY-MM-DD)
  final double loanAmount; // DB: principal_amount
  final double interestRate;
  final String status; // open / closed
  final String? renewType; // DB: renew_type (RenewType)
  final String? renewSubtype; // DB: renew_subtype (RenewSubtype)
  final String? closureDate; // DB: closure_date
  final String? closedAt; // DB: closed_at (timestamp)
  final double totalInterestPaid;
  final double totalAmountCollected;
  final String source; // new / migrated
  final int? renewalParentId;
  final String? notes;
  final List<String>? goldPhotoPaths; // DB: gold_photo_paths (JSON array)
  final List<String>? formPhotoPaths; // DB: form_photo_paths (JSON array)
  final String createdAt;
  final int? customerId; // DB: customer_id (FK to customers)
  final Map<String, dynamic>? customerSnapshot; // DB: customer_snapshot (JSON)
  final double grossWeight;
  final double netWeight;
  final String purity; // item-level; '' at pledge level
  final double goldRate;
  final double pledgeRate;
  final double actualItemValue; // gold_rate × net_weight

  // ── Customer convenience getters (from snapshot) ─────────────────────────────

  String get customerName =>
      (customerSnapshot?['name'] as String?)?.trim() ?? '';
  String? get customerPhone => customerSnapshot?['phone'] as String?;
  String? get customerAddress => customerSnapshot?['address'] as String?;

  factory PledgeModel.fromMap(Map<String, dynamic> map) {
    return PledgeModel(
      id: map['id'] as int?,
      pledgeNumber: map['pledge_no'] as String? ?? '',
      pledgeDate: map['start_date'] as String? ?? '',
      loanAmount: (map['principal_amount'] as num?)?.toDouble() ?? 0.0,
      interestRate: (map['interest_rate'] as num?)?.toDouble() ?? 18.0,
      status: map['status'] as String? ?? 'open',
      renewType: map['renew_type'] as String?,
      renewSubtype: map['renew_subtype'] as String?,
      closureDate: map['closure_date'] as String?,
      closedAt: map['closed_at'] as String?,
      totalInterestPaid:
          (map['total_interest_paid'] as num?)?.toDouble() ?? 0.0,
      totalAmountCollected:
          (map['total_amount_collected'] as num?)?.toDouble() ?? 0.0,
      source: map['source'] as String? ?? 'new',
      renewalParentId: map['renewal_parent_id'] as int?,
      notes: map['notes'] as String?,
      goldPhotoPaths: _parseJsonList(map['gold_photo_paths'] as String?),
      formPhotoPaths: _parseJsonList(map['form_photo_paths'] as String?),
      createdAt: map['created_at'] as String? ?? '',
      customerId: map['customer_id'] as int?,
      customerSnapshot: _parseJsonMap(map['customer_snapshot'] as String?),
      grossWeight: (map['gross_weight'] as num?)?.toDouble() ?? 0.0,
      netWeight: (map['net_weight'] as num?)?.toDouble() ?? 0.0,
      purity: map['purity'] as String? ?? '',
      goldRate: (map['gold_rate'] as num?)?.toDouble() ?? 0.0,
      pledgeRate: (map['pledge_rate'] as num?)?.toDouble() ?? 0.0,
      actualItemValue: (map['actual_item_value'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'pledge_no': pledgeNumber,
      'start_date': pledgeDate,
      'principal_amount': loanAmount,
      'interest_rate': interestRate,
      'status': status,
      'renew_type': renewType,
      'renew_subtype': renewSubtype,
      'closure_date': closureDate,
      'closed_at': closedAt,
      'total_interest_paid': totalInterestPaid,
      'total_amount_collected': totalAmountCollected,
      'source': source,
      'renewal_parent_id': renewalParentId,
      'gross_weight': grossWeight,
      'net_weight': netWeight,
      'pledge_rate': pledgeRate,
      'gold_rate': goldRate,
      'actual_item_value': actualItemValue,
      'gold_photo_paths':
          goldPhotoPaths != null ? jsonEncode(goldPhotoPaths!) : null,
      'form_photo_paths':
          formPhotoPaths != null ? jsonEncode(formPhotoPaths!) : null,
      'customer_id': customerId,
      'customer_snapshot':
          customerSnapshot != null ? jsonEncode(customerSnapshot!) : null,
      'notes': notes,
      'created_by': null,
      'created_at': createdAt,
      'updated_at': createdAt,
    };
  }

  PledgeModel copyWith({
    int? id,
    String? pledgeNumber,
    String? pledgeDate,
    double? loanAmount,
    double? interestRate,
    String? status,
    String? renewType,
    String? renewSubtype,
    String? closureDate,
    String? closedAt,
    double? totalInterestPaid,
    double? totalAmountCollected,
    String? source,
    int? renewalParentId,
    List<String>? goldPhotoPaths,
    List<String>? formPhotoPaths,
    int? customerId,
    Map<String, dynamic>? customerSnapshot,
  }) {
    return PledgeModel(
      id: id ?? this.id,
      pledgeNumber: pledgeNumber ?? this.pledgeNumber,
      pledgeDate: pledgeDate ?? this.pledgeDate,
      loanAmount: loanAmount ?? this.loanAmount,
      interestRate: interestRate ?? this.interestRate,
      status: status ?? this.status,
      renewType: renewType ?? this.renewType,
      renewSubtype: renewSubtype ?? this.renewSubtype,
      closureDate: closureDate ?? this.closureDate,
      closedAt: closedAt ?? this.closedAt,
      totalInterestPaid: totalInterestPaid ?? this.totalInterestPaid,
      totalAmountCollected: totalAmountCollected ?? this.totalAmountCollected,
      source: source ?? this.source,
      renewalParentId: renewalParentId ?? this.renewalParentId,
      notes: notes,
      goldPhotoPaths: goldPhotoPaths ?? this.goldPhotoPaths,
      formPhotoPaths: formPhotoPaths ?? this.formPhotoPaths,
      createdAt: createdAt,
      customerId: customerId ?? this.customerId,
      customerSnapshot: customerSnapshot ?? this.customerSnapshot,
      grossWeight: grossWeight,
      netWeight: netWeight,
      purity: purity,
      goldRate: goldRate,
      pledgeRate: pledgeRate,
      actualItemValue: actualItemValue,
    );
  }
}

/// Canonical `renew_type` values.
class RenewType {
  const RenewType._();

  static const renewed = 'RENEWED';
  static const partPayment = 'PART_PAYMENT';
  static const loanIncrease = 'LOAN_INCREASE';
}

/// Canonical `renew_subtype` values, grouped by renew type.
class RenewSubtype {
  const RenewSubtype._();

  // RENEWED
  static const interestPaid = 'INTEREST_PAID';
  static const interestCapitalised = 'INTEREST_CAPITALISED';

  // PART_PAYMENT
  static const principalAndInterest = 'PRINCIPAL_AND_INTEREST';
  static const fixedAmountInclusive = 'FIXED_AMOUNT_INCLUSIVE';

  // LOAN_INCREASE
  static const interestNotCapitalised = 'INTEREST_NOT_CAPITALISED';
  static const loanIncreaseInterestCapitalised = 'INTEREST_CAPITALISED';
}

/// Human-readable label for a renew_type + renew_subtype combination.
String renewalLabel(String? renewType, String? renewSubtype) {
  switch (renewType) {
    case RenewType.renewed:
      return renewSubtype == RenewSubtype.interestCapitalised
          ? 'Renewed — Interest Capitalised'
          : 'Renewed — Interest Paid';
    case RenewType.partPayment:
      return renewSubtype == RenewSubtype.fixedAmountInclusive
          ? 'Part Payment — Fixed Amount'
          : 'Part Payment — Principal & Interest';
    case RenewType.loanIncrease:
      return renewSubtype == RenewSubtype.loanIncreaseInterestCapitalised
          ? 'Loan Top-Up — Interest Capitalised'
          : 'Loan Top-Up — Interest Paid';
    default:
      return 'Closed';
  }
}
