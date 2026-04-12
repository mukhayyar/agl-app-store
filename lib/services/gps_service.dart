import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

class GpsData {
  final double speedKmh;
  final double? latitude;
  final double? longitude;
  final bool hasSignal;

  const GpsData({
    required this.speedKmh,
    this.latitude,
    this.longitude,
    required this.hasSignal,
  });

  static const GpsData noSignal = GpsData(speedKmh: 0, hasSignal: false);
}

class GpsService extends ChangeNotifier {
  GpsData _data = GpsData.noSignal;
  GpsData get data => _data;

  StreamSubscription<String>? _sub;
  Timer? _simTimer;
  bool _running = false;
  bool _usingReal = false;

  // Simulation state
  double _simSpeed = 0.0;
  double _simAccel = 1.2;
  final _rng = math.Random();

  static const _serialPaths = ['/dev/ttyUSB0', '/dev/ttyS0', '/dev/ttyACM0'];

  void start() {
    if (_running) return;
    _running = true;
    _tryOpenSerial();
  }

  void stop() {
    _sub?.cancel();
    _simTimer?.cancel();
    _sub = null;
    _simTimer = null;
    _running = false;
  }

  Future<void> _tryOpenSerial() async {
    for (final path in _serialPaths) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;

        final stream = file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        _sub = stream.listen(
          _onNmeaLine,
          onError: (_) => _fallbackToSim(),
          cancelOnError: true,
        );
        _usingReal = true;
        return;
      } catch (_) {
        continue;
      }
    }
    _fallbackToSim();
  }

  void _fallbackToSim() {
    _usingReal = false;
    _simTimer ??= Timer.periodic(const Duration(milliseconds: 500), (_) => _simulateTick());
  }

  void _simulateTick() {
    // Simulate a drive: accelerate, cruise, decelerate
    final noise = (_rng.nextDouble() - 0.5) * 0.8;
    _simAccel += (_rng.nextDouble() - 0.5) * 0.3;
    _simAccel = _simAccel.clamp(-3.0, 3.0);

    if (_simSpeed > 110) _simAccel = -2.0;
    if (_simSpeed < 5) _simAccel = 1.5;

    _simSpeed = (_simSpeed + _simAccel * 0.5 + noise).clamp(0.0, 120.0);

    _data = GpsData(
      speedKmh: _simSpeed,
      latitude: null,
      longitude: null,
      hasSignal: false,
    );
    notifyListeners();
  }

  void _onNmeaLine(String line) {
    line = line.trim();
    if (!line.startsWith('\$GPRMC') && !line.startsWith('\$GNRMC')) return;
    if (!_validateNmeaChecksum(line)) return;

    final parts = line.split(',');
    if (parts.length < 10) return;

    // Status: A=active, V=void
    final status = parts[2];
    if (status != 'A') {
      _data = GpsData.noSignal;
      notifyListeners();
      return;
    }

    // Speed in knots → km/h
    final speedKnots = double.tryParse(parts[7]);
    final speedKmh = speedKnots != null ? speedKnots * 1.852 : 0.0;

    // Latitude
    final latRaw = parts[3];
    final latDir = parts[4];
    final lat = _parseNmeaCoord(latRaw, latDir);

    // Longitude
    final lonRaw = parts[5];
    final lonDir = parts[6];
    final lon = _parseNmeaCoord(lonRaw, lonDir);

    _data = GpsData(
      speedKmh: speedKmh,
      latitude: lat,
      longitude: lon,
      hasSignal: true,
    );
    notifyListeners();
  }

  double? _parseNmeaCoord(String raw, String dir) {
    if (raw.isEmpty) return null;
    try {
      final dotIdx = raw.indexOf('.');
      if (dotIdx < 2) return null;
      final degLen = dotIdx - 2;
      final degrees = double.parse(raw.substring(0, degLen));
      final minutes = double.parse(raw.substring(degLen));
      double coord = degrees + minutes / 60.0;
      if (dir == 'S' || dir == 'W') coord = -coord;
      return coord;
    } catch (_) {
      return null;
    }
  }

  bool _validateNmeaChecksum(String sentence) {
    try {
      final starIdx = sentence.lastIndexOf('*');
      if (starIdx < 0 || starIdx >= sentence.length - 2) return true; // No checksum — accept
      final data = sentence.substring(1, starIdx);
      final checksumStr = sentence.substring(starIdx + 1, starIdx + 3);
      final expected = int.parse(checksumStr, radix: 16);
      int calc = 0;
      for (final ch in data.codeUnits) {
        calc ^= ch;
      }
      return calc == expected;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
