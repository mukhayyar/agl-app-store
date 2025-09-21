class FlatpakPackage {
  final String id;
  final String name;
  final String? icon;
  final String? summary;
  final String? description;
  final String? developerName;
  final String? version;
  final String? license;
  final String? downloadSize;

  const FlatpakPackage({
    required this.id,
    required this.name,
    this.icon,
    this.summary,
    this.description,
    this.developerName,
    this.version,
    this.license,
    this.downloadSize,
  });

  factory FlatpakPackage.fromAppstream(Map<String, dynamic> json) {
  // kadang “name” bisa berupa Map (multi-locale). Ambil string jika perlu.
  String _asStringOrFirst(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is Map && v.isNotEmpty) {
      // ambil salah satu nilai (mis. "C" / "en_US")
      final first = v.values.first;
      if (first is String) return first;
    }
    return v.toString();
  }

  return FlatpakPackage(
    id: json['id']?.toString() ?? '',
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

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'icon': icon,
    'summary': summary,
    'description': description,
    'developer_name': developerName,
    'version': version,
    'license': license,
    'download_size': downloadSize,
  };

  factory FlatpakPackage.fromMap(Map<String, dynamic> map) => FlatpakPackage(
    id: map['id'] ?? '',
    name: map['name'] ?? '',
    icon: map['icon'],
    summary: map['summary'],
    description: map['description'],
    developerName: map['developer_name'],
    version: map['version'],
    license: map['license'],
    downloadSize: map['download_size']?.toString(),
  );
}
