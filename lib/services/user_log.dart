import 'package:flutter/foundation.dart';

/// Lightweight user-action logger. Goes to stdout so flutter-auto's
/// systemd journal captures it; tail on the device with:
///
///   journalctl -u agl-app-flutter@agl_app_store -f | grep USER-TAP
///
/// The goal is a one-line audit trail of everything the user touched in
/// the UI — install/launch/uninstall buttons, nav taps, source switches,
/// screenshot opens, island expansions — so that when a bug is reported
/// we can reconstruct exactly what was tapped and in what order.
///
/// Keep entries terse. Details go into the optional map as key=value
/// pairs so the output stays grep-friendly.
class UserLog {
  const UserLog._();

  static void tap(String action, [Map<String, Object?>? details]) {
    if (details == null || details.isEmpty) {
      debugPrint('[USER-TAP] $action');
      return;
    }
    final buf = StringBuffer('[USER-TAP] $action');
    details.forEach((k, v) {
      if (v == null) return;
      buf.write(' $k=$v');
    });
    debugPrint(buf.toString());
  }
}
