import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/flatpak_package.dart';
import 'flatpak_cache.dart';
import '../platform/flatpak_platform.dart';
import 'dart:async';

const _baseUrl = 'https://flathub.org/api/v2';

class FlatpakRepository {
  final FlatpakCache _cache = FlatpakCache();

  Future<void> init() => _cache.init();

  Future<void> refreshAllApps() async {
    final uri = Uri.parse('$_baseUrl/appstream?filter=apps');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }

    final decoded = json.decode(resp.body);
    if (decoded is! List || decoded.isEmpty) return;

    // Bisa berisi List<Map> (lengkap) atau List<String> (hanya id)
    if (decoded.first is Map<String, dynamic>) {
      final apps = decoded
          .cast<Map<String, dynamic>>()
          .map((m) => FlatpakPackage.fromAppstream(m))
          .toList();
      await _cache.upsertAll(apps);
    } else if (decoded.first is String) {
      final ids = decoded.cast<String>();
      final apps = ids
          .map((id) => FlatpakPackage(id: id, name: id))
          .toList();
      await _cache.upsertAll(apps);
    } else {
      throw Exception('Format tidak didukung dari Flathub.');
    }
  }

  /// Ambil detail lengkap untuk 1 app dan update cache.
  Future<FlatpakPackage?> fetchDetails(String appId) async {
    final uri = Uri.parse('$_baseUrl/appstream/$appId');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return null;

    final data = json.decode(resp.body);
    if (data is! Map<String, dynamic>) return null;

    final full = FlatpakPackage.fromAppstream(data);
    await _cache.upsertAll([full]); // update 1 record
    return full;
  }

  /// Enrich untuk item yang belum punya summary/description (concurrency dibatasi).
  Future<void> enrichMissingDetails(List<FlatpakPackage> items,
      {int maxConcurrent = 8}) async {
    final toFetch = items
        .where((p) => (p.summary == null || p.summary!.isEmpty) ||
                      (p.description == null || p.description!.isEmpty))
        .map((p) => p.id)
        .toList();
    if (toFetch.isEmpty) return;

    final sem = _Semaphore(maxConcurrent);
    final futures = <Future>[];

    for (final id in toFetch) {
      await sem.acquire();
      futures.add(fetchDetails(id).whenComplete(() => sem.release()));
    }
    await Future.wait(futures);
  }

  Future<List<FlatpakPackage>> getPage({
    required int page,
    required int pageSize,
    String? query,
  }) {
    final offset = (page - 1) * pageSize;
    return _cache.page(offset: offset, limit: pageSize, query: query);
  }

  Future<int> totalCount({String? query}) => _cache.count(query: query);

  Future<Set<String>> installedIds() async {
    final ids = await FlatpakPlatform.listInstalled();
    return ids.toSet();
  }

  Future<bool> isInstalled(String appId) => FlatpakPlatform.isInstalled(appId);
  Future<void> install(String appId)     => FlatpakPlatform.install(appId);
  Future<void> uninstall(String appId)   => FlatpakPlatform.uninstall(appId);
  Future<void> update(String appId)      => FlatpakPlatform.update(appId);
}

/// Simple semaphore untuk membatasi concurrency
class _Semaphore {
  int _available;
  final _q = <Completer<void>>[];
  _Semaphore(this._available);

  Future<void> acquire() {
    if (_available > 0) {
      _available--;
      return Future.value();
    }
    final c = Completer<void>();
    _q.add(c);
    return c.future;
  }

  void release() {
    if (_q.isNotEmpty) {
      _q.removeAt(0).complete();
    } else {
      _available++;
    }
  }
}
