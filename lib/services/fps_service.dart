import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Tracks rendering performance by subscribing to Flutter's frame
/// timings.
///
/// Notes on meaning:
/// - Flutter only raster-schedules a frame when something needs to
///   redraw. On a completely static screen `current` can drop to ~0
///   even on a healthy device — that's Flutter being efficient, not
///   a perf problem. FPS readings are meaningful while something is
///   animating or the user is scrolling.
/// - `current` = frames actually rendered in the last ~1 s.
/// - `average` = running mean over the last `_historySize` samples
///   (excluding leading zero samples before the service started ticking).
/// - `history` = the last `_historySize` per-second samples so the
///   monitor can draw a trend chart.
class FpsService extends ChangeNotifier {
  static const _historySize = 60;
  static const _targetFps = 60.0;

  double current = 0;
  double average = 0;
  // Published as a fresh list every tick so widget reconciliation
  // sees a new object reference and rebuilds the chart.
  List<double> history = List.filled(_historySize, 0);

  int _frameCountThisSecond = 0;
  Timer? _ticker;
  TimingsCallback? _cb;

  void start() {
    if (_ticker != null) return;
    _cb = _onFrames;
    SchedulerBinding.instance.addTimingsCallback(_cb!);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
    if (_cb != null) {
      SchedulerBinding.instance.removeTimingsCallback(_cb!);
      _cb = null;
    }
  }

  void _onFrames(List<FrameTiming> timings) {
    _frameCountThisSecond += timings.length;
  }

  void _tick() {
    current = _frameCountThisSecond.toDouble().clamp(0.0, 120.0);
    _frameCountThisSecond = 0;

    history = [...history.skip(1), current];

    // Running average over samples we've actually measured. Skipping
    // leading zeros (from before the service was producing numbers)
    // avoids dragging the average down for the first minute.
    final measured = history.where((v) => v > 0).toList();
    average = measured.isEmpty
        ? 0
        : measured.reduce((a, b) => a + b) / measured.length;

    notifyListeners();
  }

  /// Target FPS, exposed for UI gauges/thresholds.
  double get target => _targetFps;

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
