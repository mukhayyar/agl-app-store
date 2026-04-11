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
  });

  // --------------------------------------------------
  // FROM APPSTREAM / FLATHUB API
  // --------------------------------------------------
  factory FlatpakPackage.fromAppstream(Map<String, dynamic> json) {
    String _asStringOrFirst(dynamic v) {
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

    return FlatpakPackage(
      id: internalId,
      flatpakId: flatpakId,
      name: _asStringOrFirst(json['name']),
      icon: json['icon']?.toString(),
      summary: _asStringOrFirst(json['summary']),
      description: _asStringOrFirst(json['description']),
      developerName: json['developer_name']?.toString(),
      version: json['version']?.toString(),
      license: json['license']?.toString(),
      downloadSize: json['download_size']?.toString(),
    );
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
    );
  }

  // --------------------------------------------------
  // Flatpak ID Validator (shared)
  // --------------------------------------------------
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
}
