/// One gold item belonging to a pledge (`pledge_items` table).
///
/// Photos are no longer stored per item — gold photos now live at the pledge
/// level (`pledges.gold_photo_paths`). The `stone_weight` column has been
/// dropped as well.
class PledgeItemModel {
  const PledgeItemModel({
    this.id,
    required this.pledgeId,
    this.itemType = 'Other',
    this.description,
    this.quantity = 1,
    this.grossWeight = 0.0,
    required this.netWeight,
    this.purity = '',
    this.notes,
    required this.createdAt,
  });

  final int? id;
  final int pledgeId;
  final String itemType; // DB: item_type (value from item_types table)
  final String? description; // DB: description
  final int quantity; // DB: quantity
  final double grossWeight; // DB: gross_weight
  final double netWeight; // DB: net_weight
  final String purity; // DB: purity (value from purity_types table)
  final String? notes; // DB: notes
  final String createdAt;

  factory PledgeItemModel.fromMap(Map<String, dynamic> map) {
    return PledgeItemModel(
      id: map['id'] as int?,
      pledgeId: map['pledge_id'] as int? ?? 0,
      itemType: map['item_type'] as String? ?? 'Other',
      description: map['description'] as String?,
      quantity: (map['quantity'] as int?) ?? 1,
      grossWeight: (map['gross_weight'] as num?)?.toDouble() ?? 0.0,
      netWeight: (map['net_weight'] as num?)?.toDouble() ?? 0.0,
      purity: map['purity'] as String? ?? '',
      notes: map['notes'] as String?,
      createdAt: map['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'pledge_id': pledgeId,
      'item_type': itemType,
      'description': description,
      'quantity': quantity,
      'gross_weight': grossWeight,
      'net_weight': netWeight,
      'purity': purity,
      'notes': notes,
      'created_at': createdAt,
    };
  }
}
