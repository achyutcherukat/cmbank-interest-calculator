import 'dart:convert';

class PledgeItemModel {
  const PledgeItemModel({
    this.id,
    required this.pledgeId,
    this.itemType = 'other',
    this.grossWeight = 0.0,
    required this.netWeight,
    this.purity = '',
    this.notes,
    this.photoPaths = const [],
    required this.createdAt,
  });

  final int? id;
  final int pledgeId;
  final String itemType;
  final double grossWeight;
  final double netWeight;   // DB: net_weight
  final String purity;
  final String? notes;      // DB: notes / description
  final List<String> photoPaths; // DB: photo_paths (JSON array)
  final String createdAt;

  factory PledgeItemModel.fromMap(Map<String, dynamic> map) {
    List<String> paths = [];
    final pathsJson = map['photo_paths'] as String?;
    if (pathsJson != null && pathsJson.isNotEmpty) {
      try {
        paths = (jsonDecode(pathsJson) as List).cast<String>();
      } catch (_) {}
    }
    if (paths.isEmpty) {
      final single = map['photo_path'] as String?;
      if (single != null && single.isNotEmpty) paths = [single];
    }

    return PledgeItemModel(
      id: map['id'] as int?,
      pledgeId: map['pledge_id'] as int? ?? 0,
      itemType: map['item_type'] as String? ?? 'other',
      grossWeight: (map['gross_weight'] as num?)?.toDouble() ?? 0.0,
      netWeight: (map['net_weight'] as num?)?.toDouble() ?? 0.0,
      purity: map['purity'] as String? ?? '',
      notes: (map['notes'] as String?) ?? (map['description'] as String?),
      photoPaths: paths,
      createdAt: map['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'pledge_id': pledgeId,
      'item_type': itemType,
      'description': notes,
      'quantity': 1,
      'gross_weight': grossWeight,
      'stone_weight': 0.0,
      'net_weight': netWeight,
      'purity': purity,
      'photo_path': photoPaths.isNotEmpty ? photoPaths.first : null,
      'photo_paths': jsonEncode(photoPaths),
      'notes': notes,
      'created_at': createdAt,
    };
  }
}
