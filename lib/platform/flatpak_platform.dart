import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  /// Bus for events emitted by the Dart fallback path (when the native
  /// plugin is absent). The `installEvents()` stream merges these with
  /// the native EventChannel so the bloc sees a uniform event shape
  /// regardless of platform.
  static final StreamController<dynamic> _syntheticEvents =
      StreamController<dynamic>.broadcast();

  /// Returns a unified stream of install progress / done events.
  ///
  /// Sources merged:
  ///   1. Native EventChannel (when the C++ plugin is loaded)
  ///   2. Synthetic events pushed by the Dart `Process.run` fallback
  ///      (used on flutter-auto / AGL where the native plugin is absent)
  ///
  /// We probe the method channel via `ping` to decide whether to attach
  /// the native source. We cannot rely on `handleError` for the
  /// MissingPluginException because Flutter's EventChannel routes it to
  /// `FlutterError.reportError` instead of the stream's error sink.
  static Stream<dynamic> installEvents() {
    late StreamController<dynamic> controller;
    StreamSubscription<dynamic>? nativeSub;
    StreamSubscription<dynamic>? syntheticSub;

    controller = StreamController<dynamic>.broadcast(
      onListen: () async {
        // Always pipe synthetic events — they're how the Dart fallback
        // tells the bloc that an install/uninstall finished.
        syntheticSub = _syntheticEvents.stream.listen(controller.add);

        // Optionally attach native event channel.
        if (!_useProcessFallback) {
          try {
            await _channel.invokeMethod<bool>('ping');
          } on MissingPluginException {
            _useProcessFallback = true;
          } catch (_) {
            // PlatformException etc. — plugin exists; ignore probe failure.
          }
        }
        if (_useProcessFallback) return;
        try {
          nativeSub = _events.receiveBroadcastStream().listen(
            controller.add,
            onError: controller.addError,
          );
        } catch (_) {
          _useProcessFallback = true;
        }
      },
      onCancel: () async {
        await nativeSub?.cancel();
        await syntheticSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Push a synthetic event to mirror the native `done` payload shape so
  /// the bloc's existing event listener can process it uniformly.
  static void _emitDone(String appId, {required bool ok}) {
    _syntheticEvents.add({
      'type': 'done',
      'appId': appId,
      'status': ok ? 0 : 1,
    });
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
  /// Runs a command, falling back to absolute paths if PATH is not set
  /// (systemd services on AGL may have a minimal environment).
  static Future<String> _run(String cmd, List<String> args) async {
    ProcessResult result;
    try {
      result = await Process.run(cmd, args);
    } on ProcessException {
      // Command not found in PATH — try known absolute paths
      final absPath = await _resolveAbsolute(cmd);
      if (absPath == null) {
        throw Exception('$cmd: command not found in PATH or standard locations');
      }
      result = await Process.run(absPath, args);
    }
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      throw Exception('$cmd ${args.join(' ')} failed (${result.exitCode}): $stderr');
    }
    return result.stdout.toString().trim();
  }

  /// Resolves a command name to an absolute path by checking standard locations.
  static Future<String?> _resolveAbsolute(String cmd) async {
    for (final prefix in ['/usr/bin/', '/bin/', '/usr/local/bin/', '/usr/sbin/', '/sbin/']) {
      final path = '$prefix$cmd';
      if (await File(path).exists()) return path;
    }
    return null;
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
      } on PlatformException catch (e) {
        // Native plugin loaded but its install path errored. Fall back
        // to the Dart `flatpak` invocation — same binary, but the
        // resulting Exception carries the real stderr so callers /
        // log viewer see why it failed.
        debugPrint('Native install failed for $appId: ${e.message ?? e.code}; falling back to dart:io');
      }
    }
    final r = remote ?? _penshubRemote;
    try {
      await _run('flatpak', [
        'install', '--system', '--noninteractive', '-y', r, appId,
      ]);
      _emitDone(appId, ok: true);
    } catch (e) {
      _emitDone(appId, ok: false);
      rethrow;
    }
  }

  // ── Launch ──────────────────────────────────────────────────
  static Future<void> launch(String appId) async {
    if (!_useProcessFallback) {
      try {
        await _channel.invokeMethod('launchFlatpak', {'appId': appId});
        return;
      } on MissingPluginException {
        _useProcessFallback = true;
      } on PlatformException catch (e) {
        debugPrint('Native launch failed for $appId: ${e.message ?? e.code}; falling back to dart:io');
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
      } on PlatformException catch (e) {
        debugPrint('Native isInstalled failed for $appId: ${e.message ?? e.code}; falling back to dart:io');
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
      } on PlatformException catch (e) {
        debugPrint('Native listInstalled failed: ${e.message ?? e.code}; falling back to dart:io');
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
      } on PlatformException catch (e) {
        debugPrint('Native uninstall failed for $appId: ${e.message ?? e.code}; falling back to dart:io');
      }
    }
    try {
      await _run('flatpak', [
        'uninstall', '--system', '--noninteractive', '-y', appId,
      ]);
      _emitDone(appId, ok: true);
    } catch (e) {
      _emitDone(appId, ok: false);
      rethrow;
    }
  }

  // ── Update ──────────────────────────────────────────────────
  static Future<void> update(String appId) async {
    if (!_useProcessFallback) {
      try {
        await _channel.invokeMethod('updateFlatpak', {'appId': appId});
        return;
      } on MissingPluginException {
        _useProcessFallback = true;
      } on PlatformException catch (e) {
        debugPrint('Native update failed for $appId: ${e.message ?? e.code}; falling back to dart:io');
      }
    }
    try {
      await _run('flatpak', [
        'update', '--system', '--noninteractive', '-y', appId,
      ]);
      _emitDone(appId, ok: true);
    } catch (e) {
      _emitDone(appId, ok: false);
      rethrow;
    }
  }

  // ── Refresh appstream ───────────────────────────────────────
  /// Refreshes appstream metadata for each known remote.
  ///
  /// On AGL flutter-auto the native plugin is absent, so this falls back
  /// to spawning `flatpak` per-remote. Each remote runs independently so
  /// a failure on one (e.g. "No such ref appstream/ARCH in remote
  /// penshub" when a remote doesn't publish appstream branches) does not
  /// affect the others. stderr/stdout are captured and discarded so the
  /// flutter-auto journal stays clean.
  static Future<void> refreshAppstream() async {
    if (!_useProcessFallback) {
      try {
        await _channel.invokeMethod('refreshAppstream');
        return;
      } on MissingPluginException {
        _useProcessFallback = true;
      }
    }
    await Future.wait([
      _silentAppstreamRefresh('flathub'),
      _silentAppstreamRefresh(_penshubRemote),
    ]);
  }

  /// Runs `flatpak update --appstream <remote>` swallowing all output and
  /// any failure. Used for opportunistic appstream warmup; never throws.
  static Future<void> _silentAppstreamRefresh(String remote) async {
    final args = ['update', '--system', '--appstream', '-y', remote];
    try {
      await Process.run('flatpak', args);
      return;
    } on ProcessException {
      // `flatpak` not in PATH (minimal systemd env on AGL) — try abs path
    } catch (_) {
      return;
    }
    final abs = await _resolveAbsolute('flatpak');
    if (abs == null) return;
    try {
      await Process.run(abs, args);
    } catch (_) {
      // intentionally ignored
    }
  }
}
