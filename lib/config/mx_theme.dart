import 'package:flutter/material.dart';
import 'mx_colors.dart';
import 'mx_type.dart';

/// Central [ThemeData] for MYCOSIX — light, warm, editorial.
class MxTheme {
  MxTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: MxColors.cream,
      colorScheme: const ColorScheme.light(
        primary: MxColors.moss,
        onPrimary: Colors.white,
        secondary: MxColors.earth,
        onSecondary: Colors.white,
        surface: MxColors.creamSoft,
        onSurface: MxColors.charcoal,
        error: MxColors.danger,
        onError: Colors.white,
      ),
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: MxType.h1(1440),
        displayMedium: MxType.h2(1440),
        bodyLarge: MxType.body(1440),
        bodyMedium: MxType.bodySm(),
        labelLarge: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
      dividerColor: MxColors.line,
      splashColor: MxColors.moss.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
      inputDecorationTheme: _inputDecoration(),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MxColors.glow,
          foregroundColor: MxColors.forest,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shadowColor: MxColors.glow.withValues(alpha: 0.5),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MxRadius.pill)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MxColors.forest,
          side: const BorderSide(color: MxColors.moss, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MxRadius.pill)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MxColors.mossDeep,
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MxColors.charcoal,
        contentTextStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 14,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static InputDecorationTheme _inputDecoration() {
    return InputDecorationTheme(
      filled: true,
      fillColor: MxColors.creamSoft,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      labelStyle: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        color: MxColors.stone,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        color: MxColors.stoneLight,
      ),
      prefixIconColor: MxColors.moss,
      suffixIconColor: MxColors.stoneLight,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MxRadius.md),
        borderSide: const BorderSide(color: MxColors.line, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MxRadius.md),
        borderSide: const BorderSide(color: MxColors.moss, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MxRadius.md),
        borderSide: const BorderSide(color: MxColors.danger, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MxRadius.md),
        borderSide: const BorderSide(color: MxColors.danger, width: 1.6),
      ),
      errorStyle: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 12,
        color: MxColors.danger,
      ),
      floatingLabelBehavior: FloatingLabelBehavior.always,
    );
  }
}
