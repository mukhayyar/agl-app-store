import 'package:flutter/material.dart';

/// Light automotive color tokens.
class AppColors {
  AppColors._();

  // Brand
  static const Color brand = Color(0xFF6C5CE7);
  static const Color brandLight = Color(0xFFA29BFE);
  static const Color brandSoft = Color(0xFFEDE9FF);

  // Accents
  static const Color accentCyan = Color(0xFF00B4D8);
  static const Color accentPink = Color(0xFFFF6B9D);
  static const Color accentOrange = Color(0xFFFF9F43);
  static const Color accentGreen = Color(0xFF00C853);
  static const Color accentViolet = Color(0xFFA29BFE);

  // Light surfaces (used by light theme and as fallback)
  static const Color background = Color(0xFFF7F8FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFF0F2F8);
  static const Color surfaceBright = Color(0xFFE8EAF0);

  // Dark surfaces (used by dark theme)
  static const Color backgroundDark = Color(0xFF0A0E1A);
  static const Color surfaceDark = Color(0xFF131829);
  static const Color surfaceElevatedDark = Color(0xFF1A2035);

  // Text
  static const Color textPrimary = Color(0xFF1A1B2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textOnAccent = Color(0xFFFFFFFF);

  // Borders
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderBright = Color(0xFFD1D5DB);
  static const Color borderDark = Color(0xFF1E2540);

  // States
  static const Color success = Color(0xFF00C853);
  static const Color warning = Color(0xFFFF9F43);
  static const Color danger = Color(0xFFEF4444);

  // Glass
  static const Color glass = Color(0x0D000000);
  static const Color glassBorder = Color(0x1A000000);

  // Gradients
  static const List<List<Color>> gradients = [
    [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
    [Color(0xFFFF6B9D), Color(0xFFFF9F43)],
    [Color(0xFF00B4D8), Color(0xFF00C853)],
    [Color(0xFFFF9F43), Color(0xFFFF6B9D)],
    [Color(0xFF00C853), Color(0xFF00B4D8)],
    [Color(0xFFA29BFE), Color(0xFF6C5CE7)],
  ];

  static List<Color> gradientFor(String seed) {
    if (seed.isEmpty) return gradients.first;
    final hash = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    return gradients[hash % gradients.length];
  }
}

/// Convenience extension to resolve theme-adaptive colors from any widget.
/// Usage: `context.colors.bg`, `context.colors.card`, etc.
extension AppColorsX on BuildContext {
  _Adaptive get colors {
    final dark = Theme.of(this).brightness == Brightness.dark;
    return _Adaptive(dark);
  }
}

class _Adaptive {
  final bool _dark;
  const _Adaptive(this._dark);

  Color get bg => _dark ? AppColors.backgroundDark : AppColors.background;
  Color get card => _dark ? AppColors.surfaceDark : AppColors.surface;
  Color get cardEl => _dark ? AppColors.surfaceElevatedDark : AppColors.surfaceElevated;
  Color get border => _dark ? AppColors.borderDark : AppColors.border;
  Color get textP => _dark ? const Color(0xFFF1F3F8) : AppColors.textPrimary;
  Color get textS => _dark ? const Color(0xFF8B93A8) : AppColors.textSecondary;
  Color get textT => _dark ? const Color(0xFF4A5168) : AppColors.textTertiary;
}
