import 'package:flutter/material.dart';

IconData financeCategoryIcon(String value) {
  final text = value.toLowerCase();
  if (text.contains('combust') || text.contains('gas')) {
    return Icons.local_gas_station_rounded;
  }
  if (text.contains('alimenta')) return Icons.restaurant_rounded;
  if (text.contains('mercado')) return Icons.shopping_cart_rounded;
  if (text.contains('assinatura')) return Icons.subscriptions_rounded;
  if (text.contains('conta')) return Icons.receipt_long_rounded;
  if (text.contains('moradia') || text.contains('alug')) {
    return Icons.home_rounded;
  }
  if (text.contains('educa')) return Icons.school_rounded;
  if (text.contains('saúde') || text.contains('saude')) {
    return Icons.health_and_safety_rounded;
  }
  if (text.contains('lazer')) return Icons.movie_rounded;
  if (text.contains('transporte')) return Icons.directions_bus_rounded;
  return Icons.account_balance_wallet_rounded;
}

BrandVisual recurringBrandVisual(String value) {
  final text = value.toLowerCase();
  if (text.contains('youtube')) {
    return const BrandVisual(Icons.play_arrow_rounded, Color(0xFFFF0033));
  }
  if (text.contains('spotify')) {
    return const BrandVisual(Icons.graphic_eq_rounded, Color(0xFF1DB954));
  }
  if (text.contains('crunchyroll')) {
    return const BrandVisual(Icons.play_circle_fill_rounded, Color(0xFFF47521));
  }
  if (text.contains('netflix')) {
    return const BrandVisual(Icons.movie_filter_rounded, Color(0xFFE50914));
  }
  if (text.contains('prime')) {
    return const BrandVisual(Icons.play_circle_rounded, Color(0xFF00A8E1));
  }
  if (text.contains('disney')) {
    return const BrandVisual(Icons.auto_awesome_rounded, Color(0xFF3151A3));
  }
  if (text.contains('academia')) {
    return const BrandVisual(Icons.fitness_center_rounded, Color(0xFF7C4DFF));
  }
  if (text.contains('internet') || text.contains('wifi')) {
    return const BrandVisual(Icons.wifi_rounded, Color(0xFF0288D1));
  }
  return const BrandVisual(Icons.calendar_month_rounded, Color(0xFF168567));
}

class BrandVisual {
  const BrandVisual(this.icon, this.color);
  final IconData icon;
  final Color color;
}
