import 'package:flutter/material.dart';

import 'app_theme_tokens.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final tokens = AppThemeTokens(
      appBackground: dark ? const Color(0xFF0F172A) : const Color(0xFFF4F6FA),
      surface: dark ? const Color(0xFF1E293B) : Colors.white,
      surfaceElevated: dark ? const Color(0xFF263146) : Colors.white,
      surfaceMuted: dark ? const Color(0xFF18202D) : const Color(0xFFF7F9FD),
      surfaceBorder: dark ? const Color(0xFF334155) : const Color(0xFFE3E8F1),
      surfaceShadow: dark ? const Color(0x99000000) : const Color(0x140F172A),
      glassBackground: dark ? const Color(0x991E293B) : const Color(0xCCFFFFFF),
      glassBorder: dark ? const Color(0x3364748B) : const Color(0x33E3E8F1),
      primaryText: dark ? const Color(0xFFF8FAFC) : const Color(0xFF18243D),
      secondaryText: dark ? const Color(0xFF94A3B8) : const Color(0xFF5A6D8B),
      accent: dark ? const Color(0xFF72A3FF) : const Color(0xFF1B2D63),
      accentSoft: dark ? const Color(0xFF24314B) : const Color(0xFFDCE4F4),
      accentGradient: LinearGradient(
          colors: dark
              ? const <Color>[Color(0xFF72A3FF), Color(0xFF3B82F6)]
              : const <Color>[Color(0xFF1B2D63), Color(0xFF2A4186)]),
      hero: dark ? const Color(0xFFFF7E33) : const Color(0xFFFF6A00),
      heroGlow: const Color(0xFFFF9248),
      success: dark ? const Color(0xFF22D3EE) : const Color(0xFF11C979),
      warning: dark ? const Color(0xFFFBBF24) : const Color(0xFFF8A200),
      badgeOrange: const Color(0xFFFF6A3D),
      accentBlue: dark ? const Color(0xFF72A3FF) : const Color(0xFF3B82F6),
      purple: dark ? const Color(0xFFA78BFA) : const Color(0xFF695CFF),
      pink: dark ? const Color(0xFFFB7185) : const Color(0xFFFF2A68),
      green: dark ? const Color(0xFF34D399) : const Color(0xFF14C77F),
      railBackground: dark ? const Color(0xFF0F172A) : const Color(0xFFF7F9FD),
      mobileNavBackground: dark ? const Color(0xFF0F172A) : Colors.white,
      cardRadius: 24,
      pillRadius: 22,
      contentMaxWidth: 1120,
      railWidth: 92,
    );
    final colorScheme =
        ColorScheme.fromSeed(seedColor: tokens.accent, brightness: brightness)
            .copyWith(
      primary: tokens.accent,
      secondary: tokens.hero,
      surface: tokens.surface,
      onSurface: tokens.primaryText,
      outlineVariant: tokens.surfaceBorder,
    );
    final textTheme = TextTheme(
      displaySmall: TextStyle(
          fontSize: 34,
          height: 1.1,
          fontWeight: FontWeight.w800,
          color: tokens.primaryText,
          letterSpacing: -1),
      headlineMedium: TextStyle(
          fontSize: 30,
          height: 1.14,
          fontWeight: FontWeight.w800,
          color: tokens.primaryText,
          letterSpacing: -1),
      headlineSmall: TextStyle(
          fontSize: 22,
          height: 1.2,
          fontWeight: FontWeight.w800,
          color: tokens.primaryText,
          letterSpacing: -.5),
      titleLarge: TextStyle(
          fontSize: 18,
          height: 1.2,
          fontWeight: FontWeight.w800,
          color: tokens.primaryText),
      titleMedium: TextStyle(
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: tokens.primaryText),
      bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.45,
          fontWeight: FontWeight.w500,
          color: tokens.primaryText),
      bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w500,
          color: tokens.secondaryText),
      bodySmall: TextStyle(
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: tokens.secondaryText),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.appBackground,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[tokens],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: tokens.surfaceBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: tokens.surfaceBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: tokens.accent, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        backgroundColor: tokens.accent,
        foregroundColor: dark ? const Color(0xFF0F172A) : Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.pillRadius)),
        textStyle: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        foregroundColor: tokens.primaryText,
        side: BorderSide(color: tokens.surfaceBorder),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.pillRadius)),
      )),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.mobileNavBackground,
        indicatorColor: tokens.accentSoft,
        labelTextStyle: WidgetStatePropertyAll(textTheme.bodySmall),
      ),
    );
  }
}
