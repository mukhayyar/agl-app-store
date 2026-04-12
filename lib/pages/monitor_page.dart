import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/system_monitor.dart';
import '../services/gps_service.dart';
import '../services/api_benchmark.dart';
import '../widgets/gauge_widget.dart';
import '../widgets/speedometer_widget.dart';
import '../widgets/line_chart_widget.dart';

// ─────────────────────────── Colour tokens ───────────────────────────
const _bg = Color(0xFF0D0D0D);
const _surface = Color(0xFF1A1A2E);
const _accent = Color(0xFF00D4FF);
const _textPrimary = Colors.white;
final _textSecondary = Colors.white.withOpacity(0.55);

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  // ── Latency history ──────────────────────────────────────────────────
  final List<double?> _latencyHistory = List.filled(30, null);
  Timer? _latencyTimer;
  double? _currentLatencyMs;

  // ── Benchmark state ──────────────────────────────────────────────────
  bool _benchRunning = false;
  BenchmarkResult? _lastBenchResult;

  @override
  void initState() {
    super.initState();
    _startLatencyPoll();
  }

  @override
  void dispose() {
    _latencyTimer?.cancel();
    super.dispose();
  }

  void _startLatencyPoll() {
    _latencyTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final bench = context.read<ApiBenchmark>();
      final ms = await bench.measureLatency();
      if (!mounted) return;
      setState(() {
        _latencyHistory.removeAt(0);
        _latencyHistory.add(ms);
        _currentLatencyMs = ms;
      });
    });
  }

  Future<void> _runBenchmark() async {
    if (_benchRunning) return;
    setState(() => _benchRunning = true);
    final bench = context.read<ApiBenchmark>();
    final result = await bench.runBenchmark(count: 50);
    if (!mounted) return;
    setState(() {
      _benchRunning = false;
      _lastBenchResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<SystemMonitor>();
    final gps = context.watch<GpsService>();

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.monitor_heart, color: _accent, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'IVI Monitor',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00FF88),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Color(0xFF00FF88),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Section A: System Usage ─────────────────────────────
              _sectionLabel('SYSTEM USAGE'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _CpuCard(monitor: monitor)),
                  const SizedBox(width: 10),
                  Expanded(child: _RamCard(monitor: monitor)),
                  const SizedBox(width: 10),
                  Expanded(child: _DiskCard(monitor: monitor)),
                ],
              ),
              const SizedBox(height: 20),

              // ── Section B: Network ──────────────────────────────────
              _sectionLabel('NETWORK'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _LatencyCard(
                      history: _latencyHistory,
                      currentMs: _currentLatencyMs,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ThroughputCard(
                      monitor: monitor,
                      benchRunning: _benchRunning,
                      lastResult: _lastBenchResult,
                      onRunBenchmark: _runBenchmark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Section C: Speed & GPS ──────────────────────────────
              _sectionLabel('SPEED & GPS'),
              const SizedBox(height: 10),
              _SpeedGpsCard(
                gps: gps,
                benchRunning: _benchRunning,
                lastResult: _lastBenchResult,
                onRunBenchmark: _runBenchmark,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: _accent,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
    );
  }
}

// ─────────────────────────── CPU Card ────────────────────────────────
class _CpuCard extends StatelessWidget {
  final SystemMonitor monitor;
  const _CpuCard({required this.monitor});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _CardTitle(text: 'CPU'),
          const SizedBox(height: 8),
          GaugeWidget(value: monitor.cpu, size: 90, label: 'CPU'),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: LineChartWidget(
              data: monitor.cpuHistory,
              maxValue: 100,
              color: _cpuColor(monitor.cpu),
            ),
          ),
        ],
      ),
    );
  }

  Color _cpuColor(double v) {
    if (v < 60) return const Color(0xFF00D4FF);
    if (v < 80) return const Color(0xFFFFAA00);
    return const Color(0xFFFF4444);
  }
}

// ─────────────────────────── RAM Card ────────────────────────────────
class _RamCard extends StatelessWidget {
  final SystemMonitor monitor;
  const _RamCard({required this.monitor});

  @override
  Widget build(BuildContext context) {
    final pct = monitor.ramTotalMb > 0
        ? (monitor.ramUsedMb / monitor.ramTotalMb * 100)
        : 0.0;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _CardTitle(text: 'RAM'),
          const SizedBox(height: 8),
          GaugeWidget(value: pct, size: 90, label: 'RAM'),
          const SizedBox(height: 4),
          Text(
            '${monitor.ramUsedMb.toStringAsFixed(0)} / ${monitor.ramTotalMb.toStringAsFixed(0)} MB',
            style: TextStyle(color: _textSecondary, fontSize: 10),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 40,
            child: LineChartWidget(
              data: monitor.ramHistory,
              maxValue: 100,
              color: const Color(0xFF9C6FFF),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Disk Card ───────────────────────────────
class _DiskCard extends StatelessWidget {
  final SystemMonitor monitor;
  const _DiskCard({required this.monitor});

  @override
  Widget build(BuildContext context) {
    final pct = monitor.diskTotalGb > 0
        ? (monitor.diskUsedGb / monitor.diskTotalGb)
        : 0.0;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(text: 'DISK'),
          const SizedBox(height: 12),
          Text(
            '${monitor.diskUsedGb.toStringAsFixed(1)} GB used',
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'of ${monitor.diskTotalGb.toStringAsFixed(1)} GB',
            style: TextStyle(color: _textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0, 1),
              minHeight: 8,
              backgroundColor: const Color(0xFF2A2A3E),
              valueColor: AlwaysStoppedAnimation<Color>(
                pct < 0.7
                    ? const Color(0xFF00D4FF)
                    : pct < 0.9
                        ? const Color(0xFFFFAA00)
                        : const Color(0xFFFF4444),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(pct * 100).toStringAsFixed(0)}% used',
            style: TextStyle(color: _textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Latency Card ────────────────────────────
class _LatencyCard extends StatelessWidget {
  final List<double?> history;
  final double? currentMs;

  const _LatencyCard({required this.history, required this.currentMs});

  @override
  Widget build(BuildContext context) {
    final displayData = history
        .map((v) => v ?? 0.0)
        .toList();
    final maxMs = displayData.isEmpty
        ? 500.0
        : (displayData.reduce((a, b) => a > b ? a : b) * 1.2).clamp(50, 2000).toDouble();

    Color badgeColor;
    String badgeText;
    if (currentMs == null) {
      badgeColor = Colors.grey;
      badgeText = '-- ms';
    } else if (currentMs! < 100) {
      badgeColor = const Color(0xFF00FF88);
      badgeText = '${currentMs!.toStringAsFixed(0)} ms';
    } else if (currentMs! < 300) {
      badgeColor = const Color(0xFFFFAA00);
      badgeText = '${currentMs!.toStringAsFixed(0)} ms';
    } else {
      badgeColor = const Color(0xFFFF4444);
      badgeText = '${currentMs!.toStringAsFixed(0)} ms';
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CardTitle(text: 'LATENCY'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 70,
            child: LineChartWidget(
              data: displayData,
              maxValue: maxMs,
              color: badgeColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'AGL backend ping (last 30)',
            style: TextStyle(color: _textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Throughput Card ─────────────────────────
class _ThroughputCard extends StatelessWidget {
  final SystemMonitor monitor;
  final bool benchRunning;
  final BenchmarkResult? lastResult;
  final VoidCallback onRunBenchmark;

  const _ThroughputCard({
    required this.monitor,
    required this.benchRunning,
    required this.lastResult,
    required this.onRunBenchmark,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(text: 'THROUGHPUT'),
          const SizedBox(height: 8),
          Row(
            children: [
              _NetBadge(
                label: 'RX',
                value: _formatBytes(monitor.rxBytesPerSec),
                color: const Color(0xFF00FF88),
              ),
              const SizedBox(width: 8),
              _NetBadge(
                label: 'TX',
                value: _formatBytes(monitor.txBytesPerSec),
                color: const Color(0xFF00D4FF),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (lastResult != null) ...[
            _ResultChip(
              label: 'RPS',
              value: lastResult!.rps.toStringAsFixed(1),
            ),
            const SizedBox(height: 4),
            _ResultChip(
              label: 'AVG',
              value: '${lastResult!.avgMs.toStringAsFixed(0)} ms',
            ),
            const SizedBox(height: 4),
            _ResultChip(
              label: 'OK',
              value: '${lastResult!.successCount}/${lastResult!.totalCount}',
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: benchRunning ? null : onRunBenchmark,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: _accent,
                disabledBackgroundColor: const Color(0xFF1E1E2E),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: benchRunning
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_accent),
                      ),
                    )
                  : const Text('Run API Test', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(double bytesPerSec) {
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (bytesPerSec >= 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${bytesPerSec.toStringAsFixed(0)} B/s';
  }
}

// ─────────────────────────── Speed/GPS Card ──────────────────────────
class _SpeedGpsCard extends StatelessWidget {
  final GpsService gps;
  final bool benchRunning;
  final BenchmarkResult? lastResult;
  final VoidCallback onRunBenchmark;

  const _SpeedGpsCard({
    required this.gps,
    required this.benchRunning,
    required this.lastResult,
    required this.onRunBenchmark,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          // Speedometer
          Center(
            child: SpeedometerWidget(
              speedKmh: gps.speedKmh.clamp(0, 120),
              maxSpeed: 120,
              size: 260,
            ),
          ),
          const SizedBox(height: 12),
          // GPS info row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                gps.hasGps ? Icons.gps_fixed : Icons.gps_off,
                color: gps.hasGps ? const Color(0xFF00FF88) : Colors.grey,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                gps.hasGps && gps.lat != null && gps.lon != null
                    ? '${gps.lat!.toStringAsFixed(5)}, ${gps.lon!.toStringAsFixed(5)}'
                    : gps.hasGps
                        ? 'Acquiring signal...'
                        : 'No GPS signal (simulated)',
                style: TextStyle(
                  color: gps.hasGps ? _textPrimary : _textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Full benchmark button
          if (lastResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  _ResultChip(label: 'RPS', value: lastResult!.rps.toStringAsFixed(1)),
                  _ResultChip(label: 'MIN', value: '${lastResult!.minMs.toStringAsFixed(0)} ms'),
                  _ResultChip(label: 'AVG', value: '${lastResult!.avgMs.toStringAsFixed(0)} ms'),
                  _ResultChip(label: 'MAX', value: '${lastResult!.maxMs.toStringAsFixed(0)} ms'),
                  _ResultChip(
                    label: 'OK',
                    value: '${lastResult!.successCount}/${lastResult!.totalCount}',
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: benchRunning ? null : onRunBenchmark,
              icon: benchRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_accent),
                      ),
                    )
                  : const Icon(Icons.speed, size: 18),
              label: Text(benchRunning ? 'Running...' : 'Run Full Benchmark (50 req)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: _accent,
                disabledBackgroundColor: const Color(0xFF1E1E2E),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Shared helpers ───────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String text;
  const _CardTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: _textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _NetBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _NetBadge({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(color: _textPrimary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ResultChip extends StatelessWidget {
  final String label;
  final String value;

  const _ResultChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accent.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: _textSecondary, fontSize: 11),
          ),
          Text(
            value,
            style: const TextStyle(
              color: _accent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
