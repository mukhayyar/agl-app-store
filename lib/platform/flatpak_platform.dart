import 'package:flutter/services.dart';

class FlatpakPlatform {
  static const _channel = MethodChannel('com.example.flathub/installer');
  static const _events  = EventChannel('com.example.flathub/installer_events');

  static Stream<dynamic> installEvents() => _events.receiveBroadcastStream();

  static Future<void> install(String appId) async {
    await _channel.invokeMethod('installFlatpak', {'appId': appId});
  }

  static Future<bool> isInstalled(String appId) async {
    final ok = await _channel.invokeMethod('isInstalled', {'appId': appId});
    return ok == true;
  }

  static Future<List<String>> listInstalled() async {
    final list = await _channel.invokeMethod<List<dynamic>>('listInstalled');
    return (list ?? []).cast<String>();
  }

  static Future<void> uninstall(String appId) async {
    await _channel.invokeMethod('uninstallFlatpak', {'appId': appId});
  }

  static Future<void> update(String appId) async {
    await _channel.invokeMethod('updateFlatpak', {'appId': appId});
  }
}
