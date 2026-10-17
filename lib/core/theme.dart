import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData light() {
    const controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
    );
    const panelShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
      side: BorderSide(color: AppColors.borderSubtle),
    );
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand).copyWith(
      primary: AppColors.brand,
      onPrimary: AppColors.onBrand,
      primaryContainer: AppColors.brandLight,
      onPrimaryContainer: AppColors.brandDark,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.borderSubtle,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.surfaceLow,
      surfaceContainer: AppColors.background,
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainerHighest: AppColors.surfaceHighest,
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
    );
    final primaryButton = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      shape: const WidgetStatePropertyAll(controlShape),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return AppColors.surfaceHigh;
        if (states.contains(WidgetState.pressed))
          return const Color(0xFF0C3B5E);
        if (states.contains(WidgetState.hovered)) return AppColors.brandDark;
        return AppColors.brand;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? AppColors.textMuted
            : Colors.white,
      ),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      hoverColor: AppColors.brand.withValues(alpha: 0.06),
      focusColor: AppColors.brand.withValues(alpha: 0.12),
      splashFactory: NoSplash.splashFactory,
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: const TextStyle(
              fontSize: 32,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
            headlineMedium: const TextStyle(
              fontSize: 28,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
            titleLarge: const TextStyle(
              fontSize: 20,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
            titleMedium: const TextStyle(
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
            bodyLarge: const TextStyle(
              fontSize: 16,
              height: 1.5,
              color: AppColors.text,
            ),
            bodyMedium: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.text,
            ),
          )
          .apply(fontFamily: 'Segoe UI'),
      cardTheme: const CardThemeData(
        elevation: 1,
        shadowColor: Color(0x1A000000),
        surfaceTintColor: Colors.transparent,
        color: AppColors.surface,
        shape: panelShape,
        margin: EdgeInsets.zero,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Color(0x14000000),
        titleTextStyle: TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        shape: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButton),
      filledButtonTheme: FilledButtonThemeData(style: primaryButton),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 44),
          foregroundColor: AppColors.text,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.border),
          shape: controlShape,
          textStyle: const TextStyle(
            fontFamily: 'Segoe UI',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: AppColors.brand,
          shape: controlShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          shape: controlShape,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: panelShape,
        elevation: 16,
        shadowColor: Color(0x30000000),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surfaceLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(),
        elevation: 8,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: panelShape,
        elevation: 4,
      ),
      dividerTheme: const DividerThemeData(
        space: 24,
        thickness: 1,
        color: AppColors.borderSubtle,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceLow,
        selectedColor: AppColors.brandLight,
        side: const BorderSide(color: AppColors.borderSubtle),
        shape: controlShape,
        labelStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(AppColors.surfaceLow),
        headingTextStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        dataTextStyle: TextStyle(fontSize: 14, color: AppColors.text),
        dividerThickness: 1,
        horizontalMargin: 20,
        columnSpacing: 24,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        border: inputBorder(AppColors.border),
        enabledBorder: inputBorder(AppColors.border),
        focusedBorder: inputBorder(AppColors.brand, 2),
        errorBorder: inputBorder(scheme.error),
        focusedErrorBorder: inputBorder(scheme.error, 2),
      ),
    );
  }
}
