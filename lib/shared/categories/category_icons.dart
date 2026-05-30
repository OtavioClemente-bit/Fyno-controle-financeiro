import 'package:flutter/material.dart';

/// Ícones disponíveis para categorias customizadas.
/// Persistimos apenas a `key` no banco (icon_key).
class CategoryIcons {
  static const Map<String, IconData> map = {
    'shopping_cart': Icons.shopping_cart,
    'local_grocery_store': Icons.local_grocery_store,
    'restaurant': Icons.restaurant,
    'local_cafe': Icons.local_cafe,
    'home': Icons.home,
    'bolt': Icons.bolt,
    'water_drop': Icons.water_drop,
    'wifi': Icons.wifi,
    'directions_car': Icons.directions_car,
    'local_gas_station': Icons.local_gas_station,
    'commute': Icons.commute,
    'medical_services': Icons.medical_services,
    'fitness_center': Icons.fitness_center,
    'school': Icons.school,
    'shopping_bag': Icons.shopping_bag,
    'attach_money': Icons.attach_money,
    'card_giftcard': Icons.card_giftcard,
    'sports_esports': Icons.sports_esports,
    'movie': Icons.movie,
    'pets': Icons.pets,
    'work': Icons.work,
    'savings': Icons.savings,
    'payments': Icons.payments,
    'receipt_long': Icons.receipt_long,
    'more_horiz': Icons.more_horiz,
  };

  static List<String> keys() => map.keys.toList(growable: false);

  static IconData of(String? key) => map[key] ?? Icons.label;

  static String normalizeKey(String key) => map.containsKey(key) ? key : 'more_horiz';
}
