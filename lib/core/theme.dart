import 'package:flutter/material.dart';

import 'app_colors.dart';

class _ThemeColors {
  const _ThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceLow,
    required this.surfaceHigh,
    required this.surfaceHighest,
    required this.primary,
    required this.primaryPressed,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.onPrimary,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderSubtle,
    required this.secondary,
    required this.secondaryLight,
  });

  final Color background;
  final Color surface;
  final Color surfaceLow;
  final Color surfaceHigh;
  final Color surfaceHighest;
  final Color primary;
  final Color primaryPressed;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color onPrimary;
  final Color text;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color borderSubtle;
  final Color secondary;
  final Color secondaryLight;
}

const _lightColors = _ThemeColors(
  background: AppColors.background,
  surface: AppColors.surface,
  surfaceLow: AppColors.surfaceLow,
  surfaceHigh: AppColors.surfaceHigh,
  surfaceHighest: AppColors.surfaceHighest,
  primary: AppColors.brand,
  primaryPressed: Color(0xFF004C99),
  primaryContainer: AppColors.brandLight,
  onPrimaryContainer: AppColors.brandDark,
  onPrimary: AppColors.onBrand,
  text: AppColors.text,
  textSecondary: AppColors.textSecondary,
  textMuted: AppColors.textMuted,
  border: AppColors.border,
  borderSubtle: AppColors.borderSubtle,
  secondary: AppColors.secondary,
  secondaryLight: AppColors.secondaryLight,
);

const _darkColors = _ThemeColors(
  background: AppColors.darkBackground,
  surface: AppColors.darkSurface,
  surfaceLow: AppColors.darkSurfaceLow,
  surfaceHigh: AppColors.darkSurfaceHigh,
  surfaceHighest: AppColors.darkSurfaceHighest,
  primary: AppColors.darkBrand,
  primaryPressed: AppColors.darkBrandPressed,
  primaryContainer: AppColors.darkBrandContainer,
  onPrimaryContainer: AppColors.darkBrand,
  onPrimary: AppColors.darkOnBrand,
  text: AppColors.darkText,
  textSecondary: AppColors.darkTextSecondary,
  textMuted: AppColors.darkTextMuted,
  border: AppColors.darkBorder,
  borderSubtle: AppColors.darkBorderSubtle,
  secondary: AppColors.darkSecondary,
  secondaryLight: AppColors.darkSecondaryLight,
);

class AppTheme {
  static ThemeData light() => _build(_lightColors, Brightness.light);

  static ThemeData dark() => _build(_darkColors, Brightness.dark);

  static ThemeData _build(_ThemeColors colors, Brightness brightness) {
    const controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );
    const panelShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(20)),
      side: BorderSide.none,
    );
    final scheme =
        ColorScheme.fromSeed(
          seedColor: colors.primary,
          brightness: brightness,
        ).copyWith(
          primary: colors.primary,
          onPrimary: colors.onPrimary,
          primaryContainer: colors.primaryContainer,
          onPrimaryContainer: colors.onPrimaryContainer,
          surface: colors.surface,
          onSurface: colors.text,
          onSurfaceVariant: colors.textSecondary,
          outline: colors.border,
          outlineVariant: colors.borderSubtle,
          surfaceContainerLowest: colors.surface,
          surfaceContainerLow: colors.surfaceLow,
          surfaceContainer: colors.background,
          surfaceContainerHigh: colors.surfaceHigh,
          surfaceContainerHighest: colors.surfaceHighest,
          surfaceTint: Colors.transparent,
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: '.SF Pro Text',
      fontFamilyFallback: const [
        'Helvetica Neue',
        'Arial',
        'Roboto',
        'sans-serif',
      ],
    );
    final primaryButton = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      shape: const WidgetStatePropertyAll(controlShape),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return colors.surfaceHigh;
        if (states.contains(WidgetState.pressed)) return colors.primaryPressed;
        if (states.contains(WidgetState.hovered)) return colors.primaryPressed;
        return colors.primary;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? colors.textMuted
            : colors.onPrimary,
      ),
    );
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      scaffoldBackgroundColor: colors.background,
      hoverColor: colors.primary.withValues(alpha: 0.08),
      focusColor: colors.primary.withValues(alpha: 0.14),
      splashFactory: NoSplash.splashFactory,
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: TextStyle(
              fontSize: 34,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
            headlineMedium: TextStyle(
              fontSize: 28,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
            titleLarge: TextStyle(
              fontSize: 20,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
            titleMedium: TextStyle(
              fontSize: 17,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
            bodyLarge: TextStyle(fontSize: 17, height: 1.5, color: colors.text),
            bodyMedium: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: colors.text,
            ),
          )
          .apply(fontFamily: '.SF Pro Text'),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: brightness == Brightness.dark
            ? Colors.black54
            : const Color(0x1A000000),
        surfaceTintColor: Colors.transparent,
        color: colors.surface,
        shape: panelShape,
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: colors.surface,
        foregroundColor: colors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: brightness == Brightness.dark
            ? Colors.black54
            : const Color(0x14000000),
        titleTextStyle: TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
        shape: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButton),
      filledButtonTheme: FilledButtonThemeData(style: primaryButton),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 44),
          foregroundColor: colors.text,
          backgroundColor: colors.surface,
          side: BorderSide(color: colors.border),
          shape: controlShape,
          textStyle: const TextStyle(
            fontFamily: '.SF Pro Text',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: colors.primary,
          shape: controlShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.textSecondary,
          shape: controlShape,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: panelShape,
        elevation: 16,
        shadowColor: Colors.black38,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.surfaceLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        elevation: 8,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: panelShape,
        elevation: 4,
      ),
      dividerTheme: DividerThemeData(
        space: 24,
        thickness: 0.5,
        color: colors.borderSubtle,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceLow,
        selectedColor: colors.primaryContainer,
        side: BorderSide(color: colors.borderSubtle),
        shape: controlShape,
        labelStyle: TextStyle(fontSize: 12, color: colors.textSecondary),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(colors.surfaceLow),
        headingTextStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
        dataTextStyle: TextStyle(fontSize: 14, color: colors.text),
        dividerThickness: 1,
        horizontalMargin: 20,
        columnSpacing: 24,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
        border: inputBorder(colors.border),
        enabledBorder: inputBorder(colors.border),
        focusedBorder: inputBorder(colors.primary, 2),
        errorBorder: inputBorder(scheme.error),
        focusedErrorBorder: inputBorder(scheme.error, 2),
      ),
    );
  }
}
