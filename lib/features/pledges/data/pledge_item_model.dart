class PledgeItemModel {
  const PledgeItemModel({
    this.id,
    required this.pledgeId,
    this.description,
    required this.weight,
    this.purity = '22K',
    this.estimatedValue = 0.0,
    this.photoPath,
    required this.createdAt,
  });

  final int? id;
  final int pledgeId;
  final String? description;
  final double weight;      // DB: net_weight
  final String purity;
  final double estimatedValue;
  final String? photoPath;  // DB: photo_path
  final String createdAt;

  factory PledgeItemModel.fromMap(Map<String, dynamic> map) {
    return PledgeItemModel(
      id: map['id'] as int?,
      pledgeId: map['pledge_id'] as int,
      description: map['description'] as String?,
      weight: (map['net_weight'] as num?)?.toDouble() ?? 0.0,
      purity: map['purity'] as String? ?? '22K',
      estimatedValue: 0.0,
      photoPath: map['photo_path'] as String?,
      createdAt: map['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'pledge_id': pledgeId,
      'item_type': 'gold',
      'description': description,
      'quantity': 1,
      'gross_weight': weight,
      'stone_weight': 0.0,
      'net_weight': weight,
      'purity': purity,
      'photo_path': photoPath,
      'created_at': createdAt,
    };
  }
}
