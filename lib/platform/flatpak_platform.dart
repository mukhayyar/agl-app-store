import 'package:flutter/services.dart';

class FlatpakPlatform {
  static const _channel = MethodChannel('com.pens.flatpak/installer');
  static const _events = EventChannel('com.pens.flatpak/installer_events');

  static Stream<dynamic> installEvents() => _events.receiveBroadcastStream();

  /// Installs a flatpak app from the given [remote] (e.g. `flathub` or
  /// `repo.agl-store.cyou`). When [remote] is null the native plugin falls
  /// back to its compiled-in default (PensHub).
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

    // Safely convert to strongly typed Map
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
}
