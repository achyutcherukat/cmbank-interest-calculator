/// A configurable lookup value (item type or purity type).
class LookupType {
  const LookupType({
    required this.id,
    required this.name,
    required this.displayOrder,
    required this.isActive,
  });

  final int id;
  final String name;
  final int displayOrder;
  final bool isActive;

  factory LookupType.fromMap(Map<String, dynamic> map) {
    return LookupType(
      id: map['id'] as int,
      name: map['name'] as String? ?? '',
      displayOrder: (map['display_order'] as int?) ?? 0,
      isActive: (map['is_active'] as int?) == 1,
    );
  }
}
