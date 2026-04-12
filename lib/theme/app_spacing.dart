/// Spacing & radius scale used across the design system.
///
/// Stick to these values rather than ad-hoc literals so layouts stay
/// consistent and easy to retune from a single place.
class AppSpacing {
  AppSpacing._();

  // Spacing scale (4pt grid)
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  // Page horizontal padding
  static const double pageGutter = 20;

  // Border radius
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusXxl = 28;
  static const double radiusFull = 999;
}
