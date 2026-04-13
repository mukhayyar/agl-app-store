/// Spacing & radius tokens tuned for automotive touch targets.
///
/// Minimum touch target is 48dp per Material guidelines; we default
/// to 56dp for in-car use (gloved / imprecise taps).
class AppSpacing {
  AppSpacing._();

  // Spacing (4pt grid)
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  // Page gutter
  static const double pageH = 20;

  // Border radius
  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 16;
  static const double rXl = 20;
  static const double rXxl = 28;
  static const double rFull = 999;

  // Touch targets
  static const double touchMin = 48;
  static const double touchLg = 56;
}
