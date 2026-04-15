class FlatpakPackage {
  final String id; // internal / slug
  final String flatpakId; // canonical Flatpak App ID

  final String name;
  final String? icon;
  final String? summary;
  final String? description;
  final String? developerName;
  final String? version;
  final String? license;
  final String? downloadSize;

  final List<String> screenshots; // urls
  final String? homepage;
  final String? bugtracker;
  final List<String> categories;

  /// PensHub-only: app has been verified by PensHub. False / null on Flathub.
  final bool isVerified;

  /// PensHub-only: ISO timestamp after which the app should be considered
  /// expired (e.g. signing key rotation deadline). Null when not applicable.
  final DateTime? expiresAt;

  const FlatpakPackage({
    required this.id,
    required this.flatpakId,
    required this.name,
    this.icon,
    this.summary,
    this.description,
    this.developerName,
    this.version,
    this.license,
    this.downloadSize,
    this.screenshots = const [],
    this.homepage,
    this.bugtracker,
    this.categories = const [],
    this.isVerified = false,
    this.expiresAt,
  });

  // Pre-compiled RegExp — avoid re-creation per call
  static final _partRe = RegExp(r'^[A-Za-z0-9_]+$');
  static final _lastPartRe = RegExp(r'^[A-Za-z0-9_-]+$');

  // --------------------------------------------------
  // FROM APPSTREAM / FLATHUB API
  // --------------------------------------------------
  /// Maps a Flathub `/api/v2/appstream/{id}` JSON object to a [FlatpakPackage].
  ///
  /// Flathub returns AppStream-shaped data with a few quirks:
  ///   * `description` is HTML (`<p>…</p>`) — we strip tags so the UI shows
  ///     plain readable text.
  ///   * `version` is not at the top level; it lives in `releases[0].version`.
  ///   * `screenshots` is a list of objects, each with a `sizes[]` array of
  ///     differently-scaled URLs. We pick a sensible mid-size per screenshot.
  ///   * Homepage and bugtracker live under `urls.{homepage,bugtracker}`.
  ///   * License is `project_license`, not `license`.
  factory FlatpakPackage.fromAppstream(Map<String, dynamic> json) {
    String asStringOrFirst(dynamic v) {
      if (v == null) return '';
      if (v is String) return v;
      if (v is Map && v.isNotEmpty) {
        final first = v.values.first;
        if (first is String) return first;
      }
      return v.toString();
    }

    String flatpakId = '';
    if (json['id'] is String && _looksLikeFlatpakId(json['id'])) {
      flatpakId = json['id'];
    } else if (json['bundle']?['flatpak']?['id'] is String) {
      flatpakId = json['bundle']['flatpak']['id'];
    }

    final internalId =
        json['slug']?.toString() ?? json['id']?.toString() ?? flatpakId;

    // Description: AppStream returns HTML — strip tags to plain text.
    final descRaw = asStringOrFirst(json['description']);
    final description = _stripHtml(descRaw);

    // Version: prefer top-level, fall back to releases[0].
    String? version = json['version']?.toString();
    if (version == null || version.isEmpty) {
      final releases = json['releases'];
      if (releases is List && releases.isNotEmpty) {
        final first = releases.first;
        if (first is Map) {
          version = first['version']?.toString();
        }
      }
    }

    // License: Flathub uses `project_license`; some older payloads use `license`.
    final license =
        json['project_license']?.toString() ?? json['license']?.toString();

    // URLs map: { homepage, bugtracker, ... }
    String? homepage;
    String? bugtracker;
    final urls = json['urls'];
    if (urls is Map) {
      homepage = urls['homepage']?.toString();
      bugtracker = urls['bugtracker']?.toString();
    }
    homepage ??= json['homepage']?.toString();

    // Screenshots: pick one URL per screenshot from its `sizes` array.
    final screenshots = _extractAppstreamScreenshots(json['screenshots']);

    // Categories: list of strings
    final categories = _readStringList(json['categories']);

    return FlatpakPackage(
      id: internalId,
      flatpakId: flatpakId,
      name: asStringOrFirst(json['name']),
      icon: json['icon']?.toString(),
      summary: asStringOrFirst(json['summary']),
      description: description.isEmpty ? null : description,
      developerName: json['developer_name']?.toString(),
      version: version,
      license: license,
      downloadSize: json['download_size']?.toString(),
      screenshots: screenshots,
      homepage: homepage,
      bugtracker: bugtracker,
      categories: categories,
    );
  }

  // --------------------------------------------------
  // FROM PENSHUB API (https://api.agl-store.cyou)
  // --------------------------------------------------
  /// Maps a PensHub `/apps` or `/apps/{id}` JSON object to a [FlatpakPackage].
  ///
  /// PensHub returns the flatpak app id directly under `id` (e.g.
  /// `com.pens.MorseCode`), so [id] and [flatpakId] are the same value.
  /// Description is plain text on PensHub but we still pipe it through the
  /// HTML stripper as a defensive no-op.
  factory FlatpakPackage.fromPensHubJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString() ?? '';

    final descRaw =
        json['description']?.toString() ?? json['summary']?.toString() ?? '';
    final description = _stripHtml(descRaw);

    return FlatpakPackage(
      id: rawId,
      flatpakId: rawId,
      name: json['name']?.toString() ?? rawId,
      icon: json['icon']?.toString(),
      summary: json['summary']?.toString(),
      description: description.isEmpty ? null : description,
      developerName: json['developer_name']?.toString(),
      version: json['version']?.toString(),
      license: json['project_license']?.toString(),
      downloadSize: json['download_size']?.toString(),
      screenshots: _readStringList(json['screenshots']),
      homepage: json['homepage']?.toString(),
      categories: _readStringList(json['categories']),
      isVerified: json['is_verified'] == true,
      expiresAt: _parseDate(json['expires_at']),
    );
  }

  /// Human-readable size string ("127 MB", "1.2 GB"). Parses the stored
  /// [downloadSize] as bytes. Returns null when unavailable.
  String? get formattedDownloadSize {
    if (downloadSize == null || downloadSize!.isEmpty) return null;
    final bytes = int.tryParse(downloadSize!) ??
        double.tryParse(downloadSize!)?.round();
    if (bytes == null || bytes <= 0) return null;
    return _formatBytes(bytes);
  }

  static String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = 1024 * kb;
    const gb = 1024 * mb;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(bytes >= 10 * mb ? 0 : 1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  // --------------------------------------------------
  // TO MAP (SEMAST / CACHE)
  // --------------------------------------------------
  Map<String, dynamic> toMap() => {
    'id': id,
    'flatpak_id': flatpakId,
    'name': name,
    'icon': icon,
    'summary': summary,
    'description': description,
    'developer_name': developerName,
    'version': version,
    'license': license,
    'download_size': downloadSize,
    'screenshots': screenshots,
    'homepage': homepage,
    'bugtracker': bugtracker,
    'categories': categories,
    'is_verified': isVerified,
    'expires_at': expiresAt?.toIso8601String(),
  };

  // --------------------------------------------------
  // FROM MAP (CACHE / DB)
  // --------------------------------------------------
  factory FlatpakPackage.fromMap(Map<String, dynamic> map) {
    final flatpakId =
        map['flatpak_id']?.toString() ?? map['id']?.toString() ?? '';

    return FlatpakPackage(
      id: map['id']?.toString() ?? flatpakId,
      flatpakId: flatpakId,
      name: map['name']?.toString() ?? flatpakId,
      icon: map['icon']?.toString(),
      summary: map['summary']?.toString(),
      description: map['description']?.toString(),
      developerName: map['developer_name']?.toString(),
      version: map['version']?.toString(),
      license: map['license']?.toString(),
      downloadSize: map['download_size']?.toString(),
      screenshots: _readStringList(map['screenshots']),
      homepage: map['homepage']?.toString(),
      bugtracker: map['bugtracker']?.toString(),
      categories: _readStringList(map['categories']),
      isVerified: map['is_verified'] == true,
      expiresAt: _parseDate(map['expires_at']),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  // --------------------------------------------------
  // Helpers
  // --------------------------------------------------
  static List<String> _readStringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  /// Picks one usable URL per Flathub screenshot entry.
  ///
  /// Each screenshot is an object with a `sizes` array containing several
  /// resolutions of the same image. We prefer the largest size that's still
  /// reasonable for in-app rendering (≤ 1280 px wide), and fall back to the
  /// first available `src` if widths are missing.
  static List<String> _extractAppstreamScreenshots(dynamic v) {
    if (v is! List) return const [];
    final out = <String>[];
    for (final s in v) {
      if (s is! Map) continue;
      final sizes = s['sizes'];
      if (sizes is! List || sizes.isEmpty) continue;

      Map? best;
      int bestWidth = 0;
      for (final size in sizes) {
        if (size is! Map) continue;
        final w = int.tryParse(size['width']?.toString() ?? '') ?? 0;
        if (w == 0) continue;
        if (w <= 1280 && w > bestWidth) {
          best = size;
          bestWidth = w;
        }
      }
      best ??= sizes.first as Map?;
      final url = best?['src']?.toString();
      if (url != null && url.isNotEmpty) out.add(url);
    }
    return out;
  }

  /// Strips HTML tags from AppStream descriptions and decodes the few entity
  /// references that show up in practice. Block tags become newlines so
  /// paragraphs and bullets stay readable.
  static final _blockEndRe =
      RegExp(r'</(p|li|ul|ol|h[1-6])>', caseSensitive: false);
  static final _brRe = RegExp(r'<br\s*/?>', caseSensitive: false);
  static final _liStartRe = RegExp(r'<li[^>]*>', caseSensitive: false);
  static final _tagRe = RegExp(r'<[^>]+>');
  static final _multiNewlineRe = RegExp(r'\n{3,}');

  static String _stripHtml(String? html) {
    if (html == null || html.isEmpty) return '';
    if (!html.contains('<')) return html.trim();
    return html
        .replaceAll(_brRe, '\n')
        .replaceAll(_blockEndRe, '\n\n')
        .replaceAll(_liStartRe, '• ')
        .replaceAll(_tagRe, '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(_multiNewlineRe, '\n\n')
        .trim();
  }

  // --------------------------------------------------
  // Flatpak ID Validator (shared) — uses static RegExp
  // --------------------------------------------------
  static bool _looksLikeFlatpakId(String id) {
    if (!id.contains('.')) return false;

    final parts = id.split('.');
    for (int i = 0; i < parts.length; i++) {
      final isLast = i == parts.length - 1;
      if (!(isLast ? _lastPartRe : _partRe).hasMatch(parts[i])) return false;
    }
    return true;
  }
}
