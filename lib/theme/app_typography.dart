import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  static TextTheme build(TextTheme base) {
    return GoogleFonts.plusJakartaSansTextTheme(base).copyWith(
      displayLarge: _s(40, FontWeight.w800, AppColors.textPrimary, -0.8, 1.1),
      displayMedium: _s(32, FontWeight.w800, AppColors.textPrimary, -0.6, 1.15),
      displaySmall: _s(26, FontWeight.w700, AppColors.textPrimary, -0.4, 1.2),
      headlineMedium: _s(22, FontWeight.w700, AppColors.textPrimary, -0.2),
      headlineSmall: _s(20, FontWeight.w700, AppColors.textPrimary),
      titleLarge: _s(18, FontWeight.w700, AppColors.textPrimary),
      titleMedium: _s(16, FontWeight.w600, AppColors.textPrimary),
      titleSmall: _s(14, FontWeight.w600, AppColors.textPrimary),
      bodyLarge: _s(16, FontWeight.w400, AppColors.textPrimary, 0, 1.55),
      bodyMedium: _s(14, FontWeight.w400, AppColors.textSecondary, 0, 1.55),
      bodySmall: _s(12, FontWeight.w400, AppColors.textTertiary, 0, 1.5),
      labelLarge: _s(15, FontWeight.w600, AppColors.textPrimary, 0.1),
      labelMedium: _s(13, FontWeight.w600, AppColors.textSecondary, 0.1),
      labelSmall: _s(11, FontWeight.w600, AppColors.textTertiary, 0.4),
    );
  }

  /// Dark-theme variant with light text colors.
  static TextTheme buildDark(TextTheme base) {
    const p = Color(0xFFF1F3F8);
    const s = Color(0xFF8B93A8);
    const t = Color(0xFF4A5168);
    return GoogleFonts.plusJakartaSansTextTheme(base).copyWith(
      displayLarge: _s(40, FontWeight.w800, p, -0.8, 1.1),
      displayMedium: _s(32, FontWeight.w800, p, -0.6, 1.15),
      displaySmall: _s(26, FontWeight.w700, p, -0.4, 1.2),
      headlineMedium: _s(22, FontWeight.w700, p, -0.2),
      headlineSmall: _s(20, FontWeight.w700, p),
      titleLarge: _s(18, FontWeight.w700, p),
      titleMedium: _s(16, FontWeight.w600, p),
      titleSmall: _s(14, FontWeight.w600, p),
      bodyLarge: _s(16, FontWeight.w400, p, 0, 1.55),
      bodyMedium: _s(14, FontWeight.w400, s, 0, 1.55),
      bodySmall: _s(12, FontWeight.w400, t, 0, 1.5),
      labelLarge: _s(15, FontWeight.w600, p, 0.1),
      labelMedium: _s(13, FontWeight.w600, s, 0.1),
      labelSmall: _s(11, FontWeight.w600, t, 0.4),
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
