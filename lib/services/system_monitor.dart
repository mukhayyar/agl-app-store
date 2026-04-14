import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class SystemMonitor extends ChangeNotifier {
  // Current values
  double cpu = 0;
  double ramUsedMb = 0;
  double ramTotalMb = 0;
  double diskUsedGb = 0;
  double diskTotalGb = 0;
  double rxBytesPerSec = 0;
  double txBytesPerSec = 0;

  // History (60 samples) — new list created on every tick so Flutter
  // widget reconciliation sees a different object and triggers rebuild.
  List<double> cpuHistory = List.filled(60, 0);
  List<double> ramHistory = List.filled(60, 0);
  List<double> rxHistory = List.filled(60, 0);
  List<double> txHistory = List.filled(60, 0);

  Timer? _timer;

  // Previous CPU stat values
  int _prevIdle = 0;
  int _prevTotal = 0;

  // Previous network byte counts
  int _prevRxBytes = 0;
  int _prevTxBytes = 0;
  bool _firstNetRead = true;

  void start() {
    _timer?.cancel();
    _readCpuBaseline();
    _readNetBaseline();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _readCpuBaseline() async {
    try {
      final content = await File('/proc/stat').readAsString();
      final line = content.split('\n').firstWhere((l) => l.startsWith('cpu '));
      final parts = line.trim().split(RegExp(r'\s+'));
      final values = parts.skip(1).map(int.parse).toList();
      if (values.length >= 8) {
        _prevIdle = values[3] + values[4];
        _prevTotal = values.fold(0, (a, b) => a + b);
      }
    } catch (_) {}
  }

  Future<void> _readNetBaseline() async {
    try {
      final result = await _sumNetBytes();
      _prevRxBytes = result[0];
      _prevTxBytes = result[1];
      _firstNetRead = false;
    } catch (_) {}
  }

  Future<void> _tick() async {
    // Use individual try/catch so one failing reading doesn't skip notify.
    // Also wait for all, even those that throw, so history lists stay in
    // sync (each tick must append exactly one sample to each history).
    await Future.wait([
      _readCpu().catchError((_) {}),
      _readRam().catchError((_) {}),
      _readDisk().catchError((_) {}),
      _readNetwork().catchError((_) {}),
    ]);
    notifyListeners();
  }

  Future<void> _readCpu() async {
    try {
      final content = await File('/proc/stat').readAsString();
      final line = content.split('\n').firstWhere((l) => l.startsWith('cpu '));
      final parts = line.trim().split(RegExp(r'\s+'));
      final values = parts.skip(1).map(int.parse).toList();
      if (values.length >= 8) {
        final idle = values[3] + values[4];
        final total = values.fold(0, (a, b) => a + b);
        final idleDelta = idle - _prevIdle;
        final totalDelta = total - _prevTotal;
        if (totalDelta > 0) {
          cpu = ((1.0 - idleDelta / totalDelta) * 100).clamp(0.0, 100.0);
        }
        _prevIdle = idle;
        _prevTotal = total;
      }
    } catch (_) {
      cpu = 0;
    }
    cpuHistory = _pushHistory(cpuHistory, cpu);
  }

  Future<void> _readRam() async {
    try {
      final content = await File('/proc/meminfo').readAsString();
      final lines = content.split('\n');
      int memTotal = 0;
      int memAvailable = 0;
      for (final line in lines) {
        if (line.startsWith('MemTotal:')) {
          memTotal = _parseMeminfoKb(line);
        } else if (line.startsWith('MemAvailable:')) {
          memAvailable = _parseMeminfoKb(line);
        }
      }
      if (memTotal > 0) {
        ramTotalMb = memTotal / 1024.0;
        ramUsedMb = (memTotal - memAvailable) / 1024.0;
      }
    } catch (_) {
      ramTotalMb = 0;
      ramUsedMb = 0;
    }
    final pct = ramTotalMb > 0 ? (ramUsedMb / ramTotalMb) * 100 : 0.0;
    ramHistory = _pushHistory(ramHistory, pct);
  }

  int _parseMeminfoKb(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return int.tryParse(parts[1]) ?? 0;
    }
    return 0;
  }

  Future<void> _readDisk() async {
    try {
      final result = await Process.run('df', ['-BG', '/']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        if (lines.length >= 2) {
          final parts = lines[1].trim().split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            diskTotalGb = double.tryParse(parts[1].replaceAll('G', '')) ?? 0;
            diskUsedGb = double.tryParse(parts[2].replaceAll('G', '')) ?? 0;
          }
        }
      }
    } catch (_) {
      diskTotalGb = 0;
      diskUsedGb = 0;
    }
  }

  Future<void> _readNetwork() async {
    try {
      final bytes = await _sumNetBytes();
      final rxBytes = bytes[0];
      final txBytes = bytes[1];

      if (!_firstNetRead) {
        rxBytesPerSec = (rxBytes - _prevRxBytes).toDouble().clamp(0, double.infinity);
        txBytesPerSec = (txBytes - _prevTxBytes).toDouble().clamp(0, double.infinity);
      }
      _prevRxBytes = rxBytes;
      _prevTxBytes = txBytes;
      _firstNetRead = false;
    } catch (_) {
      rxBytesPerSec = 0;
      txBytesPerSec = 0;
    }
    rxHistory = _pushHistory(rxHistory, rxBytesPerSec);
    txHistory = _pushHistory(txHistory, txBytesPerSec);
  }

  Future<List<int>> _sumNetBytes() async {
    final content = await File('/proc/net/dev').readAsString();
    final lines = content.split('\n').skip(2); // skip header lines
    int totalRx = 0;
    int totalTx = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final colonIdx = trimmed.indexOf(':');
      if (colonIdx < 0) continue;
      final iface = trimmed.substring(0, colonIdx).trim();
      // Skip loopback
      if (iface == 'lo') continue;
      final parts = trimmed.substring(colonIdx + 1).trim().split(RegExp(r'\s+'));
      if (parts.length >= 9) {
        totalRx += int.tryParse(parts[0]) ?? 0;
        totalTx += int.tryParse(parts[8]) ?? 0;
      }
    }
    return [totalRx, totalTx];
  }

  /// Returns a new list with the oldest sample dropped and [value] appended.
  /// Creating a new list (not mutating in-place) is required so that Flutter's
  /// widget reconciliation detects the change and rebuilds the chart widget.
  List<double> _pushHistory(List<double> history, double value) {
    return [...history.skip(1), value];
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
