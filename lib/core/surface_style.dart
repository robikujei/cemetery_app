import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Grouped surfaces with soft corners and subtle depth.
class SurfaceStyle {
  static BoxDecoration panel({
    Color color = AppColors.surface,
    double radius = 20,
  }) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    // Derive the border from the surface itself so panels remain readable in
    // both themes instead of carrying the light palette into dark mode.
    border: Border.all(color: color.withValues(alpha: 0.12), width: 0.5),
  );
}
