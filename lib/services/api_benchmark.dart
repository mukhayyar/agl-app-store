import 'dart:async';
import 'package:http/http.dart' as http;

class BenchmarkResult {
  final double rps;
  final double minMs;
  final double avgMs;
  final double maxMs;
  final int successCount;
  final int totalCount;

  const BenchmarkResult({
    required this.rps,
    required this.minMs,
    required this.avgMs,
    required this.maxMs,
    required this.successCount,
    required this.totalCount,
  });
}

class ApiBenchmark {
  final String baseUrl;

  ApiBenchmark({this.baseUrl = 'http://localhost:8002'});

  Future<double?> measureLatency() async {
    try {
      final stopwatch = Stopwatch()..start();
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      stopwatch.stop();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return stopwatch.elapsedMicroseconds / 1000.0;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<double?> measureThroughput() async {
    try {
      final stopwatch = Stopwatch()..start();
      final response = await http
          .get(Uri.parse('$baseUrl/apps?limit=50'))
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bytes = response.bodyBytes.length;
        final seconds = stopwatch.elapsedMicroseconds / 1e6;
        if (seconds > 0) {
          return (bytes / seconds) / (1024 * 1024); // MB/s
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<BenchmarkResult> runBenchmark({int count = 50}) async {
    final stopwatch = Stopwatch()..start();
    final futures = List.generate(
      count,
      (_) => _timedGet('$baseUrl/apps'),
    );
    final results = await Future.wait(futures);
    stopwatch.stop();

    final successful = results.whereType<double>().toList();
    final totalSeconds = stopwatch.elapsedMicroseconds / 1e6;

    if (successful.isEmpty) {
      return BenchmarkResult(
        rps: 0,
        minMs: 0,
        avgMs: 0,
        maxMs: 0,
        successCount: 0,
        totalCount: count,
      );
    }

    successful.sort();
    final minMs = successful.first;
    final maxMs = successful.last;
    final avgMs = successful.reduce((a, b) => a + b) / successful.length;
    final rps = totalSeconds > 0 ? successful.length / totalSeconds : 0.0;

    return BenchmarkResult(
      rps: rps,
      minMs: minMs,
      avgMs: avgMs,
      maxMs: maxMs,
      successCount: successful.length,
      totalCount: count,
    );
  }

  Future<double?> _timedGet(String url) async {
    try {
      final stopwatch = Stopwatch()..start();
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return stopwatch.elapsedMicroseconds / 1000.0;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
