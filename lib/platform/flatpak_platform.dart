import 'package:flutter/services.dart';

class FlatpakPlatform {
  static const _channel = MethodChannel('com.pens.flatpak/installer');
  static const _events = EventChannel('com.pens.flatpak/installer_events');

  static Stream<dynamic> installEvents() => _events.receiveBroadcastStream();

  /// Ensures the PensHub remote is registered on the host system.
  /// Downloads the GPG key and runs `flatpak remote-add` if not already present.
  ///
  /// Returns a map:
  ///   - `added` (bool): true if the remote was newly added
  ///   - `alreadyExists` (bool): true if it was already configured
  ///   - `error` (String?): non-null if something failed
  static Future<Map<String, dynamic>> ensureRemote() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('ensureRemote');
    return Map<String, dynamic>.from(result ?? {});
  }

  /// Installs a flatpak app from the given [remote] (e.g. `flathub` or `penshub`).
  /// When [remote] is null the native plugin falls back to its default (penshub).
  static Future<void> install(String appId, {String? remote}) async {
    await _channel.invokeMethod('installFlatpak', {
      'appId': appId,
      if (remote != null) 'remote': remote,
    });
  }

  static Future<void> launch(String appId) async {
    await _channel.invokeMethod('launchFlatpak', {'appId': appId});
  }

  static Future<bool> isInstalled(String appId) async {
    final ok = await _channel.invokeMethod('isInstalled', {'appId': appId});
    return ok == true;
  }

  static Future<List<Map<String, String>>> listInstalled() async {
    final list = await _channel.invokeMethod<List<dynamic>>('listInstalled');

    return (list ?? []).map((e) {
      final m = Map<String, dynamic>.from(e);
      return {
        'id': m['id']?.toString() ?? '',
        'name': m['name']?.toString() ?? '',
      };
    }).toList();
  }

  static Future<void> uninstall(String appId) async {
    await _channel.invokeMethod('uninstallFlatpak', {'appId': appId});
  }

  static Future<void> update(String appId) async {
    await _channel.invokeMethod('updateFlatpak', {'appId': appId});
  }

  /// Refreshes the appstream cache for both penshub and flathub remotes
  /// in the background. Non-blocking — the native side spawns the processes
  /// and returns immediately. Call this on every app launch so the catalog
  /// stays fresh without the driver ever touching a terminal.
  static Future<void> refreshAppstream() async {
    await _channel.invokeMethod('refreshAppstream');
  }
}
