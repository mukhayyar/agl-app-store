import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  // Font sizes are sized for 7-inch 1080x1920 vertical automotive displays.
  // Base sizes are ~40% larger than standard desktop Material 3 sizes to
  // ensure readability at arm's length on in-vehicle head units.

  static TextTheme build(TextTheme base) {
    return GoogleFonts.plusJakartaSansTextTheme(base).copyWith(
      displayLarge: _s(56, FontWeight.w800, AppColors.textPrimary, -0.8, 1.1),
      displayMedium: _s(46, FontWeight.w800, AppColors.textPrimary, -0.6, 1.15),
      displaySmall: _s(36, FontWeight.w700, AppColors.textPrimary, -0.4, 1.2),
      headlineMedium: _s(30, FontWeight.w700, AppColors.textPrimary, -0.2),
      headlineSmall: _s(28, FontWeight.w700, AppColors.textPrimary),
      titleLarge: _s(24, FontWeight.w700, AppColors.textPrimary),
      titleMedium: _s(22, FontWeight.w600, AppColors.textPrimary),
      titleSmall: _s(19, FontWeight.w600, AppColors.textPrimary),
      bodyLarge: _s(22, FontWeight.w400, AppColors.textPrimary, 0, 1.55),
      bodyMedium: _s(19, FontWeight.w400, AppColors.textSecondary, 0, 1.55),
      bodySmall: _s(17, FontWeight.w400, AppColors.textTertiary, 0, 1.5),
      labelLarge: _s(21, FontWeight.w600, AppColors.textPrimary, 0.1),
      labelMedium: _s(18, FontWeight.w600, AppColors.textSecondary, 0.1),
      labelSmall: _s(15, FontWeight.w600, AppColors.textTertiary, 0.4),
    );
  }

  /// Dark-theme variant with light text colors.
  static TextTheme buildDark(TextTheme base) {
    const p = Color(0xFFF1F3F8);
    const s = Color(0xFF8B93A8);
    const t = Color(0xFF4A5168);
    return GoogleFonts.plusJakartaSansTextTheme(base).copyWith(
      displayLarge: _s(56, FontWeight.w800, p, -0.8, 1.1),
      displayMedium: _s(46, FontWeight.w800, p, -0.6, 1.15),
      displaySmall: _s(36, FontWeight.w700, p, -0.4, 1.2),
      headlineMedium: _s(30, FontWeight.w700, p, -0.2),
      headlineSmall: _s(28, FontWeight.w700, p),
      titleLarge: _s(24, FontWeight.w700, p),
      titleMedium: _s(22, FontWeight.w600, p),
      titleSmall: _s(19, FontWeight.w600, p),
      bodyLarge: _s(22, FontWeight.w400, p, 0, 1.55),
      bodyMedium: _s(19, FontWeight.w400, s, 0, 1.55),
      bodySmall: _s(17, FontWeight.w400, t, 0, 1.5),
      labelLarge: _s(21, FontWeight.w600, p, 0.1),
      labelMedium: _s(18, FontWeight.w600, s, 0.1),
      labelSmall: _s(15, FontWeight.w600, t, 0.4),
    );
  }

  static TextStyle _s(double sz, FontWeight w, Color c,
      [double ls = 0, double h = 0]) {
    return GoogleFonts.plusJakartaSans(
      fontSize: sz, fontWeight: w, color: c,
      letterSpacing: ls, height: h > 0 ? h : null,
    );
  }
}
