import 'package:flutter/material.dart';

extension ThemeDataExtensions on ThemeData {
  bool get isDark => brightness == Brightness.dark;

  // Couleurs pour le shimmer
  Color get shimmerBaseColor => isDark ? Colors.grey.shade700 : Colors.grey.shade300;
  Color get shimmerHighlightColor => isDark ? Colors.grey.shade800 : Colors.grey.shade200;
}
