import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/flatpak_package.dart';
import 'flatpak_cache.dart';
import '../platform/flatpak_platform.dart';

const _baseUrl = 'https://flathub.org/api/v2';

class FlatpakRepository {
  final FlatpakCache _cache = FlatpakCache();

  Future<void> init() => _cache.init();

  // -----------------------------
  // Helpers
  // -----------------------------
  static bool _looksLikeFlatpakId(String id) {
    if (!id.contains('.')) return false;
    final parts = id.split('.');
    for (int i = 0; i < parts.length; i++) {
      final isLast = i == parts.length - 1;
      final re = RegExp(isLast ? r'^[A-Za-z0-9_-]+$' : r'^[A-Za-z0-9_]+$');
      if (!re.hasMatch(parts[i])) return false;
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

  static List<FlatpakPackage> _parseCategoryResponseSafe(String body) {
    final decoded = json.decode(body);

    List<dynamic> hits = [];
    if (decoded is Map<String, dynamic> && decoded.containsKey('hits')) {
      hits = decoded['hits'];
    } else if (decoded is List) {
      hits = decoded;
    }

    return hits
        .whereType<Map<String, dynamic>>()
        .map(FlatpakPackage.fromAppstream)
        // 🔒 CRITICAL: drop invalid entries
        .where((p) => p.flatpakId.isNotEmpty)
        .toList();
  }

  // -----------------------------
  // Parsing (Isolate-safe)
  // -----------------------------
  static List<FlatpakPackage> _parseAppList(String body) {
    final decoded = json.decode(body);
    if (decoded is! List) return [];

    // Case 1: List<String> → flatpak IDs only
    if (decoded.isNotEmpty && decoded.first is String) {
      return decoded.cast<String>().map((id) {
        return FlatpakPackage(
          id: id, // internal id
          flatpakId: id, // canonical flatpak id
          name: id, // temporary, will be enriched later
        );
      }).toList();
    }

    // Case 2: Full AppStream objects
    if (decoded.first is Map<String, dynamic>) {
      return decoded
          .cast<Map<String, dynamic>>()
          .map(FlatpakPackage.fromAppstream)
          .where((p) => p.flatpakId.isNotEmpty)
          .toList();
    }

    return [];
  }

  static FlatpakPackage? _parseSingleApp(String body) {
    final decoded = json.decode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final pkg = FlatpakPackage.fromAppstream(decoded);
    return pkg.flatpakId.isNotEmpty ? pkg : null;
  }

  // -----------------------------
  // Sync / Refresh
  // -----------------------------
  Future<void> refreshAllApps() async {
    try {
      final uri = Uri.parse('$_baseUrl/appstream?filter=apps');
      final resp = await http.get(uri);

      if (resp.statusCode == 200) {
        final apps = await compute(_parseAppList, resp.body);
        await _cache.upsertAll(apps);
      }
    } catch (e) {
      debugPrint('Background refresh failed: $e');
    }
  }

  // -----------------------------
  // Details
  // -----------------------------
  Future<FlatpakPackage?> fetchDetailsByFlatpakId(String flatpakId) async {
    if (!_looksLikeFlatpakId(flatpakId)) return null;

    final cached = await _cache.getByFlatpakId(flatpakId);
    if (cached != null) return cached;

    try {
      final uri = Uri.parse('$_baseUrl/appstream/$flatpakId');
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final pkg = await compute(_parseSingleApp, resp.body);
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
    // 0. Emit cached data first (if any)
    final cached = await _cache.page(offset: 0, limit: 200, query: null);

    final cachedFiltered = cached.where((p) => p.flatpakId.isNotEmpty).toList();

    if (cachedFiltered.isNotEmpty) {
      yield cachedFiltered;
    }

    // 1. Fetch from network
    final uri = Uri.parse('$_baseUrl/collection/category/$categoryName');

    try {
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        debugPrint('Category fetch failed [$categoryName]: ${resp.statusCode}');
        return;
      }

      // 2. Parse in isolate
      final apps = await compute(_parseCategoryResponseSafe, resp.body);

      if (apps.isEmpty) return;

      // 3. Save to DB (keyed by flatpakId)
      await _cache.upsertAll(apps);

      // 4. Emit fresh data
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

    return FlatpakPlatform.install(fixed);
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
