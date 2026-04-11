import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/system_monitor.dart';
import '../services/gps_service.dart';
import '../services/api_service.dart';
import '../widgets/gauge_widget.dart';
import '../widgets/speedometer_widget.dart';
import '../widgets/line_chart_widget.dart';

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  // Benchmark state
  bool _benchRunning = false;
  BenchmarkResult? _benchResult;
  double? _throughputMbps;
  Timer? _throughputTimer;

  @override
  void initState() {
    super.initState();
    // Measure throughput every 30s
    _measureThroughput();
    _throughputTimer = Timer.periodic(const Duration(seconds: 30), (_) => _measureThroughput());
  }

  @override
  void dispose() {
    _throughputTimer?.cancel();
    super.dispose();
  }

  Future<void> _measureThroughput() async {
    final api = context.read<ApiService>();
    final mb = await api.measureThroughput();
    if (mounted) setState(() => _throughputMbps = mb);
  }

  Future<void> _runBenchmark() async {
    if (_benchRunning) return;
    setState(() {
      _benchRunning = true;
      _benchResult = null;
    });
    final api = context.read<ApiService>();
    final result = await api.runBenchmark(count: 50);
    if (mounted) {
      setState(() {
        _benchRunning = false;
        _benchResult = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.monitor_heart_rounded, color: Color(0xFF00D4FF), size: 20),
            SizedBox(width: 8),
            Text('System Monitor'),
          ],
        ),
        actions: [
          Consumer<SystemMonitor>(
            builder: (_, mon, __) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Color(0xFF00FF88),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(label: 'A — SYSTEM USAGE'),
            const SizedBox(height: 12),
            const _SystemUsageSection(),
            const SizedBox(height: 24),
            _SectionLabel(label: 'B — NETWORK MONITOR'),
            const SizedBox(height: 12),
            _NetworkSection(
              throughputMbps: _throughputMbps,
            ),
            const SizedBox(height: 24),
            _SectionLabel(label: 'C — SPEED & GPS'),
            const SizedBox(height: 12),
            _SpeedSection(
              benchRunning: _benchRunning,
              benchResult: _benchResult,
              onRunBenchmark: _runBenchmark,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFF00D4FF),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF00D4FF),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

// ─── Section A: System Usage ──────────────────────────────────────────────────

class _SystemUsageSection extends StatelessWidget {
  const _SystemUsageSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<SystemMonitor>(
      builder: (_, mon, __) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Gauges row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    GaugeWidget(
                      value: mon.cpuPercent,
                      label: 'CPU',
                      subLabel: null,
                    ),
                    GaugeWidget(
                      value: mon.ramPercent,
                      label: 'RAM',
                      subLabel: '${mon.ramUsedMb}/${mon.ramTotalMb}M',
                    ),
                    GaugeWidget(
                      value: mon.diskPercent,
                      label: 'DISK',
                      subLabel: '${mon.diskUsedGb}/${mon.diskTotalGb}G',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // CPU history chart
                MetricLineChart(
                  data: List<double>.from(mon.cpuHistory),
                  label: 'CPU % (30s)',
                  color: _gaugeColor(mon.cpuPercent),
                  unit: '%',
                  maxY: 100,
                ),
                const SizedBox(height: 12),
                // RAM history chart
                MetricLineChart(
                  data: List<double>.from(mon.ramHistory),
                  label: 'RAM % (30s)',
                  color: _gaugeColor(mon.ramPercent),
                  unit: '%',
                  maxY: 100,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _gaugeColor(double v) {
    if (v < 60) return const Color(0xFF00FF88);
    if (v < 80) return const Color(0xFFFFCC00);
    return const Color(0xFFFF4444);
  }
}

// ─── Section B: Network Monitor ───────────────────────────────────────────────

class _NetworkSection extends StatelessWidget {
  final double? throughputMbps;

  const _NetworkSection({this.throughputMbps});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ApiService, SystemMonitor>(
      builder: (_, api, mon, __) {
        final pingOnline = api.pingLatencyMs >= 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Ping + throughput stats row
                Row(
                  children: [
                    Expanded(
                      child: _NetStatBox(
                        label: 'PING',
                        value: pingOnline
                            ? '${api.pingLatencyMs.toStringAsFixed(0)} ms'
                            : 'Timeout',
                        color: pingOnline
                            ? _pingColor(api.pingLatencyMs)
                            : const Color(0xFFFF4444),
                        sub: pingOnline
                            ? 'min:${api.pingMin == double.infinity ? "--" : api.pingMin.toStringAsFixed(0)} avg:${api.pingAvg.toStringAsFixed(0)} max:${api.pingMax.toStringAsFixed(0)}'
                            : 'No connection',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NetStatBox(
                        label: 'THROUGHPUT',
                        value: throughputMbps != null
                            ? '${throughputMbps!.toStringAsFixed(2)} MB/s'
                            : '--- MB/s',
                        color: const Color(0xFF00D4FF),
                        sub: 'HTTP download',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // RX/TX rates
                Row(
                  children: [
                    Expanded(
                      child: _NetStatBox(
                        label: 'RX',
                        value: _formatBytes(mon.netRxRate),
                        color: const Color(0xFF00FF88),
                        sub: 'Total: ${_formatBytesTotal(mon.netRxBytes)}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NetStatBox(
                        label: 'TX',
                        value: _formatBytes(mon.netTxRate),
                        color: const Color(0xFFFFAA00),
                        sub: 'Total: ${_formatBytesTotal(mon.netTxBytes)}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Ping chart
                MetricLineChart(
                  data: List<double>.from(api.pingHistory),
                  label: 'Ping latency ms (30s)',
                  color: pingOnline ? _pingColor(api.pingLatencyMs) : const Color(0xFF445566),
                  unit: 'ms',
                ),
                const SizedBox(height: 12),
                // RX chart
                MetricLineChart(
                  data: List<double>.from(mon.rxHistory),
                  label: 'RX KB/s (30s)',
                  color: const Color(0xFF00FF88),
                  unit: 'K',
                ),
                const SizedBox(height: 12),
                // TX chart
                MetricLineChart(
                  data: List<double>.from(mon.txHistory),
                  label: 'TX KB/s (30s)',
                  color: const Color(0xFFFFAA00),
                  unit: 'K',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _pingColor(double ms) {
    if (ms < 50) return const Color(0xFF00FF88);
    if (ms < 150) return const Color(0xFFFFCC00);
    return const Color(0xFFFF4444);
  }

  String _formatBytes(double bytesPerSec) {
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / 1024 / 1024).toStringAsFixed(2)} MB/s';
    } else if (bytesPerSec >= 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${bytesPerSec.toStringAsFixed(0)} B/s';
  }

  String _formatBytesTotal(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

class _NetStatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String sub;

  const _NetStatBox({
    required this.label,
    required this.value,
    required this.color,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1A1A2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF556677),
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(color: Color(0xFF445566), fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Section C: Speed & GPS ───────────────────────────────────────────────────

class _SpeedSection extends StatelessWidget {
  final bool benchRunning;
  final BenchmarkResult? benchResult;
  final VoidCallback onRunBenchmark;

  const _SpeedSection({
    required this.benchRunning,
    required this.benchResult,
    required this.onRunBenchmark,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GpsService>(
      builder: (_, gps, __) {
        final data = gps.data;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Speedometer
                SpeedometerWidget(speedKmh: data.speedKmh),
                const SizedBox(height: 16),
                // GPS info
                _GpsInfoRow(data: data),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF1A1A2E)),
                const SizedBox(height: 12),
                // Benchmark
                _BenchmarkPanel(
                  running: benchRunning,
                  result: benchResult,
                  onRun: onRunBenchmark,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GpsInfoRow extends StatelessWidget {
  final GpsData data;
  const _GpsInfoRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          data.hasSignal ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
          color: data.hasSignal ? const Color(0xFF00FF88) : const Color(0xFF445566),
          size: 16,
        ),
        const SizedBox(width: 8),
        if (data.hasSignal && data.latitude != null && data.longitude != null)
          Text(
            '${data.latitude!.toStringAsFixed(5)}, ${data.longitude!.toStringAsFixed(5)}',
            style: const TextStyle(
              color: Color(0xFF00FF88),
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          )
        else
          const Text(
            'GPS: No signal — simulated speed',
            style: TextStyle(color: Color(0xFF445566), fontSize: 13),
          ),
      ],
    );
  }
}

class _BenchmarkPanel extends StatelessWidget {
  final bool running;
  final BenchmarkResult? result;
  final VoidCallback onRun;

  const _BenchmarkPanel({required this.running, this.result, required this.onRun});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'HTTP BENCHMARK',
                style: TextStyle(
                  color: Color(0xFF556677),
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: running ? null : onRun,
              icon: running
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 16),
              label: Text(running ? 'Running…' : 'Run Benchmark'),
              style: ElevatedButton.styleFrom(
                backgroundColor: running ? const Color(0xFF334455) : const Color(0xFF00D4FF),
                foregroundColor: running ? const Color(0xFF778899) : Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        if (result != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.3)),
            ),
            child: Column(
              children: [
                // RPS — hero metric
                Text(
                  '${result!.rps.toStringAsFixed(1)} RPS',
                  style: const TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const Text(
                  'Requests per second (50 concurrent GET /apps)',
                  style: TextStyle(color: Color(0xFF445566), fontSize: 11),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _BenchStat(
                      label: 'SUCCESS',
                      value: '${result!.successCount}/${result!.totalRequests}',
                      color: result!.successCount == result!.totalRequests
                          ? const Color(0xFF00FF88)
                          : const Color(0xFFFFCC00),
                    ),
                    _BenchStat(
                      label: 'AVG',
                      value: '${result!.avgLatencyMs.toStringAsFixed(0)} ms',
                      color: const Color(0xFFCCCCDD),
                    ),
                    _BenchStat(
                      label: 'MIN',
                      value: '${result!.minLatencyMs} ms',
                      color: const Color(0xFF00FF88),
                    ),
                    _BenchStat(
                      label: 'MAX',
                      value: '${result!.maxLatencyMs} ms',
                      color: const Color(0xFFFF6644),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ] else if (!running) ...[
          const SizedBox(height: 12),
          const Text(
            'Fire 50 concurrent HTTP requests to the AGL backend and measure RPS',
            style: TextStyle(color: Color(0xFF334455), fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _BenchStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BenchStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF445566),
            fontSize: 9,
            letterSpacing: 1,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
