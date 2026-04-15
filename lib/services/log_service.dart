import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Severity tag for a log entry, used by the in-app log viewer for color coding.
enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String message;
  const LogEntry(this.time, this.level, this.message);
}

/// Captures `print`, `debugPrint`, and `FlutterError.onError` into a
/// bounded ring buffer so the Monitor page can show a live tail of the
/// app's logs without needing journalctl/SSH access.
///
/// Wire it up once in `main()` BEFORE `runApp` by calling
/// [LogService.install]. It registers a custom `debugPrint` and a
/// `FlutterError.onError` handler. Wrap `runApp` in
/// [LogService.runZoned] to also capture plain `print()` output and any
/// uncaught zone errors.
class LogService extends ChangeNotifier {
  LogService._();

  static final LogService instance = LogService._();

  static const _capacity = 300;
  final ListQueue<LogEntry> _entries = ListQueue<LogEntry>();
  UnmodifiableListView<LogEntry> get entries =>
      UnmodifiableListView<LogEntry>(_entries);

  static bool _installed = false;

  /// Install global hooks. Safe to call multiple times — only the first
  /// call has an effect.
  static void install() {
    if (_installed) return;
    _installed = true;

    // Tee debugPrint into the buffer while preserving original behavior.
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        instance._add(LogLevel.debug, message);
      }
      original(message, wrapWidth: wrapWidth);
    };

    // Capture Flutter framework errors as full entries.
    final priorErrorHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      instance._add(
        LogLevel.error,
        'FlutterError: ${details.exceptionAsString()}',
      );
      if (priorErrorHandler != null) priorErrorHandler(details);
    };
  }

  /// Wrap `runApp` so plain `print()` and uncaught zone errors land in
  /// the buffer too. Returns whatever [body] returns.
  static R runZoned<R>(R Function() body) {
    return runZonedGuarded<R>(
      body,
      (error, stack) {
        instance._add(LogLevel.error, 'Uncaught: $error');
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          instance._add(LogLevel.info, line);
          parent.print(zone, line);
        },
      ),
    ) as R;
  }

  /// Manually push a log line — useful for code paths that don't go
  /// through `print` / `debugPrint` (e.g. you have a structured event).
  void log(LogLevel level, String message) => _add(level, message);

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void _add(LogLevel level, String message) {
    final lvl = _inferLevel(level, message);
    _entries.addLast(LogEntry(DateTime.now(), lvl, message));
    while (_entries.length > _capacity) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  /// Promote a debug-tagged line to warning/error if its content looks
  /// like one — most of our debugPrints carry semantic prefixes.
  LogLevel _inferLevel(LogLevel base, String message) {
    if (base != LogLevel.debug) return base;
    final lower = message.toLowerCase();
    if (lower.contains('error') ||
        lower.contains('exception') ||
        lower.contains('failed')) {
      return LogLevel.error;
    }
    if (lower.contains('warn') || lower.contains('falling back')) {
      return LogLevel.warning;
    }
    return LogLevel.info;
  }
}
