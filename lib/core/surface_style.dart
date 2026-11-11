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
    border: Border.all(color: color.withValues(alpha: 0.18), width: 1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ],
  );
}
