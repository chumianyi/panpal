class CloudFile {
  final String id;
  final String name;
  final bool isDir;
  final int size;
  final DateTime? modifiedAt;
  final String path;
  final String? downloadUrl;
  final String? thumbnail;
  final String? fileId;
  final Map<String, dynamic> raw;

  const CloudFile({
    required this.id,
    required this.name,
    this.isDir = false,
    this.size = 0,
    this.modifiedAt,
    this.path = '',
    this.downloadUrl,
    this.thumbnail,
    this.fileId,
    this.raw = const {},
  });

  String get extension {
    if (isDir) return '';
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  factory CloudFile.fromJson(Map<String, dynamic> json) => CloudFile(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    isDir: json['isDir'] as bool? ?? false,
    size: json['size'] as int? ?? 0,
    modifiedAt: json['modifiedAt'] != null ? DateTime.tryParse(json['modifiedAt'].toString()) : null,
    path: json['path'] as String? ?? '',
    downloadUrl: json['downloadUrl'] as String?,
    thumbnail: json['thumbnail'] as String?,
    fileId: json['fileId'] as String?,
    raw: json['raw'] as Map<String, dynamic>? ?? {},
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isDir': isDir,
    'size': size,
    'modifiedAt': modifiedAt?.toIso8601String(),
    'path': path,
    'downloadUrl': downloadUrl,
    'thumbnail': thumbnail,
    'fileId': fileId,
    'raw': raw,
  };
}
