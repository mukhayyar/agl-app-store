import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Flatpak operations for the AGL App Store.
///
/// Uses a **dual strategy**:
///   1. Try the native C++ Platform Channel (works on desktop GTK runner)
///   2. Fall back to `dart:io` Process.run (works on flutter-auto / AGL)
///
/// This ensures the app works both during development (desktop) and on
/// the actual AGL embedded target where flutter-auto doesn't compile
/// the native linux/runner plugin.
class FlatpakPlatform {
  static const _channel = MethodChannel('com.pens.flatpak/installer');
  static const _events = EventChannel('com.pens.flatpak/installer_events');

  /// Whether we've detected the native plugin is unavailable
  static bool _useProcessFallback = false;

  static const _penshubRemote = 'penshub';
  static const _penshubUrl = 'https://repo.agl-store.cyou';
  static const _penshubGpgUrl = 'https://repo.agl-store.cyou/public.gpg';
  static const _gpgTmpPath = '/tmp/penshub.gpg';

  // ── Install events stream ───────────────────────────────────
  /// Returns a stream of install progress events from the native plugin.
  /// On flutter-auto (AGL) the native plugin is not available, so we return
  /// an empty stream. The stream wraps receiveBroadcastStream with a
  /// handleError to silently swallow MissingPluginException that fires
  /// asynchronously when .listen() is called.
  static Stream<dynamic> installEvents() {
    if (_useProcessFallback) return const Stream.empty();
    try {
      return _events.receiveBroadcastStream().handleError(
        (error) {
          // Swallow MissingPluginException — flutter-auto doesn't have the
          // native plugin. All subsequent calls will use Process.run fallback.
          _useProcessFallback = true;
        },
        test: (error) => error is MissingPluginException,
      );
    } catch (_) {
      _useProcessFallback = true;
      return const Stream.empty();
    }
  }

  // ── Exit the app (for kiosk/embedded mode) ──────────────────
  /// Forces the flutter-auto process to exit cleanly. Used by the UI
  /// close button on embedded targets where the app would otherwise
  /// hog the compositor and require SSH + systemctl stop to kill.
  static Future<void> exitApp() async {
    // Try to cleanly exit; SIGTERM our own process group
    try {
      await Process.run('systemctl', ['stop', 'agl-app-flutter@agl_app_store']);
    } catch (_) {
      // Fallback: just exit the dart VM
    }
    // If systemctl stop didn't kill us (e.g. running as root from terminal),
    // exit the process directly
    exit(0);
  }

  // ── Helper: run a process and return stdout ─────────────────
  static Future<String> _run(String cmd, List<String> args) async {
    final result = await Process.run(cmd, args);
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      throw Exception('$cmd ${args.join(' ')} failed (${ result.exitCode}): $stderr');
    }
    return result.stdout.toString().trim();
  }

  // ── Ensure remote ───────────────────────────────────────────
  static Future<Map<String, dynamic>> ensureRemote() async {
    if (!_useProcessFallback) {
      try {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('ensureRemote');
        return Map<String, dynamic>.from(result ?? {});
      } on MissingPluginException {
        _useProcessFallback = true;
      }
    }
    // Fallback: use dart:io
    return _ensureRemoteFallback();
  }

  static Future<Map<String, dynamic>> _ensureRemoteFallback() async {
    try {
      // Check if penshub remote already exists
      final remotes = await _run('flatpak', ['remote-list', '--system', '--columns=name']);
      if (remotes.contains(_penshubRemote)) {
        return {'added': false, 'alreadyExists': true};
      }
      // Download GPG key
      try {
        await _run('wget', ['-q', '-O', _gpgTmpPath, _penshubGpgUrl]);
      } catch (_) {
        try {
          await _run('curl', ['-sfL', '-o', _gpgTmpPath, _penshubGpgUrl]);
        } catch (_) {
          // Add without GPG if we can't fetch the key
          await _run('flatpak', [
            'remote-add', '--system', '--if-not-exists',
            '--no-gpg-verify', _penshubRemote, _penshubUrl,
          ]);
          return {'added': true, 'alreadyExists': false};
        }
      }
      // Add with GPG verification
      await _run('flatpak', [
        'remote-add', '--system', '--if-not-exists',
        '--gpg-import=$_gpgTmpPath', _penshubRemote, _penshubUrl,
      ]);
      return {'added': true, 'alreadyExists': false};
    } catch (e) {
      return {'added': false, 'alreadyExists': false, 'error': e.toString()};
    }
  }

  // ── Install ─────────────────────────────────────────────────
  static Future<void> install(String appId, {String? remote}) async {
    if (!_useProcessFallback) {
      try {
        await _channel.invokeMethod('installFlatpak', {
          'appId': appId,
          if (remote != null) 'remote': remote,
        });
        return;
      } on MissingPluginException {
        _useProcessFallback = true;
      }
    }
    final r = remote ?? _penshubRemote;
    await _run('flatpak', [
      'install', '--system', '--noninteractive', '-y', r, appId,
    ]);
  }

  // ── Launch ──────────────────────────────────────────────────
  static Future<void> launch(String appId) async {
    if (!_useProcessFallback) {
      try {
        await _channel.invokeMethod('launchFlatpak', {'appId': appId});
        return;
      } on MissingPluginException {
        _useProcessFallback = true;
      }
    }
    // Fire and forget — don't await the launched app
    Process.start('flatpak', ['run', appId],
        mode: ProcessStartMode.detached);
  }

  // ── Is installed ────────────────────────────────────────────
  static Future<bool> isInstalled(String appId) async {
    if (!_useProcessFallback) {
      try {
        final ok = await _channel.invokeMethod('isInstalled', {'appId': appId});
        return ok == true;
      } on MissingPluginException {
        _useProcessFallback = true;
      }
    }
    try {
      await _run('flatpak', ['info', '--system', appId]);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── List installed ──────────────────────────────────────────
  static Future<List<Map<String, String>>> listInstalled() async {
    if (!_useProcessFallback) {
      try {
        final list = await _channel.invokeMethod<List<dynamic>>('listInstalled');
        return (list ?? []).map((e) {
          final m = Map<String, dynamic>.from(e);
          return {
            'id': m['id']?.toString() ?? '',
            'name': m['name']?.toString() ?? '',
          };
        }).toList();
      } on MissingPluginException {
        _useProcessFallback = true;
      }
    }
    // Fallback: parse flatpak list output
    try {
      final output = await _run('flatpak', [
        'list', '--system', '--app', '--columns=application,name',
      ]);
      if (output.isEmpty) return [];
      return output.split('\n').where((l) => l.trim().isNotEmpty).map((line) {
        final parts = line.split('\t');
        return {
          'id': parts.isNotEmpty ? parts[0].trim() : '',
          'name': parts.length > 1 ? parts[1].trim() : parts[0].trim(),
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Uninstall ───────────────────────────────────────────────
  static Future<void> uninstall(String appId) async {
    if (!_useProcessFallback) {
      try {
        await _channel.invokeMethod('uninstallFlatpak', {'appId': appId});
        return;
      } on MissingPluginException {
        _useProcessFallback = true;
      }
    }
    await _run('flatpak', [
      'uninstall', '--system', '--noninteractive', '-y', appId,
    ]);
  }

  // ── Update ──────────────────────────────────────────────────
  static Future<void> update(String appId) async {
    if (!_useProcessFallback) {
      try {
        await _channel.invokeMethod('updateFlatpak', {'appId': appId});
        return;
      } on MissingPluginException {
        _useProcessFallback = true;
      }
    }
    await _run('flatpak', [
      'update', '--system', '--noninteractive', '-y', appId,
    ]);
  }

  // ── Refresh appstream ───────────────────────────────────────
  static Future<void> refreshAppstream() async {
    if (!_useProcessFallback) {
      try {
        await _channel.invokeMethod('refreshAppstream');
        return;
      } on MissingPluginException {
        _useProcessFallback = true;
      }
    }
    // Fire and forget for both remotes
    Process.start('flatpak', ['update', '--system', '--appstream'],
        mode: ProcessStartMode.detached);
  }
}
