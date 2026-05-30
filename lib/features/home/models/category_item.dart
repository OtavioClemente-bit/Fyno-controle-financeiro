class CategoryItem {
  final int? id;
  final String name;
  final String iconKey;
  final int createdAtMs;

  const CategoryItem({
    this.id,
    required this.name,
    required this.iconKey,
    required this.createdAtMs,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'icon_key': iconKey,
        'created_at_ms': createdAtMs,
      };

  static CategoryItem fromMap(Map<String, Object?> m) => CategoryItem(
        id: (m['id'] as int?),
        name: (m['name'] as String? ?? '').trim(),
        iconKey: (m['icon_key'] as String? ?? 'more_horiz').trim(),
        createdAtMs: (m['created_at_ms'] as int?) ?? 0,
      );
}
