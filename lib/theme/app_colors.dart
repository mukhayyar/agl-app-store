import 'package:flutter/material.dart';

/// Centralized color tokens for the AGL App Store design system.
///
/// Naming follows a semantic convention:
///   * `surface*`     – background layers (page → card → elevated)
///   * `text*`        – foreground text scales (primary → tertiary)
///   * `border*`      – hairline & divider colors
///   * `brand*`       – brand / primary action accents
///   * `accent*`      – secondary supporting accents
///   * `state*`       – success / warning / danger semantics
class AppColors {
  AppColors._();

  // Brand
  static const Color brand = Color(0xFF4F46E5); // indigo-600
  static const Color brandDark = Color(0xFF3730A3); // indigo-800
  static const Color brandSoft = Color(0xFFEEF2FF); // indigo-50
  static const Color brandOn = Color(0xFFFFFFFF);

  // Accents (used in featured gradients & category chips)
  static const Color accentPink = Color(0xFFEC4899);
  static const Color accentOrange = Color(0xFFF97316);
  static const Color accentTeal = Color(0xFF14B8A6);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentSky = Color(0xFF0EA5E9);
  static const Color accentViolet = Color(0xFF8B5CF6);

  // Surface
  static const Color background = Color(0xFFF8FAFC); // slate-50
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1F5F9); // slate-100
  static const Color surfaceSubtle = Color(0xFFF8FAFC);

  // Text
  static const Color textPrimary = Color(0xFF0F172A); // slate-900
  static const Color textSecondary = Color(0xFF475569); // slate-600
  static const Color textTertiary = Color(0xFF94A3B8); // slate-400
  static const Color textOnBrand = Color(0xFFFFFFFF);

  // Borders & dividers
  static const Color borderSubtle = Color(0xFFE2E8F0); // slate-200
  static const Color borderStrong = Color(0xFFCBD5E1); // slate-300

  // States
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  // Featured gradient palettes for cards (paired top→bottom)
  static const List<List<Color>> featuredGradients = [
    [Color(0xFF6366F1), Color(0xFF8B5CF6)], // indigo → violet
    [Color(0xFFEC4899), Color(0xFFF97316)], // pink → orange
    [Color(0xFF0EA5E9), Color(0xFF14B8A6)], // sky → teal
    [Color(0xFF22C55E), Color(0xFF14B8A6)], // green → teal
    [Color(0xFFF59E0B), Color(0xFFEF4444)], // amber → red
    [Color(0xFF8B5CF6), Color(0xFFEC4899)], // violet → pink
  ];

  /// Pick a stable gradient for a given seed (e.g. package id).
  static List<Color> gradientFor(String seed) {
    if (seed.isEmpty) return featuredGradients.first;
    final hash = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    return featuredGradients[hash % featuredGradients.length];
  }
}
