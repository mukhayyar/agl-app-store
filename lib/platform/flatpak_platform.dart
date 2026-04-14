import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Flatpak operations for the AGL App Store.
///
/// Uses a **multi-strategy chain** for every operation. Each method tries
/// several approaches in order, falling through to the next on failure:
///
///   Strategy 1: Native C++ Platform Channel   (desktop GTK runner)
///   Strategy 2: `flatpak ... --system` CLI    (root-privileged embedded)
///   Strategy 3: `flatpak ... --user` CLI      (unprivileged or no system install)
///   Strategy 4: `flatpak ...` CLI (auto scope)(last-resort)
///
/// Only if ALL strategies fail does the method throw. Errors from each
/// attempt are collected and included in the final exception message for
/// easier debugging.
class FlatpakPlatform {
  static const _channel = MethodChannel('com.pens.flatpak/installer');
  static const _events = EventChannel('com.pens.flatpak/installer_events');

  /// Whether we've detected the native plugin is unavailable.
  /// Starts as `true` (assume no native plugin) and flips to `false` only
  /// if init() successfully probes the channel.
  static bool _useProcessFallback = true;
  static bool _initialized = false;

  static const _penshubRemote = 'penshub';
  static const _penshubUrl = 'https://repo.agl-store.cyou';
  static const _penshubGpgUrl = 'https://repo.agl-store.cyou/public.gpg';
  static const _gpgTmpPath = '/tmp/penshub.gpg';

  // ════════════════════════════════════════════════════════════════
  // INIT — probe the native plugin once at app startup
  // ════════════════════════════════════════════════════════════════

  /// Probes the native MethodChannel ONCE at app startup. Call from main()
  /// BEFORE runApp() so installEvents() can skip receiveBroadcastStream on
  /// flutter-auto (which would log a spurious MissingPluginException).
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _channel.invokeMethod<bool>('isInstalled', {
        'appId': 'probe.nonexistent',
      });
      _useProcessFallback = false;
    } on MissingPluginException {
      _useProcessFallback = true;
    } catch (_) {
      _useProcessFallback = false;
    }
  }

  // ════════════════════════════════════════════════════════════════
  // CHAIN RUNNER — execute strategies in order, return first success
  // ════════════════════════════════════════════════════════════════

  /// Runs async strategies in order. Returns the result of the first
  /// strategy that succeeds. If all fail, throws an Exception with all
  /// collected error messages for debugging.
  static Future<T> _chain<T>(
    String opName,
    List<Future<T> Function()> strategies,
  ) async {
    final errors = <String>[];
    for (var i = 0; i < strategies.length; i++) {
      try {
        return await strategies[i]();
      } catch (e) {
        errors.add('  [${i + 1}] $e');
      }
    }
    throw Exception(
      '$opName: all ${strategies.length} strategies failed:\n'
      '${errors.join("\n")}',
    );
  }

  // ════════════════════════════════════════════════════════════════
  // HELPER — run a CLI command with absolute-path fallback
  // ════════════════════════════════════════════════════════════════

  /// Runs a command. If not in PATH, tries common absolute locations.
  /// Throws on non-zero exit code.
  static Future<String> _run(String cmd, List<String> args) async {
    ProcessResult result;
    try {
      result = await Process.run(cmd, args);
    } on ProcessException {
      final absPath = await _resolveAbsolute(cmd);
      if (absPath == null) {
        throw Exception('$cmd: command not found');
      }
      result = await Process.run(absPath, args);
    }
    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      throw Exception('$cmd exited ${result.exitCode}: $err');
    }
    return result.stdout.toString().trim();
  }

  static Future<String?> _resolveAbsolute(String cmd) async {
    for (final prefix in const [
      '/usr/bin/', '/bin/', '/usr/local/bin/', '/usr/sbin/', '/sbin/',
    ]) {
      final path = '$prefix$cmd';
      if (await File(path).exists()) return path;
    }
    return null;
  }

  // ════════════════════════════════════════════════════════════════
  // EVENT STREAM — install progress events
  // ════════════════════════════════════════════════════════════════

  static Stream<dynamic> installEvents() {
    if (_useProcessFallback) return const Stream.empty();
    return _events.receiveBroadcastStream().handleError(
      (_) => _useProcessFallback = true,
      test: (e) => e is MissingPluginException,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // APP LIFECYCLE — kiosk-mode exit
  // ════════════════════════════════════════════════════════════════

  static Future<void> exitApp() async {
    try {
      await _run('systemctl', ['stop', 'agl-app-flutter@agl_app_store']);
    } catch (_) {}
    exit(0);
  }

  // ════════════════════════════════════════════════════════════════
  // ENSURE REMOTE — register PENSHub with fallbacks
  // ════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> ensureRemote() async {
    return _chain<Map<String, dynamic>>('ensureRemote', [
      // Strategy 1 — native plugin
      () async {
        if (_useProcessFallback) throw Exception('native plugin unavailable');
        final result = await _channel
            .invokeMethod<Map<dynamic, dynamic>>('ensureRemote');
        return Map<String, dynamic>.from(result ?? {});
      },
      // Strategy 2 — already exists?
      () async {
        final remotes =
            await _run('flatpak', ['remote-list', '--system', '--columns=name']);
        if (remotes.contains(_penshubRemote)) {
          return {'added': false, 'alreadyExists': true};
        }
        throw Exception('not present');
      },
      // Strategy 3 — fetch GPG + add with verification (system)
      () async {
        await _fetchGpgKey();
        await _run('flatpak', [
          'remote-add', '--system', '--if-not-exists',
          '--gpg-import=$_gpgTmpPath', _penshubRemote, _penshubUrl,
        ]);
        return {'added': true, 'alreadyExists': false};
      },
      // Strategy 4 — fetch GPG + add with verification (user)
      () async {
        await _fetchGpgKey();
        await _run('flatpak', [
          'remote-add', '--user', '--if-not-exists',
          '--gpg-import=$_gpgTmpPath', _penshubRemote, _penshubUrl,
        ]);
        return {'added': true, 'alreadyExists': false};
      },
      // Strategy 5 — add without GPG verification (last resort)
      () async {
        await _run('flatpak', [
          'remote-add', '--system', '--if-not-exists',
          '--no-gpg-verify', _penshubRemote, _penshubUrl,
        ]);
        return {'added': true, 'alreadyExists': false, 'noGpg': true};
      },
    ]);
  }

  static Future<void> _fetchGpgKey() async {
    await _chain<void>('fetchGpgKey', [
      () async {
        await _run('wget', ['-q', '-O', _gpgTmpPath, _penshubGpgUrl]);
      },
      () async {
        await _run('curl', ['-sfL', '-o', _gpgTmpPath, _penshubGpgUrl]);
      },
    ]);
  }

  // ════════════════════════════════════════════════════════════════
  // INSTALL — multi-strategy
  // ════════════════════════════════════════════════════════════════

  static Future<void> install(String appId, {String? remote}) async {
    final r = remote ?? _penshubRemote;
    await _chain<void>('install $appId', [
      () async {
        if (_useProcessFallback) throw Exception('native plugin unavailable');
        await _channel.invokeMethod('installFlatpak', {
          'appId': appId, if (remote != null) 'remote': remote,
        });
      },
      () async {
        await _run('flatpak', [
          'install', '--system', '--noninteractive', '-y', r, appId,
        ]);
      },
      () async {
        await _run('flatpak', [
          'install', '--user', '--noninteractive', '-y', r, appId,
        ]);
      },
      () async {
        await _run('flatpak', [
          'install', '--noninteractive', '-y', r, appId,
        ]);
      },
    ]);
  }

  // ════════════════════════════════════════════════════════════════
  // UNINSTALL — multi-strategy
  // ════════════════════════════════════════════════════════════════

  static Future<void> uninstall(String appId) async {
    await _chain<void>('uninstall $appId', [
      () async {
        if (_useProcessFallback) throw Exception('native plugin unavailable');
        await _channel.invokeMethod('uninstallFlatpak', {'appId': appId});
      },
      () async {
        await _run('flatpak', [
          'uninstall', '--system', '--noninteractive', '-y', appId,
        ]);
      },
      () async {
        await _run('flatpak', [
          'uninstall', '--user', '--noninteractive', '-y', appId,
        ]);
      },
      () async {
        await _run('flatpak', [
          'uninstall', '--noninteractive', '-y', appId,
        ]);
      },
    ]);
  }

  // ════════════════════════════════════════════════════════════════
  // LAUNCH — multi-strategy
  // ════════════════════════════════════════════════════════════════

  static Future<void> launch(String appId) async {
    await _chain<void>('launch $appId', [
      () async {
        if (_useProcessFallback) throw Exception('native plugin unavailable');
        await _channel.invokeMethod('launchFlatpak', {'appId': appId});
      },
      // Detached processes — fire & forget so the app doesn't block UI
      () async {
        final cmd = await _resolveAbsolute('flatpak') ?? 'flatpak';
        await Process.start(cmd, ['run', appId],
            mode: ProcessStartMode.detached);
      },
      () async {
        final cmd = await _resolveAbsolute('flatpak') ?? 'flatpak';
        await Process.start(cmd, ['run', '--user', appId],
            mode: ProcessStartMode.detached);
      },
    ]);
  }

  // ════════════════════════════════════════════════════════════════
  // IS INSTALLED — check via multiple scopes
  // ════════════════════════════════════════════════════════════════

  static Future<bool> isInstalled(String appId) async {
    // Try native first
    if (!_useProcessFallback) {
      try {
        final ok = await _channel.invokeMethod('isInstalled', {'appId': appId});
        return ok == true;
      } on MissingPluginException {
        _useProcessFallback = true;
      } catch (_) {
        // fall through to CLI
      }
    }
    // Try both scopes — true if found anywhere
    for (final scope in ['--system', '--user']) {
      try {
        await _run('flatpak', ['info', scope, appId]);
        return true;
      } catch (_) {
        /* not in this scope, try next */
      }
    }
    return false;
  }

  // ════════════════════════════════════════════════════════════════
  // LIST INSTALLED — merge system + user
  // ════════════════════════════════════════════════════════════════

  static Future<List<Map<String, String>>> listInstalled() async {
    // Try native first
    if (!_useProcessFallback) {
      try {
        final list =
            await _channel.invokeMethod<List<dynamic>>('listInstalled');
        return (list ?? []).map((e) {
          final m = Map<String, dynamic>.from(e);
          return {
            'id': m['id']?.toString() ?? '',
            'name': m['name']?.toString() ?? '',
          };
        }).toList();
      } on MissingPluginException {
        _useProcessFallback = true;
      } catch (_) {
        // fall through to CLI
      }
    }
    // CLI: merge system + user installs, dedup by id
    final seen = <String>{};
    final result = <Map<String, String>>[];
    for (final scope in ['--system', '--user']) {
      try {
        final output = await _run('flatpak', [
          'list', scope, '--app', '--columns=application,name',
        ]);
        if (output.isEmpty) continue;
        for (final line in output.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final parts = trimmed.split('\t');
          final id = parts.isNotEmpty ? parts[0].trim() : '';
          if (id.isEmpty || seen.contains(id)) continue;
          seen.add(id);
          result.add({
            'id': id,
            'name': parts.length > 1 ? parts[1].trim() : id,
          });
        }
      } catch (_) {
        /* skip this scope */
      }
    }
    return result;
  }

  // ════════════════════════════════════════════════════════════════
  // UPDATE — multi-strategy
  // ════════════════════════════════════════════════════════════════

  static Future<void> update(String appId) async {
    await _chain<void>('update $appId', [
      () async {
        if (_useProcessFallback) throw Exception('native plugin unavailable');
        await _channel.invokeMethod('updateFlatpak', {'appId': appId});
      },
      () async {
        await _run('flatpak', [
          'update', '--system', '--noninteractive', '-y', appId,
        ]);
      },
      () async {
        await _run('flatpak', [
          'update', '--user', '--noninteractive', '-y', appId,
        ]);
      },
    ]);
  }

  // ════════════════════════════════════════════════════════════════
  // REFRESH APPSTREAM — fire & forget, non-blocking
  // ════════════════════════════════════════════════════════════════

  static Future<void> refreshAppstream() async {
    if (!_useProcessFallback) {
      try {
        await _channel.invokeMethod('refreshAppstream');
        return;
      } on MissingPluginException {
        _useProcessFallback = true;
      } catch (_) {/* fall through */}
    }
    // Fire & forget both scopes
    for (final scope in ['--system', '--user']) {
      try {
        final cmd = await _resolveAbsolute('flatpak') ?? 'flatpak';
        await Process.start(cmd, ['update', scope, '--appstream'],
            mode: ProcessStartMode.detached);
      } catch (_) {/* skip */}
    }
  }
}
