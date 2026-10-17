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
    border: Border.all(color: AppColors.borderSubtle, width: 0.5),
  );
}
