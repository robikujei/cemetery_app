import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Solid Fluent-style surfaces with a fine stroke and restrained elevation.
class SurfaceStyle {
  static BoxDecoration panel({
    Color color = AppColors.surface,
    double radius = 8,
  }) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppColors.borderSubtle),
    boxShadow: const [
      BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
      BoxShadow(color: Color(0x08000000), blurRadius: 1, offset: Offset(0, 1)),
    ],
  );
}
