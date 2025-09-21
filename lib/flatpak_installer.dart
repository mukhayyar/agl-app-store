import 'package:flutter/services.dart';

class FlatpakInstaller {
  static const MethodChannel _channel =
      MethodChannel('com.example.flathub/installer');

  static Future<void> installApp(String appId) async {
    try {
      await _channel.invokeMethod('installFlatpak', {'appId': appId});
    } on PlatformException catch (e) {
      throw Exception('Failed to install app: ${e.message}');
    }
  }
}
