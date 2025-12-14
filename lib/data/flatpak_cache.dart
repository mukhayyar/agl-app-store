import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

import '../models/flatpak_package.dart';

class FlatpakCache {
  static final FlatpakCache _i = FlatpakCache._();
  FlatpakCache._();
  factory FlatpakCache() => _i;

  late Database _db;
  final _store = stringMapStoreFactory.store('apps');

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

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    _db = await databaseFactoryIo.openDatabase(
      p.join(dir.path, 'flathub_cache.db'),
    );
  }

  // -----------------------------
  // Write
  // -----------------------------
  Future<void> upsertAll(List<FlatpakPackage> apps) async {
    await _db.transaction((txn) async {
      for (final a in apps) {
        if (a.flatpakId.isEmpty) continue;
        final fixed = normalizeFlatpakId(a.flatpakId);
        await _store.record(fixed).put(txn, a.toMap());
      }
    });
  }

  // -----------------------------
  // Read
  // -----------------------------
  Future<FlatpakPackage?> getByFlatpakId(String flatpakId) async {
    final record = await _store.record(flatpakId).get(_db);
    if (record == null) return null;
    return FlatpakPackage.fromMap(record);
  }

  Future<int> count({String? query}) async {
    Filter? filter;
    if (query != null && query.isNotEmpty) {
      final re = RegExp(RegExp.escape(query), caseSensitive: false);
      filter = Filter.or([
        Filter.matchesRegExp('name', re),
        Filter.matchesRegExp('id', re),
        Filter.matchesRegExp('flatpak_id', re),
      ]);
    }
    return _store.count(_db, filter: filter);
  }

  Future<List<FlatpakPackage>> page({
    required int offset,
    required int limit,
    String? query,
  }) async {
    Filter? filter;
    if (query != null && query.isNotEmpty) {
      final re = RegExp(RegExp.escape(query), caseSensitive: false);
      filter = Filter.or([
        Filter.matchesRegExp('name', re),
        Filter.matchesRegExp('id', re),
        Filter.matchesRegExp('flatpak_id', re),
      ]);
    }

    final finder = Finder(
      filter: filter,
      sortOrders: [SortOrder('name')],
      offset: offset,
      limit: limit,
    );

    final records = await _store.find(_db, finder: finder);
    return records.map((r) => FlatpakPackage.fromMap(r.value)).toList();
  }
}
