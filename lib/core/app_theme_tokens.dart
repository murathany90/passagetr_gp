import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

@immutable
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({
    required this.appBackground,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.surfaceBorder,
    required this.surfaceShadow,
    required this.glassBackground,
    required this.glassBorder,
    required this.primaryText,
    required this.secondaryText,
    required this.accent,
    required this.accentSoft,
    required this.accentGradient,
    required this.hero,
    required this.heroGlow,
    required this.success,
    required this.warning,
    required this.badgeOrange,
    required this.accentBlue,
    required this.purple,
    required this.pink,
    required this.green,
    required this.railBackground,
    required this.mobileNavBackground,
    required this.cardRadius,
    required this.pillRadius,
    required this.contentMaxWidth,
    required this.railWidth,
  });

  final Color appBackground;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color surfaceBorder;
  final Color surfaceShadow;
  final Color glassBackground;
  final Color glassBorder;
  final Color primaryText;
  final Color secondaryText;
  final Color accent;
  final Color accentSoft;
  final Gradient accentGradient;
  final Color hero;
  final Color heroGlow;
  final Color success;
  final Color warning;
  final Color badgeOrange;
  final Color accentBlue;
  final Color purple;
  final Color pink;
  final Color green;
  final Color railBackground;
  final Color mobileNavBackground;
  final double cardRadius;
  final double pillRadius;
  final double contentMaxWidth;
  final double railWidth;

  static AppThemeTokens of(BuildContext context) {
    return Theme.of(context).extension<AppThemeTokens>()!;
  }

  @override
  AppThemeTokens copyWith({
    Color? appBackground,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceMuted,
    Color? surfaceBorder,
    Color? surfaceShadow,
    Color? glassBackground,
    Color? glassBorder,
    Color? primaryText,
    Color? secondaryText,
    Color? accent,
    Color? accentSoft,
    Gradient? accentGradient,
    Color? hero,
    Color? heroGlow,
    Color? success,
    Color? warning,
    Color? badgeOrange,
    Color? accentBlue,
    Color? purple,
    Color? pink,
    Color? green,
    Color? railBackground,
    Color? mobileNavBackground,
    double? cardRadius,
    double? pillRadius,
    double? contentMaxWidth,
    double? railWidth,
  }) {
    return AppThemeTokens(
      appBackground: appBackground ?? this.appBackground,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceBorder: surfaceBorder ?? this.surfaceBorder,
      surfaceShadow: surfaceShadow ?? this.surfaceShadow,
      glassBackground: glassBackground ?? this.glassBackground,
      glassBorder: glassBorder ?? this.glassBorder,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentGradient: accentGradient ?? this.accentGradient,
      hero: hero ?? this.hero,
      heroGlow: heroGlow ?? this.heroGlow,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      badgeOrange: badgeOrange ?? this.badgeOrange,
      accentBlue: accentBlue ?? this.accentBlue,
      purple: purple ?? this.purple,
      pink: pink ?? this.pink,
      green: green ?? this.green,
      railBackground: railBackground ?? this.railBackground,
      mobileNavBackground: mobileNavBackground ?? this.mobileNavBackground,
      cardRadius: cardRadius ?? this.cardRadius,
      pillRadius: pillRadius ?? this.pillRadius,
      contentMaxWidth: contentMaxWidth ?? this.contentMaxWidth,
      railWidth: railWidth ?? this.railWidth,
    );
  }

  @override
  AppThemeTokens lerp(ThemeExtension<AppThemeTokens>? other, double t) {
    if (other is! AppThemeTokens) {
      return this;
    }

    return AppThemeTokens(
      appBackground: Color.lerp(appBackground, other.appBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceBorder: Color.lerp(surfaceBorder, other.surfaceBorder, t)!,
      surfaceShadow: Color.lerp(surfaceShadow, other.surfaceShadow, t)!,
      glassBackground: Color.lerp(glassBackground, other.glassBackground, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentGradient: Gradient.lerp(accentGradient, other.accentGradient, t)!,
      hero: Color.lerp(hero, other.hero, t)!,
      heroGlow: Color.lerp(heroGlow, other.heroGlow, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      badgeOrange: Color.lerp(badgeOrange, other.badgeOrange, t)!,
      accentBlue: Color.lerp(accentBlue, other.accentBlue, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      pink: Color.lerp(pink, other.pink, t)!,
      green: Color.lerp(green, other.green, t)!,
      railBackground: Color.lerp(railBackground, other.railBackground, t)!,
      mobileNavBackground: Color.lerp(
        mobileNavBackground,
        other.mobileNavBackground,
        t,
      )!,
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t)!,
      pillRadius: lerpDouble(pillRadius, other.pillRadius, t)!,
      contentMaxWidth: lerpDouble(contentMaxWidth, other.contentMaxWidth, t)!,
      railWidth: lerpDouble(railWidth, other.railWidth, t)!,
    );
  }
}
