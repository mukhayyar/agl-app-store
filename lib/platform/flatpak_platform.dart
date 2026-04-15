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

  static const _flathubRemote = 'flathub';
  // `.flatpakrepo` embeds the GPG key inline, so flatpak picks up the
  // canonical Flathub signing key without us having to fetch it.
  static const _flathubRepoUrl =
      'https://dl.flathub.org/repo/flathub.flatpakrepo';

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

  /// Tagged log helper. Goes to stdout so flutter-auto's systemd journal
  /// captures it. Tail with:
  ///   journalctl -u agl-app-flutter@agl_app_store -f | grep FLATPAK
  static void _log(String msg) {
    // ignore: avoid_print
    print('[FLATPAK] $msg');
  }

  /// Push a synthetic event to mirror the native `done` payload shape so
  /// the bloc's existing event listener can process it uniformly.
  static void _emitDone(String appId, {required bool ok}) {
    _log('emitDone appId=$appId ok=$ok');
    _syntheticEvents.add({
      'type': 'done',
      'appId': appId,
      'status': ok ? 0 : 1,
    });
  }

  /// Push a synthetic progress event with optional phase tag.
  /// `phase` is one of 'downloading' | 'installing'.
  static void _emitProgress(String appId, {required int percent, String? phase}) {
    _syntheticEvents.add({
      'type': 'progress',
      'appId': appId,
      'percent': percent,
      if (phase != null) 'phase': phase,
    });
  }

  // flatpak's interactive bar redraws inline — `27%  3.6 MB/s  00:21`.
  // First number followed by % is the step's progress.
  static final RegExp _percentRe = RegExp(r'(\d{1,3})\s*%');

  // Non-interactive / piped output falls back to per-step lines like
  // `Installing 2/7…`. We turn those into a coarse percent so the bar
  // still moves even when flatpak detects no TTY and skips its bar.
  static final RegExp _stepRe = RegExp(
    r'\bInstalling\s+(\d+)\s*/\s*(\d+)\b',
    caseSensitive: false,
  );

  // Explicit deploy markers as a belt-and-braces signal in case neither
  // percent nor step counter appear in the output.
  static final RegExp _deployRe = RegExp(
    r'\b(deploying|installation\s+complete)\b',
    caseSensitive: false,
  );

  /// Streams a long-running flatpak operation, parsing progress lines so
  /// the UI can show a live percentage and a phase indicator instead of
  /// a frozen 0% bar for the entire 5-10 minute install.
  ///
  /// flatpak's stdout format we care about (interactive):
  ///   `Installing 2/7… ▕████   ▎  27%  3.6 MB/s  00:21`
  /// And piped (non-TTY):
  ///   `Installing 2/7…`
  ///
  /// Phase heuristic: <95% → downloading, ≥95% → installing. The deploy/
  /// commit step always lives in the final couple of percent, and most
  /// of the wait time really is network pull, so this matches the
  /// user's mental model of "downloading then installing".
  static Future<void> _streamFlatpakOp({
    required String appId,
    required List<String> args,
    required String initialPhase,
  }) async {
    _log('streamOp start appId=$appId initialPhase=$initialPhase '
        'cmd=flatpak ${args.join(' ')}');
    _emitProgress(appId, percent: 0, phase: initialPhase);

    Process proc;
    try {
      proc = await Process.start('flatpak', args);
      _log('streamOp spawned pid=${proc.pid} appId=$appId');
    } on ProcessException catch (e) {
      _log('streamOp PATH lookup failed for flatpak ($e); trying absolute paths');
      final abs = await _resolveAbsolute('flatpak');
      if (abs == null) {
        _log('streamOp FATAL flatpak binary not found anywhere');
        throw Exception('flatpak: command not found in PATH or standard locations');
      }
      proc = await Process.start(abs, args);
      _log('streamOp spawned pid=${proc.pid} via abs=$abs appId=$appId');
    }

    String phase = initialPhase;
    int lastPct = 0;
    int lastLoggedPct = -1;
    final stderrBuf = StringBuffer();

    void inspectChunk(String chunk) {
      // flatpak uses \r to overwrite its progress bar in place. Split
      // on both \r and \n so each frame is one logical "line".
      for (final raw in chunk.split(RegExp(r'[\r\n]'))) {
        final line = raw.trim();
        if (line.isEmpty) continue;

        // A single line can carry both `Installing 2/7…` and `27%`. We
        // want to combine them into one monotonic overall percent so
        // the bar doesn't snap back to 0% each time a ref finishes.
        //   overall = ((step - 1) + stepPct/100) / total * 100
        // When only one piece is present we degrade gracefully.
        int? step, total, stepPct;

        final sm = _stepRe.firstMatch(line);
        if (sm != null) {
          step = int.tryParse(sm.group(1)!);
          total = int.tryParse(sm.group(2)!);
        }
        final pm = _percentRe.firstMatch(line);
        if (pm != null) {
          stepPct = int.tryParse(pm.group(1)!)?.clamp(0, 100);
        }

        int? overallPct;
        if (step != null && total != null && total > 0) {
          final sp = (stepPct ?? 0) / 100.0;
          overallPct =
              (((step - 1) + sp) / total * 100).round().clamp(0, 100);
        } else if (stepPct != null) {
          // No step counter — single-ref install or odd output shape.
          overallPct = stepPct;
        }

        if (overallPct == null) {
          // Belt-and-braces deploy detection — if flatpak prints
          // nothing we can scrape, at least flip the phase when we
          // see the word.
          if (phase == 'downloading' && _deployRe.hasMatch(line)) {
            phase = 'installing';
            _log('streamOp phase=installing (deploy keyword) appId=$appId line="$line"');
            _emitProgress(appId, percent: lastPct, phase: phase);
          }
          continue;
        }

        // Clamp to monotonic — flatpak occasionally re-draws an older
        // frame; we never want the UI to appear to go backwards.
        if (overallPct < lastPct) overallPct = lastPct;

        final newPhase = overallPct >= 95 ? 'installing' : 'downloading';
        if (newPhase != phase) {
          _log('streamOp phase=$newPhase (pct>=95) appId=$appId pct=$overallPct');
          phase = newPhase;
        }
        lastPct = overallPct;
        // Log roughly every 5% so the journal shows a smooth track.
        if (overallPct >= lastLoggedPct + 5 || overallPct == 100) {
          _log('streamOp progress appId=$appId overall=$overallPct '
              'step=${step ?? '-'}/${total ?? '-'} '
              'stepPct=${stepPct ?? '-'} phase=$phase');
          lastLoggedPct = overallPct;
        }
        _emitProgress(appId, percent: overallPct, phase: phase);
      }
    }

    final stdoutSub = proc.stdout
        .transform(systemEncoding.decoder)
        .listen(inspectChunk);
    final stderrSub = proc.stderr
        .transform(systemEncoding.decoder)
        .listen((chunk) {
      stderrBuf.write(chunk);
      inspectChunk(chunk);
    });

    final code = await proc.exitCode;
    await stdoutSub.cancel();
    await stderrSub.cancel();

    final stderrText = stderrBuf.toString().trim();
    _log('streamOp exit appId=$appId code=$code '
        'stderrLen=${stderrText.length}');
    if (stderrText.isNotEmpty) {
      // Log stderr verbatim — flatpak's failure messages usually live
      // here ("error: GPG verification failed", "Disk full", ...).
      for (final line in stderrText.split('\n')) {
        _log('streamOp stderr appId=$appId | $line');
      }
    }

    if (code != 0) {
      throw Exception('flatpak ${args.join(' ')} failed ($code): $stderrText');
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
  /// Boot-time remote reconciliation.
  ///
  /// Order matters:
  ///   1. **Flathub first** — the known-good baseline. PensHub apps
  ///      frequently depend on freedesktop runtimes from Flathub, so we
  ///      always want Flathub live even if PensHub is broken.
  ///   2. **PensHub second** — our primary catalog, but the signing
  ///      service has rotated keys in the past and shipped images can
  ///      carry a stale GPG key. If we can't verify PensHub we delete
  ///      the remote instead of leaving a half-broken entry that would
  ///      poison every later `flatpak install` with GPG errors.
  ///
  /// Kept backwards-compatible as `ensureRemote` so callers don't need
  /// to change.
  static Future<Map<String, dynamic>> ensureRemote() async => ensureRemotes();

  static Future<Map<String, dynamic>> ensureRemotes() async {
    if (!_useProcessFallback) {
      try {
        final result =
            await _channel.invokeMethod<Map<dynamic, dynamic>>('ensureRemote');
        return Map<String, dynamic>.from(result ?? {});
      } on MissingPluginException {
        _useProcessFallback = true;
      }
    }
    final flathub = await _ensureFlathub();
    final penshub = await _ensurePenshub();
    return {'flathub': flathub, 'penshub': penshub};
  }

  /// Returns the current list of system remote names, or `null` if the
  /// query itself fails (in which case callers should skip the presence
  /// check and just attempt `--if-not-exists` adds).
  static Future<Set<String>?> _listRemotes() async {
    try {
      final out = await _run(
          'flatpak', ['remote-list', '--system', '--columns=name']);
      return out
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
    } catch (e) {
      _log('remote-list failed: $e');
      return null;
    }
  }

  /// Add Flathub using its official `.flatpakrepo` file — the embedded
  /// GPG key is authoritative and survives key rotations, so we don't
  /// need a separate key fetch step.
  static Future<Map<String, dynamic>> _ensureFlathub() async {
    _log('ensureFlathub: begin');
    final remotes = await _listRemotes();
    if (remotes != null && remotes.contains(_flathubRemote)) {
      _log('ensureFlathub: already present');
      return {'status': 'ok', 'message': 'already present'};
    }
    try {
      await _run('flatpak', [
        'remote-add',
        '--system',
        '--if-not-exists',
        _flathubRemote,
        _flathubRepoUrl,
      ]);
      _log('ensureFlathub: added');
      return {'status': 'added', 'message': 'added from $_flathubRepoUrl'};
    } catch (e) {
      _log('ensureFlathub: FAILED $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// Add PensHub, then verify it. If the verify step fails specifically
  /// with a GPG / signature error, delete the remote so later flatpak
  /// operations don't get blocked by the broken entry.
  static Future<Map<String, dynamic>> _ensurePenshub() async {
    _log('ensurePenshub: begin');
    final remotes = await _listRemotes();
    final alreadyHad = remotes != null && remotes.contains(_penshubRemote);

    if (!alreadyHad) {
      // Add with best-effort GPG. We try wget, then curl, then as a last
      // resort add without GPG — better than nothing until the user's
      // signing service is repaired.
      bool haveKey = false;
      try {
        await _run('wget', ['-q', '-O', _gpgTmpPath, _penshubGpgUrl]);
        haveKey = true;
      } catch (_) {
        try {
          await _run('curl', ['-sfL', '-o', _gpgTmpPath, _penshubGpgUrl]);
          haveKey = true;
        } catch (_) {
          _log('ensurePenshub: GPG key fetch failed (wget+curl) — '
              'adding without verification');
        }
      }
      try {
        await _run('flatpak', [
          'remote-add',
          '--system',
          '--if-not-exists',
          if (haveKey) '--gpg-import=$_gpgTmpPath' else '--no-gpg-verify',
          _penshubRemote,
          _penshubUrl,
        ]);
        _log('ensurePenshub: added (gpgVerified=$haveKey)');
      } catch (e) {
        _log('ensurePenshub: remote-add FAILED $e');
        return {'status': 'error', 'message': e.toString()};
      }
    } else {
      _log('ensurePenshub: already present');
    }

    // Verify by doing an appstream refresh. This does a signed summary
    // pull — so a broken GPG chain will throw with a clear error.
    final v = await _verifyRemote(_penshubRemote);
    if (v.ok) {
      _log('ensurePenshub: verified OK');
      return {
        'status': alreadyHad ? 'ok' : 'added',
        'message': 'verified',
      };
    }

    final stderrLow = v.stderr.toLowerCase();
    final isGpgError = stderrLow.contains('gpg') ||
        stderrLow.contains('signature') ||
        stderrLow.contains('no valid public key') ||
        stderrLow.contains('invalid signature') ||
        stderrLow.contains('key id');

    _log('ensurePenshub: verification FAILED isGpgError=$isGpgError '
        'stderr="${v.stderr}"');

    if (!isGpgError) {
      // Non-GPG failure (network, service down) — leave the remote in
      // place; a future retry may succeed once the backend recovers.
      return {'status': 'error', 'message': v.stderr};
    }

    // Broken GPG chain — remove the remote so every subsequent install
    // doesn't fail with the same GPG error. User can re-add via the app
    // on the next boot once the signing service is fixed.
    try {
      await _run('flatpak', [
        'remote-delete',
        '--system',
        '--force',
        _penshubRemote,
      ]);
      _log('ensurePenshub: removed broken remote after GPG failure');
      return {
        'status': 'removed',
        'message': 'GPG verification failed, remote deleted: ${v.stderr}',
      };
    } catch (delErr) {
      _log('ensurePenshub: remote-delete FAILED $delErr');
      return {
        'status': 'error',
        'message': 'GPG failed and delete failed: $delErr',
      };
    }
  }

  /// Probes a remote by doing a signed appstream refresh. Returns the
  /// exit status and stderr so callers can distinguish GPG errors from
  /// transient network failures.
  static Future<({bool ok, String stderr})> _verifyRemote(
      String remote) async {
    final args = ['update', '--system', '--appstream', '-y', remote];
    ProcessResult r;
    try {
      r = await Process.run('flatpak', args);
    } on ProcessException {
      final abs = await _resolveAbsolute('flatpak');
      if (abs == null) return (ok: false, stderr: 'flatpak binary not found');
      r = await Process.run(abs, args);
    }
    return (ok: r.exitCode == 0, stderr: r.stderr.toString().trim());
  }

  // ── Install ─────────────────────────────────────────────────
  static Future<void> install(String appId, {String? remote}) async {
    _log('install() called appId=$appId remote=${remote ?? '(default)'} '
        'useFallback=$_useProcessFallback');
    if (!_useProcessFallback) {
      try {
        await _channel.invokeMethod('installFlatpak', {
          'appId': appId,
          if (remote != null) 'remote': remote,
        });
        _log('install() native plugin path succeeded appId=$appId');
        return;
      } on MissingPluginException {
        _log('install() native plugin missing — switching to dart fallback');
        _useProcessFallback = true;
      } on PlatformException catch (e) {
        _log('install() native plugin error appId=$appId code=${e.code} '
            'msg=${e.message}; falling back to dart:io');
      }
    }
    final r = remote ?? _penshubRemote;
    _log('install() dart fallback appId=$appId remote=$r');
    try {
      // -y auto-confirms; --noninteractive is dropped so flatpak will
      // emit phase keywords on stdout/stderr that _streamFlatpakOp
      // uses to flip from 'downloading' to 'installing'.
      await _streamFlatpakOp(
        appId: appId,
        args: ['install', '--system', '-y', r, appId],
        initialPhase: 'downloading',
      );
      _emitDone(appId, ok: true);
    } catch (e) {
      _log('install() FAILED appId=$appId error=$e');
      _emitDone(appId, ok: false);
      rethrow;
    }
  }

  // ── Launch ──────────────────────────────────────────────────
  static Future<void> launch(String appId) async {
    _log('launch() appId=$appId useFallback=$_useProcessFallback');
    if (!_useProcessFallback) {
      try {
        await _channel.invokeMethod('launchFlatpak', {'appId': appId});
        _log('launch() native plugin path ok');
        return;
      } on MissingPluginException {
        _log('launch() native plugin missing — falling back to dart:io');
        _useProcessFallback = true;
      } on PlatformException catch (e) {
        _log('launch() native plugin error code=${e.code} msg=${e.message}; '
            'falling back to dart:io');
      }
    }

    // Build an explicit env so the child flatpak process always gets
    // the compositor socket, even if our parent env drifted (detached
    // systemd context, SSH session, etc.). This is the "use the socket
    // running from the Flutter app" fallback — we detect flutter-auto's
    // Wayland display and pass it through. If XWayland is present (once
    // it lands in meta-agl-flutter), DISPLAY is picked up automatically.
    final env = await _computeLaunchEnv();
    _log('launch() env WAYLAND_DISPLAY=${env['WAYLAND_DISPLAY'] ?? '(unset)'} '
        'XDG_RUNTIME_DIR=${env['XDG_RUNTIME_DIR'] ?? '(unset)'} '
        'DISPLAY=${env['DISPLAY'] ?? '(unset)'}');

    Process proc;
    try {
      proc = await Process.start(
        'flatpak',
        ['run', appId],
        mode: ProcessStartMode.detachedWithStdio,
        environment: env,
        includeParentEnvironment: true,
      );
    } on ProcessException catch (e) {
      _log('launch() PATH lookup failed for flatpak ($e); trying absolute');
      final abs = await _resolveAbsolute('flatpak');
      if (abs == null) {
        _log('launch() FATAL flatpak binary not found anywhere');
        throw Exception('flatpak: not found');
      }
      proc = await Process.start(
        abs,
        ['run', appId],
        mode: ProcessStartMode.detachedWithStdio,
        environment: env,
        includeParentEnvironment: true,
      );
    }

    _log('launch() spawned pid=${proc.pid} appId=$appId');
    // Capture the first ~30 s of stderr so failures (missing GTK, bad
    // DISPLAY, refused wayland socket) land in the journal instead of
    // vanishing into the detached child. We cancel after the window to
    // avoid holding a listener on a long-running GUI app forever.
    final stderrSub = proc.stderr
        .transform(systemEncoding.decoder)
        .listen((chunk) {
      for (final line in chunk.split(RegExp(r'[\r\n]'))) {
        final t = line.trim();
        if (t.isEmpty) continue;
        _log('launch() stderr appId=$appId | $t');
      }
    });
    Timer(const Duration(seconds: 30), () => stderrSub.cancel());
  }

  /// Builds a Wayland/X11-aware env map for launching flatpak apps.
  /// Preference order for each key: already-set env → auto-detected → omit.
  static Future<Map<String, String>> _computeLaunchEnv() async {
    final env = <String, String>{};

    // XDG_RUNTIME_DIR — prefer existing, else infer from uid.
    var xdg = Platform.environment['XDG_RUNTIME_DIR'];
    if (xdg == null || xdg.isEmpty) {
      try {
        final r = await Process.run('id', ['-u']);
        final uid = r.stdout.toString().trim();
        if (uid.isNotEmpty) {
          final candidate = '/run/user/$uid';
          if (await Directory(candidate).exists()) {
            xdg = candidate;
          }
        }
      } catch (_) {
        // ignored — we just won't set XDG_RUNTIME_DIR
      }
    }
    if (xdg != null && xdg.isNotEmpty) env['XDG_RUNTIME_DIR'] = xdg;

    // WAYLAND_DISPLAY — prefer existing, else scan sockets in XDG_RUNTIME_DIR.
    var wayland = Platform.environment['WAYLAND_DISPLAY'];
    if ((wayland == null || wayland.isEmpty) && xdg != null) {
      try {
        final dir = Directory(xdg);
        if (await dir.exists()) {
          await for (final e in dir.list(followLinks: false)) {
            final name = e.path.split('/').last;
            // Pick the first `wayland-N` socket (skip `.lock` companions).
            if (name.startsWith('wayland-') && !name.endsWith('.lock')) {
              wayland = name;
              break;
            }
          }
        }
      } catch (_) {
        // ignored
      }
    }
    if (wayland != null && wayland.isNotEmpty) env['WAYLAND_DISPLAY'] = wayland;

    // DISPLAY — only inherit if set. Once XWayland is added to meta-agl-
    // flutter, this will auto-pick up and let X11-only apps work too.
    final display = Platform.environment['DISPLAY'];
    if (display != null && display.isNotEmpty) env['DISPLAY'] = display;

    // DBUS_SESSION_BUS_ADDRESS — helpful for GTK apps talking to portals.
    final dbus = Platform.environment['DBUS_SESSION_BUS_ADDRESS'];
    if (dbus != null && dbus.isNotEmpty) {
      env['DBUS_SESSION_BUS_ADDRESS'] = dbus;
    }

    return env;
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
      await _streamFlatpakOp(
        appId: appId,
        args: ['update', '--system', '-y', appId],
        initialPhase: 'downloading',
      );
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
