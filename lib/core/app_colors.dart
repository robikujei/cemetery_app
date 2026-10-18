import 'package:flutter/material.dart';

/// Shared Apple HIG-inspired UI colors. Map status and QR colors remain separate.
abstract final class AppColors {
  static const background = Color(0xFFF2F2F7);
  static const surface = Colors.white;
  static const surfaceLow = Color(0xFFF7F7FA);
  static const surfaceHigh = Color(0xFFEFEFF4);
  static const surfaceHighest = Color(0xFFE5E5EA);
  static const brand = Color(0xFF0066CC);
  static const brandDark = Color(0xFF0055B3);
  static const brandLight = Color(0xFFE8F2FF);
  static const onBrand = Colors.white;
  static const text = Color(0xFF1C1C1E);
  static const textSecondary = Color(0xFF636366);
  static const textMuted = Color(0xFF6C6C70);
  static const border = Color(0xFFD1D1D6);
  static const borderSubtle = Color(0xFFE5E5EA);
  static const secondary = Color(0xFF48486A);
  static const secondaryLight = Color(0xFFF0EFF8);

  // Dark surfaces keep the same blue brand while providing enough contrast
  // for low-light use and OLED displays.
  static const darkBackground = Color(0xFF0F1115);
  static const darkSurface = Color(0xFF171A21);
  static const darkSurfaceLow = Color(0xFF13161C);
  static const darkSurfaceHigh = Color(0xFF20242C);
  static const darkSurfaceHighest = Color(0xFF2A303A);
  static const darkBrand = Color(0xFF66B2FF);
  static const darkBrandPressed = Color(0xFF9DCEFF);
  static const darkBrandContainer = Color(0xFF153B61);
  static const darkOnBrand = Color(0xFF00284D);
  static const darkText = Color(0xFFF5F7FA);
  static const darkTextSecondary = Color(0xFFB9C0CB);
  static const darkTextMuted = Color(0xFF929AA7);
  static const darkBorder = Color(0xFF3A424F);
  static const darkBorderSubtle = Color(0xFF2A303A);
  static const darkSecondary = Color(0xFFC4C5E8);
  static const darkSecondaryLight = Color(0xFF27283F);
}
