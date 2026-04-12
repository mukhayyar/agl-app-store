import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

class GpsService extends ChangeNotifier {
  double speedKmh = 0;
  double? lat;
  double? lon;
  bool hasGps = false;

  Timer? _simTimer;
  StreamSubscription<List<int>>? _gpsSubscription;
  double _simT = 0;
  String _buffer = '';

  void start() {
    _tryGpsHardware();
  }

  void stop() {
    _simTimer?.cancel();
    _simTimer = null;
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
  }

  Future<void> _tryGpsHardware() async {
    final ports = ['/dev/ttyUSB0', '/dev/ttyS0', '/dev/ttyACM0'];
    for (final port in ports) {
      try {
        final file = File(port);
        if (await file.exists()) {
          final stream = file.openRead();
          _gpsSubscription = stream.listen(
            _onGpsData,
            onError: (_) {
              _gpsSubscription?.cancel();
              _startSimulation();
            },
            onDone: _startSimulation,
            cancelOnError: true,
          );
          hasGps = true;
          notifyListeners();
          return;
        }
      } catch (_) {
        // Try next port
      }
    }
    // No hardware GPS found — start simulation
    _startSimulation();
  }

  void _onGpsData(List<int> data) {
    _buffer += String.fromCharCodes(data);
    final lines = _buffer.split('\n');
    // Keep incomplete last line in buffer
    _buffer = lines.removeLast();
    for (final line in lines) {
      _parseNmea(line.trim());
    }
  }

  void _parseNmea(String sentence) {
    if (!sentence.startsWith('\$GPRMC')) return;
    // Validate checksum
    final asteriskIdx = sentence.lastIndexOf('*');
    if (asteriskIdx < 0) return;
    final parts = sentence.substring(1, asteriskIdx).split(',');
    // \$GPRMC,HHMMSS.ss,A,Lat,N,Lon,E,Speed(knots),Course,Date,...
    if (parts.length < 8) return;
    final status = parts[2]; // A = active, V = void
    if (status != 'A') {
      speedKmh = 0;
      notifyListeners();
      return;
    }
    try {
      final latRaw = double.tryParse(parts[3]);
      final latDir = parts[4];
      final lonRaw = double.tryParse(parts[5]);
      final lonDir = parts[6];
      final speedKnots = double.tryParse(parts[7]);

      if (latRaw != null && lonRaw != null) {
        lat = _nmeaToDecimal(latRaw, latDir);
        lon = _nmeaToDecimal(lonRaw, lonDir);
        hasGps = true;
      }
      if (speedKnots != null) {
        speedKmh = speedKnots * 1.852;
      }
      notifyListeners();
    } catch (_) {}
  }

  double _nmeaToDecimal(double raw, String dir) {
    final degrees = (raw / 100).floor().toDouble();
    final minutes = raw - (degrees * 100);
    double decimal = degrees + (minutes / 60.0);
    if (dir == 'S' || dir == 'W') decimal = -decimal;
    return decimal;
  }

  void _startSimulation() {
    hasGps = false;
    lat = null;
    lon = null;
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _simT += 0.05;
      speedKmh = 40.0 + 40.0 * sin(_simT * 0.1);
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
