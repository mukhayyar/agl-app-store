import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';       // penting
import 'package:sembast/sembast_io.dart';
import '../models/flatpak_package.dart';

class FlatpakCache {
  static final FlatpakCache _i = FlatpakCache._();
  FlatpakCache._();
  factory FlatpakCache() => _i;

  late Database _db;
  final _store = stringMapStoreFactory.store('apps');
  final _meta  = stringMapStoreFactory.store('meta');

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    _db = await databaseFactoryIo.openDatabase(p.join(dir.path, 'flathub_cache.db'));
  }

  Future<void> upsertAll(
  List<FlatpakPackage> apps, {
  String? etag,
  String? lastModified,
}) async {
  await _db.transaction((txn) async {
    for (final a in apps) {
      await _store.record(a.id).put(txn, a.toMap());
    }
    if (etag != null || lastModified != null) {
      await _meta.record('http_cache').put(txn, {
        'etag': etag,
        'last_modified': lastModified,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  });
}


  Future<String?> getEtag() async {
    final m = await _meta.record('http_cache').get(_db);
    return m?['etag'] as String?;
  }

  Future<String?> getLastModified() async {
    final m = await _meta.record('http_cache').get(_db);
    return m?['last_modified'] as String?;
  }

  Future<int> count({String? query}) async {
    // Gunakan Filter (bukan Finder) untuk count
    Filter? filter;
    if (query != null && query.isNotEmpty) {
      final re = RegExp(RegExp.escape(query), caseSensitive: false);
      filter = Filter.or([
        Filter.matchesRegExp('name', re),
        Filter.matchesRegExp('id', re),
      ]);
    }
    return _store.count(_db, filter: filter); // <-- pakai filter:
  }

  /// Custom pagination (pakai Finder untuk find)
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
      ]);
    }

    final finder = Finder(
      filter: filter,
      sortOrders: [SortOrder('name', true)],
      offset: offset,
      limit: limit,
    );

    final records = await _store.find(_db, finder: finder); // <-- finder di find OK
    return records.map((r) => FlatpakPackage.fromMap(r.value)).toList();
  }

  Future<FlatpakPackage?> getById(String id) async {
    final m = await _store.record(id).get(_db);
    return m == null ? null : FlatpakPackage.fromMap(m);
  }
}
