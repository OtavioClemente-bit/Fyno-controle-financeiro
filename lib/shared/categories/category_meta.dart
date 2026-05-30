import 'package:flutter/material.dart';

class CategoryMeta {
  final String name;
  final IconData icon;
  final Color color;

  const CategoryMeta({
    required this.name,
    required this.icon,
    required this.color,
  });
}

class Categories {
  static const CategoryMeta mercado = CategoryMeta(
    name: 'Mercado',
    icon: Icons.shopping_cart,
    color: Color(0xFF2E7D32),
  );

  static const CategoryMeta combustivel = CategoryMeta(
    name: 'Combustível',
    icon: Icons.local_gas_station,
    color: Color(0xFFF57C00),
  );

  static const CategoryMeta casa = CategoryMeta(
    name: 'Casa',
    icon: Icons.home,
    color: Color(0xFF1565C0),
  );

  static const CategoryMeta saude = CategoryMeta(
    name: 'Saúde',
    icon: Icons.health_and_safety,
    color: Color(0xFFC62828),
  );

  static const CategoryMeta lazer = CategoryMeta(
    name: 'Lazer',
    icon: Icons.sports_esports,
    color: Color(0xFF6A1B9A),
  );

  static const CategoryMeta transporte = CategoryMeta(
    name: 'Transporte',
    icon: Icons.directions_car,
    color: Color(0xFF37474F),
  );

  static const CategoryMeta outros = CategoryMeta(
    name: 'Outros',
    icon: Icons.category,
    color: Color(0xFF455A64),
  );

  static const List<CategoryMeta> all = [
    mercado,
    combustivel,
    casa,
    saude,
    lazer,
    transporte,
    outros,
  ];

  /// 🔎 Busca metadata pelo nome salvo no banco
  static CategoryMeta of(String name) {
    final normalized = _normalize(name);

    for (final c in all) {
      if (_normalize(c.name) == normalized) {
        return c;
      }
    }
    return outros;
  }

  /// Remove acentos, espaços extras e deixa minúsculo
  static String _normalize(String s) {
    return s
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
  }
}
