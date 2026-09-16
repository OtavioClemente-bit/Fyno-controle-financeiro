import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF147A5A);
  static const background = Color(0xFFF7FAF7);
  static const surface = Colors.white;

  static const success = Color(0xFF178A5B);
  static const danger = Color(0xFFBA1A1A);
  static const warning = Color(0xFFE07800);

  // Legacy aliases. New UI should prefer Theme.of(context).colorScheme so it
  // automatically adapts to dark mode.
  static const textStrong = Color(0xFF18201C);
  static const text = Color(0xFF303A34);
  static const textMuted = Color(0xFF68736C);
  static const border = Color(0xFFDDE5DF);
}
