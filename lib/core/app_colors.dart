import 'package:flutter/material.dart';

/// Shared Apple HIG-inspired UI colors. Map status and QR colors remain separate.
abstract final class AppColors {
  static const background = Color(0xFFFFFBF3);
  static const surface = Colors.white;
  static const surfaceLow = Color(0xFFFFF8EA);
  static const surfaceHigh = Color(0xFFF2E9D6);
  static const surfaceHighest = Color(0xFFEBDDBD);
  static const brand = Color(0xFF123D27);
  static const brandDark = Color(0xFF0B301E);
  static const brandLight = Color(0xFFFFE6A1);
  static const onBrand = Colors.white;
  static const text = Color(0xFF1C1C1E);
  static const textSecondary = Color(0xFF636366);
  static const textMuted = Color(0xFF6C6C70);
  static const border = Color(0xFFD9CCB0);
  static const borderSubtle = Color(0xFFF0E7D3);
  static const secondary = Color(0xFF8A6421);
  static const secondaryLight = Color(0xFFFFF0C7);

  // Dark surfaces retain the evergreen brand while providing enough contrast
  // for low-light use and OLED displays.
  static const darkBackground = Color(0xFF0F1115);
  static const darkSurface = Color(0xFF171A21);
  static const darkSurfaceLow = Color(0xFF13161C);
  static const darkSurfaceHigh = Color(0xFF20242C);
  static const darkSurfaceHighest = Color(0xFF2A303A);
  static const darkBrand = Color(0xFFE2B649);
  static const darkBrandPressed = Color(0xFFFFD878);
  static const darkBrandContainer = Color(0xFF4A3A14);
  static const darkOnBrand = Color(0xFF231B08);
  static const darkText = Color(0xFFF5F7FA);
  static const darkTextSecondary = Color(0xFFB9C0CB);
  static const darkTextMuted = Color(0xFF929AA7);
  static const darkBorder = Color(0xFF3A424F);
  static const darkBorderSubtle = Color(0xFF2A303A);
  static const darkSecondary = Color(0xFFC4C5E8);
  static const darkSecondaryLight = Color(0xFF27283F);
}
