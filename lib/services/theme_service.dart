import 'package:flutter/material.dart';

/// Simple notifier that holds the current theme brightness.
/// Provided at the app root so both MaterialApp and SettingsPage can access it.
class ThemeService extends ChangeNotifier {
  bool _isDark = false;

  bool get isDark => _isDark;

  void toggle() {
    _isDark = !_isDark;
    notifyListeners();
  }

  void setDark(bool value) {
    if (_isDark == value) return;
    _isDark = value;
    notifyListeners();
  }
}
