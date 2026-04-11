import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum ExpiryLevel { critical, warning, notice }

class ExpiryInfo {
  final String label;
  final ExpiryLevel level;
  const ExpiryInfo(this.label, this.level);
}

ExpiryInfo? getExpiryInfo(DateTime? expiresAt) {
  if (expiresAt == null) return null;
  final now = DateTime.now();
  final diff = expiresAt.difference(now);
  final days = diff.inDays;
  if (diff.isNegative) return const ExpiryInfo('Expired', ExpiryLevel.critical);
  if (days < 1) return const ExpiryInfo('Expires today', ExpiryLevel.critical);
  if (days <= 7) return ExpiryInfo('$days days left', ExpiryLevel.warning);
  if (days <= 30) return ExpiryInfo('$days days left', ExpiryLevel.notice);
  return null;
}

class AppItem {
  final String id;
  final String name;
  final String description;
  final String version;
  final String? category;
  final String? iconUrl;
  final String? developer;
  final String? license;
  final bool isVerified;
  final DateTime? expiresAt;

  const AppItem({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    this.category,
    this.iconUrl,
    this.developer,
    this.license,
    this.isVerified = false,
    this.expiresAt,
  });

  factory AppItem.fromJson(Map<String, dynamic> json) {
    final rawDesc = (json['description'] ?? '').toString();
    final summary = (json['summary'] ?? '').toString();
    final description = rawDesc.isNotEmpty ? rawDesc : summary;

    DateTime? expiresAt;
    if (json['expires_at'] != null) {
      try {
        expiresAt = DateTime.parse(json['expires_at'].toString());
      } catch (_) {}
    }

    return AppItem(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? 'Unknown').toString(),
      description: description,
      version: (json['version'] ?? '0.0.1').toString(),
      category: ((json['categories'] as List?)?.firstOrNull?.toString()) ?? json['category']?.toString(),
      iconUrl: json['icon']?.toString() ?? json['icon_url']?.toString() ?? json['iconUrl']?.toString(),
      developer: json['developer_name']?.toString(),
      license: json['project_license']?.toString(),
      isVerified: json['is_verified'] == true,
      expiresAt: expiresAt,
    );
  }
}

class PingResult {
  final bool success;
  final int latencyMs;
  final String error;

  const PingResult({required this.success, required this.latencyMs, this.error = ''});
}

class BenchmarkResult {
  final int totalRequests;
  final int successCount;
  final double rps;
  final double avgLatencyMs;
  final int minLatencyMs;
  final int maxLatencyMs;

  const BenchmarkResult({
    required this.totalRequests,
    required this.successCount,
    required this.rps,
    required this.avgLatencyMs,
    required this.minLatencyMs,
    required this.maxLatencyMs,
  });
}

class ApiService extends ChangeNotifier {
  String _baseUrl;
  final http.Client _client = http.Client();

  // Ping monitoring
  double pingLatencyMs = -1.0;
  final List<double> pingHistory = List.filled(30, 0.0);
  double pingMin = double.infinity;
  double pingMax = 0.0;
  double pingAvg = 0.0;
  final List<double> _pingSamples = [];

  Timer? _pingTimer;

  ApiService({required String baseUrl}) : _baseUrl = baseUrl {
    _startPingMonitor();
  }

  String get baseUrl => _baseUrl;

  void updateBaseUrl(String url) {
    _baseUrl = url;
    _restartPingMonitor();
    notifyListeners();
  }

  void _startPingMonitor() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) => _doPing());
    _doPing();
  }

  void _restartPingMonitor() {
    _pingTimer?.cancel();
    _startPingMonitor();
  }

  Future<void> _doPing() async {
    final result = await ping();
    if (result.success) {
      pingLatencyMs = result.latencyMs.toDouble();
      _pingSamples.add(pingLatencyMs);
      if (_pingSamples.length > 30) _pingSamples.removeAt(0);

      pingMin = _pingSamples.reduce((a, b) => a < b ? a : b);
      pingMax = _pingSamples.reduce((a, b) => a > b ? a : b);
      pingAvg = _pingSamples.reduce((a, b) => a + b) / _pingSamples.length;

      _shiftHistory(pingHistory, pingLatencyMs);
    } else {
      pingLatencyMs = -1;
      _shiftHistory(pingHistory, 0);
    }
    notifyListeners();
  }

  Future<PingResult> ping() async {
    final url = Uri.parse('$_baseUrl/health');
    final sw = Stopwatch()..start();
    try {
      final response = await _client.get(url).timeout(const Duration(seconds: 5));
      sw.stop();
      return PingResult(success: response.statusCode < 500, latencyMs: sw.elapsedMilliseconds);
    } catch (_) {
      // Try /apps as fallback
      try {
        sw.reset();
        sw.start();
        final resp2 = await _client
            .get(Uri.parse('$_baseUrl/apps?limit=1'))
            .timeout(const Duration(seconds: 5));
        sw.stop();
        return PingResult(success: resp2.statusCode < 500, latencyMs: sw.elapsedMilliseconds);
      } catch (e) {
        sw.stop();
        return PingResult(success: false, latencyMs: sw.elapsedMilliseconds, error: e.toString());
      }
    }
  }

  Future<List<AppItem>> fetchApps({int limit = 20, int offset = 0}) async {
    try {
      final uri = Uri.parse('$_baseUrl/apps').replace(
        queryParameters: {'limit': '$limit', 'offset': '$offset'},
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];
      final decoded = jsonDecode(response.body);
      List<dynamic> items;
      if (decoded is List) {
        items = decoded;
      } else if (decoded is Map && decoded.containsKey('apps')) {
        items = decoded['apps'] as List;
      } else if (decoded is Map && decoded.containsKey('data')) {
        items = decoded['data'] as List;
      } else {
        return [];
      }
      return items.map((e) => AppItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<double> measureThroughput() async {
    final uri = Uri.parse('$_baseUrl/apps?limit=50');
    final sw = Stopwatch()..start();
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));
      sw.stop();
      final bytes = response.bodyBytes.length;
      final seconds = sw.elapsedMilliseconds / 1000.0;
      return seconds > 0 ? bytes / seconds / 1024 / 1024 : 0.0; // MB/s
    } catch (_) {
      return 0.0;
    }
  }

  Future<BenchmarkResult> runBenchmark({int count = 50}) async {
    final uri = Uri.parse('$_baseUrl/apps?limit=1');
    final sw = Stopwatch()..start();
    final latencies = <int>[];
    int success = 0;

    final futures = List.generate(count, (_) async {
      final t = Stopwatch()..start();
      try {
        final resp = await _client.get(uri).timeout(const Duration(seconds: 10));
        t.stop();
        if (resp.statusCode < 500) {
          success++;
          latencies.add(t.elapsedMilliseconds);
        }
      } catch (_) {
        t.stop();
      }
    });

    await Future.wait(futures);
    sw.stop();

    final elapsed = sw.elapsedMilliseconds / 1000.0;
    final rps = elapsed > 0 ? count / elapsed : 0.0;
    final avgLat = latencies.isNotEmpty
        ? latencies.reduce((a, b) => a + b) / latencies.length
        : 0.0;
    final minLat = latencies.isNotEmpty ? latencies.reduce((a, b) => a < b ? a : b) : 0;
    final maxLat = latencies.isNotEmpty ? latencies.reduce((a, b) => a > b ? a : b) : 0;

    return BenchmarkResult(
      totalRequests: count,
      successCount: success,
      rps: rps,
      avgLatencyMs: avgLat,
      minLatencyMs: minLat,
      maxLatencyMs: maxLat,
    );
  }

  void _shiftHistory(List<double> history, double value) {
    history.removeAt(0);
    history.add(value);
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _client.close();
    super.dispose();
  }
}
