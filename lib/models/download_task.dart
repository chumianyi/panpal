enum DownloadStatus { idle, downloading, paused, completed, failed, canceled }

class DownloadTask {
  final String id;
  final String url;
  final String fileName;
  final String savePath;
  int totalSize;
  int downloadedSize;
  DownloadStatus status;
  final int connections;
  double speed;
  final DateTime createdAt;
  DateTime? completedAt;
  String? error;
  final Map<String, String> headers;

  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.totalSize = 0,
    this.downloadedSize = 0,
    this.status = DownloadStatus.idle,
    this.connections = 16,
    this.speed = 0,
    DateTime? createdAt,
    this.completedAt,
    this.error,
    this.headers = const {},
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress => totalSize > 0 ? downloadedSize / totalSize : 0;

  String get progressPercent => (progress * 100).toStringAsFixed(1);

  DownloadTask copyWith({
    int? downloadedSize,
    DownloadStatus? status,
    double? speed,
    DateTime? completedAt,
    String? error,
    int? totalSize,
  }) {
    return DownloadTask(
      id: id,
      url: url,
      fileName: fileName,
      savePath: savePath,
      totalSize: totalSize ?? this.totalSize,
      downloadedSize: downloadedSize ?? this.downloadedSize,
      status: status ?? this.status,
      connections: connections,
      speed: speed ?? this.speed,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      error: error ?? this.error,
      headers: headers,
    );
  }
}
