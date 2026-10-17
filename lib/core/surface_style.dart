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
    boxShadow: const [
      BoxShadow(color: Color(0x0A000000), blurRadius: 16, offset: Offset(0, 4)),
    ],
  );
}
