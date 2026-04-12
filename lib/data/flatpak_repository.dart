import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_source.dart';
import '../models/flatpak_package.dart';
import 'flatpak_cache.dart';
import '../platform/flatpak_platform.dart';

/// Page size used for the initial sync of catalog endpoints.
const _refreshPageSize = 100;

class FlatpakRepository {
  final FlatpakCache _cache = FlatpakCache();

  /// Currently active catalog source. Defaults to PensHub (the AGL Store).
  /// Switch via [setSource]; never mutate directly.
  AppSource _source = AppSource.pensHub;
  AppSource get currentSource => _source;

  Future<void> init() => _cache.init();

  /// Switch the active catalog. Wipes the local cache so PensHub and Flathub
  /// data never bleed into each other (they may publish the same flatpak id
  /// with different metadata).
  Future<void> setSource(AppSource source) async {
    if (_source == source) return;
    _source = source;
    await _cache.clear();
  }

  // Pre-compiled static RegExp — avoid re-creation per call
  static final _partRe = RegExp(r'^[A-Za-z0-9_]+$');
  static final _lastPartRe = RegExp(r'^[A-Za-z0-9_-]+$');

  // -----------------------------
  // Helpers
  // -----------------------------
  static bool _looksLikeFlatpakId(String id) {
    if (!id.contains('.')) return false;
    final parts = id.split('.');
    for (int i = 0; i < parts.length; i++) {
      final isLast = i == parts.length - 1;
      if (!(isLast ? _lastPartRe : _partRe).hasMatch(parts[i])) return false;
    }
    return true;
  }

  static String normalizeFlatpakId(String raw) {
    if (raw.isEmpty) return raw;

    // If it already looks valid, return as-is
    if (_looksLikeFlatpakId(raw)) return raw;

    // 🔥 HACK: convert underscores to dots
    final normalized = raw.replaceAll('_', '.');

    // If the normalized version is valid, use it
    if (_looksLikeFlatpakId(normalized)) {
      debugPrint('Flatpak ID normalized: "$raw" → "$normalized"');
      return normalized;
    }

    // Last resort: return original (will be rejected later)
    return raw;
  }

  /// Extracts a list of app objects from a PensHub response.
  ///
  /// PensHub usually returns a bare JSON array, but the parser also tolerates
  /// `{ "apps": [...] }` / `{ "data": [...] }` / `{ "hits": [...] }` wrappers
  /// in case the API ever changes shape.
  static List<Map<String, dynamic>> _extractItems(dynamic decoded) {
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    if (decoded is Map<String, dynamic>) {
      for (final key in const ['apps', 'data', 'hits', 'results']) {
        final v = decoded[key];
        if (v is List) {
          return v.whereType<Map<String, dynamic>>().toList();
        }
      }
    }
    return const [];
  }

  // -----------------------------
  // Parsing (Isolate-safe)
  // -----------------------------

  /// PensHub `/apps` returns full objects in [_extractItems]-friendly form.
  static List<FlatpakPackage> _parsePensHubList(String body) {
    final decoded = json.decode(body);
    return _extractItems(decoded)
        .map(FlatpakPackage.fromPensHubJson)
        .where((p) => p.flatpakId.isNotEmpty)
        .toList();
  }

  static FlatpakPackage? _parsePensHubSingle(String body) {
    final decoded = json.decode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final pkg = FlatpakPackage.fromPensHubJson(decoded);
    return pkg.flatpakId.isNotEmpty ? pkg : null;
  }

  /// Flathub `/appstream?filter=apps` returns a JSON array of flatpak ids.
  /// We hydrate them into stub packages and let [enrichMissingDetails] fetch
  /// the rest one at a time from `/appstream/{id}`.
  static List<FlatpakPackage> _parseFlathubIdList(String body) {
    final decoded = json.decode(body);
    if (decoded is! List) return [];
    return decoded
        .whereType<String>()
        .map((id) => FlatpakPackage(id: id, flatpakId: id, name: id))
        .toList();
  }

  /// Flathub `/collection/category/{name}` returns either a `{hits: [...] }`
  /// envelope or a bare list of AppStream-shaped objects.
  static List<FlatpakPackage> _parseFlathubCategory(String body) {
    final decoded = json.decode(body);
    return _extractItems(decoded)
        .map(FlatpakPackage.fromAppstream)
        .where((p) => p.flatpakId.isNotEmpty)
        .toList();
  }

  static FlatpakPackage? _parseFlathubSingle(String body) {
    final decoded = json.decode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final pkg = FlatpakPackage.fromAppstream(decoded);
    return pkg.flatpakId.isNotEmpty ? pkg : null;
  }

  // -----------------------------
  // Sync / Refresh
  // -----------------------------
  /// Pulls the catalog list for the active source.
  ///
  /// PensHub returns rich objects directly. Flathub's `/appstream` returns
  /// just a list of ids; details get hydrated later by [enrichMissingDetails].
  Future<void> refreshAllApps() async {
    try {
      final base = _source.apiBaseUrl;

      if (_source == AppSource.pensHub) {
        final uri = Uri.parse('$base/apps').replace(
          queryParameters: {
            'limit': '$_refreshPageSize',
            'offset': '0',
          },
        );
        final resp = await http.get(uri, headers: const {
          'Accept': 'application/json',
        });
        if (resp.statusCode == 200) {
          final apps = await compute(_parsePensHubList, resp.body);
          await _cache.upsertAll(apps);
        } else {
          debugPrint('PensHub /apps failed: ${resp.statusCode}');
        }
        return;
      }

      // Flathub
      final uri = Uri.parse('$base/appstream?filter=apps');
      final resp = await http.get(uri, headers: const {
        'Accept': 'application/json',
      });
      if (resp.statusCode == 200) {
        final apps = await compute(_parseFlathubIdList, resp.body);
        await _cache.upsertAll(apps);
      } else {
        debugPrint('Flathub /appstream failed: ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('Background refresh failed: $e');
    }
  }

  // -----------------------------
  // Details
  // -----------------------------
  /// Fetches a single app's full metadata.
  ///
  /// When [forceRefresh] is false (default), a cached entry that already has
  /// a summary is returned without hitting the network. The detail page sets
  /// [forceRefresh] to true so it always shows up-to-date description,
  /// screenshots and metadata even if the cache is stale or partial.
  Future<FlatpakPackage?> fetchDetailsByFlatpakId(
    String flatpakId, {
    bool forceRefresh = false,
  }) async {
    if (!_looksLikeFlatpakId(flatpakId)) return null;

    if (!forceRefresh) {
      final cached = await _cache.getByFlatpakId(flatpakId);
      if (cached != null && (cached.summary?.isNotEmpty ?? false)) {
        return cached;
      }
    }

    final base = _source.apiBaseUrl;
    final uri = _source == AppSource.pensHub
        ? Uri.parse('$base/apps/$flatpakId')
        : Uri.parse('$base/appstream/$flatpakId');

    try {
      final resp = await http.get(uri, headers: const {
        'Accept': 'application/json',
      });
      if (resp.statusCode == 200) {
        final pkg = _source == AppSource.pensHub
            ? await compute(_parsePensHubSingle, resp.body)
            : await compute(_parseFlathubSingle, resp.body);
        if (pkg != null) {
          await _cache.upsertAll([pkg]);
          return pkg;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> enrichMissingDetails(
    List<FlatpakPackage> items, {
    int maxConcurrent = 8,
  }) async {
    final ids = items
        .where(
          (p) =>
              p.flatpakId.isNotEmpty &&
              ((p.summary == null || p.summary!.isEmpty) ||
                  (p.description == null || p.description!.isEmpty)),
        )
        .map((p) => p.flatpakId)
        .toList();

    if (ids.isEmpty) return;

    final sem = _Semaphore(maxConcurrent);
    final futures = <Future>[];

    for (final id in ids) {
      await sem.acquire();
      futures.add(fetchDetailsByFlatpakId(id).whenComplete(sem.release));
    }
    await Future.wait(futures);
  }

  // -----------------------------
  // Pagination (Local DB)
  // -----------------------------
  Future<List<FlatpakPackage>> getPage({
    required int page,
    required int pageSize,
    String? query,
  }) {
    final offset = (page - 1) * pageSize;
    return _cache.page(offset: offset, limit: pageSize, query: query);
  }

  Future<int> totalCount({String? query}) => _cache.count(query: query);

  // -----------------------------
  // Installed Apps
  // -----------------------------
  Future<Set<String>> installedIds() async {
    final apps = await FlatpakPlatform.listInstalled();
    return apps
        .map((a) => normalizeFlatpakId(a['id']!))
        .toSet(); // MUST be flatpak ID
  }

  Future<List<FlatpakPackage>> getInstalledAppsRobust() async {
    final local = await FlatpakPlatform.listInstalled();
    final result = <FlatpakPackage>[];

    for (final item in local) {
      final flatpakId = item['id']!;
      final name = item['name']!;

      final cached = await _cache.getByFlatpakId(flatpakId);
      if (cached != null) {
        result.add(cached);
      } else {
        result.add(
          FlatpakPackage(
            id: flatpakId,
            flatpakId: flatpakId,
            name: name.isNotEmpty ? name : flatpakId,
            summary: 'Installed Application',
          ),
        );
      }
    }
    return result;
  }

  Stream<List<FlatpakPackage>> fetchByCategory(String categoryName) async* {
    final base = _source.apiBaseUrl;
    final uri = _source == AppSource.pensHub
        ? Uri.parse('$base/apps').replace(queryParameters: {
            'category': categoryName,
            'limit': '$_refreshPageSize',
          })
        : Uri.parse('$base/collection/category/$categoryName');

    try {
      final resp = await http.get(uri, headers: const {
        'Accept': 'application/json',
      });
      if (resp.statusCode != 200) {
        debugPrint('Category fetch failed [$categoryName]: ${resp.statusCode}');
        return;
      }

      final apps = _source == AppSource.pensHub
          ? await compute(_parsePensHubList, resp.body)
          : await compute(_parseFlathubCategory, resp.body);

      if (apps.isEmpty) {
        yield const [];
        return;
      }

      await _cache.upsertAll(apps);
      yield apps;
    } catch (e) {
      debugPrint('Exception fetching category $categoryName: $e');
    }
  }

  // -----------------------------
  // Flatpak Actions (STRICT)
  // -----------------------------
  Future<void> fixCorruptedIds() async {
    final all = await _cache.page(offset: 0, limit: 100000, query: null);

    final fixedApps = <FlatpakPackage>[];

    for (final p in all) {
      final fixed = normalizeFlatpakId(p.flatpakId);

      if (fixed != p.flatpakId && _looksLikeFlatpakId(fixed)) {
        fixedApps.add(
          FlatpakPackage(
            id: fixed,
            flatpakId: fixed,
            name: p.name,
            icon: p.icon,
            summary: p.summary,
            description: p.description,
            developerName: p.developerName,
            version: p.version,
            license: p.license,
            downloadSize: p.downloadSize,
            screenshots: p.screenshots,
            homepage: p.homepage,
            bugtracker: p.bugtracker,
            categories: p.categories,
          ),
        );
      }
    }

    if (fixedApps.isNotEmpty) {
      debugPrint('Fixing ${fixedApps.length} corrupted Flatpak IDs');
      await _cache.upsertAll(fixedApps);
    }
  }

  Future<bool> isInstalled(String flatpakId) {
    final fixed = normalizeFlatpakId(flatpakId);
    if (!_looksLikeFlatpakId(fixed)) return Future.value(false);
    return FlatpakPlatform.isInstalled(fixed);
  }

  Future<void> install(String flatpakId) {
    final fixed = normalizeFlatpakId(flatpakId);

    if (!_looksLikeFlatpakId(fixed)) {
      debugPrint('Install blocked: invalid flatpakId "$flatpakId"');
      return Future.value(); // ⛔ NO CRASH
    }

    return FlatpakPlatform.install(fixed, remote: _source.flatpakRemote);
  }

  Future<void> uninstall(String flatpakId) {
    final fixed = normalizeFlatpakId(flatpakId);
    if (!_looksLikeFlatpakId(fixed)) return Future.value();
    return FlatpakPlatform.uninstall(fixed);
  }

  Future<void> update(String flatpakId) {
    final fixed = normalizeFlatpakId(flatpakId);
    if (!_looksLikeFlatpakId(fixed)) return Future.value();
    return FlatpakPlatform.update(fixed);
  }
}

// -----------------------------
// Simple Semaphore
// -----------------------------
class _Semaphore {
  int _available;
  final _queue = <Completer<void>>[];

  _Semaphore(this._available);

  Future<void> acquire() {
    if (_available > 0) {
      _available--;
      return Future.value();
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _available++;
    }
  }
}
