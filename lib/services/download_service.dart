import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/download_task.dart';

class _Segment {
  final int index;
  int start;
  int end;
  int downloaded;
  CancelToken? cancelToken;
  bool active;
  bool cancelled;

  _Segment({
    required this.index,
    required this.start,
    required this.end,
    this.downloaded = 0,
    this.cancelToken,
    this.active = false,
    this.cancelled = false,
  });

  int get total => end - start + 1;
  int get currentStart => start + downloaded;
}

class _SpeedPoint {
  final int bytes;
  final DateTime time;
  _SpeedPoint(this.bytes, this.time);
}

class DownloadService extends ChangeNotifier {
  final Dio _dio = Dio();
  final List<DownloadTask> _tasks = [];
  final Map<String, List<_Segment>> _segments = {};
  final Map<String, List<File>> _tempFiles = {};
  Timer? _pollTimer;
  int _defaultConnections = 16;
  static const int _maxConnections = 64;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  int get defaultConnections => _defaultConnections;
  int get maxConnections => _maxConnections;

  DownloadService() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 0);
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _updateProgress());
  }

  void setDefaultConnections(int n) {
    _defaultConnections = n.clamp(1, _maxConnections);
  }

  Future<String> get _downloadDir async {
    final dir = await getExternalStorageDirectory();
    final path = '${dir?.path ?? '/storage/emulated/0/Download'}/PanPal';
    final d = Directory(path);
    if (!await d.exists()) await d.create(recursive: true);
    return path;
  }

  Future<DownloadTask?> addTask({
    required String url,
    required String fileName,
    String? savePath,
    int? connections,
    Map<String, String> headers = const {},
  }) async {
    if (url.isEmpty) return null;
    final conn = (connections ?? _defaultConnections).clamp(1, _maxConnections);
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    final dir = savePath ?? await _downloadDir;

    final task = DownloadTask(
      id: taskId,
      url: url,
      fileName: fileName,
      savePath: '$dir/$fileName',
      connections: conn,
      status: DownloadStatus.idle,
      createdAt: DateTime.now(),
    );
    _tasks.insert(0, task);
    notifyListeners();

    unawaited(_startDownload(task, headers));
    return task;
  }

  Future<void> _startDownload(DownloadTask task, Map<String, String> headers) async {
    try {
      _updateTask(task.id, status: DownloadStatus.downloading);

      // HEAD request to get file size
      final headResp = await _dio.head(
        task.url,
        options: Options(headers: headers, followRedirects: true),
      );
      final contentLength = int.tryParse(headResp.headers.value('content-length') ?? '') ?? 0;
      final acceptRanges = headResp.headers.value('accept-ranges') ?? '';
      final supportsRange = acceptRanges.contains('bytes') && contentLength > 0;

      if (contentLength > 0) {
        _updateTask(task.id, totalSize: contentLength);
      }

      if (!supportsRange || contentLength <= 0) {
        // Single connection download
        await _singleConnectionDownload(task, headers);
        return;
      }

      // Multi-connection download
      final conn = task.connections;
      final segmentSize = contentLength ~/ conn;
      final segments = <_Segment>[];
      final tempFiles = <File>[];

      for (int i = 0; i < conn; i++) {
        final start = i * segmentSize;
        final end = (i == conn - 1) ? contentLength - 1 : start + segmentSize - 1;
        segments.add(_Segment(index: i, start: start, end: end));
        final tempFile = File('${task.savePath}.part$i');
        tempFiles.add(tempFile);
      }

      _segments[task.id] = segments;
      _tempFiles[task.id] = tempFiles;

      // Download all segments in parallel
      final futures = segments.map((seg) => _downloadSegment(task, seg, tempFiles[seg.index], headers)).toList();
      await Future.wait(futures, eagerError: false);

      // Check if all segments completed
      final allDone = segments.every((s) => s.downloaded >= s.total);
      if (allDone && _tasks.any((t) => t.id == task.id && t.status != DownloadStatus.canceled)) {
        await _mergeSegments(task, tempFiles);
        _updateTask(task.id, status: DownloadStatus.completed, downloadedSize: contentLength, completedAt: DateTime.now());
      }
    } catch (e) {
      if (_tasks.any((t) => t.id == task.id && t.status != DownloadStatus.canceled)) {
        _updateTask(task.id, status: DownloadStatus.failed, error: e.toString());
      }
    }
  }

  Future<void> _downloadSegment(DownloadTask task, _Segment seg, File tempFile, Map<String, String> headers) async {
    seg.active = true;
    seg.cancelToken = CancelToken();
    try {
      final resp = await _dio.get(
        task.url,
        options: Options(
          headers: {
            ...headers,
            'Range': 'bytes=${seg.currentStart}-${seg.end}',
          },
          responseType: ResponseType.stream,
        ),
        cancelToken: seg.cancelToken,
      );

      final raf = await tempFile.open(mode: FileMode.append);
      await raf.setPosition(seg.downloaded);

      await for (final chunk in resp.data!.stream) {
        if (seg.cancelled) break;
        await raf.writeFrom(chunk);
        seg.downloaded += (chunk.length as int);
        _updateTaskProgress(task.id);
      }
      await raf.close();
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) {
        rethrow;
      }
    } finally {
      seg.active = false;
    }
  }

  Future<void> _singleConnectionDownload(DownloadTask task, Map<String, String> headers) async {
    try {
      final tempFile = File('${task.savePath}.tmp');
      final cancelToken = CancelToken();
      _segments[task.id] = [_Segment(index: 0, start: 0, end: 0, active: true, cancelToken: cancelToken)];
      _tempFiles[task.id] = [tempFile];

      await _dio.download(
        task.url,
        tempFile.path,
        options: Options(headers: headers),
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          _updateTask(task.id, downloadedSize: received, totalSize: total > 0 ? total : null);
        },
      );

      if (_tasks.any((t) => t.id == task.id && t.status != DownloadStatus.canceled)) {
        await tempFile.rename(task.savePath);
        _updateTask(task.id, status: DownloadStatus.completed, completedAt: DateTime.now());
      }
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) {
        _updateTask(task.id, status: DownloadStatus.failed, error: e.toString());
      }
    }
  }

  Future<void> _mergeSegments(DownloadTask task, List<File> tempFiles) async {
    final output = File(task.savePath);
    final raf = await output.open(mode: FileMode.write);
    for (final f in tempFiles) {
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        await raf.writeFrom(bytes);
      }
    }
    await raf.close();
    for (final f in tempFiles) {
      if (await f.exists()) await f.delete();
    }
  }

  void _updateTaskProgress(String taskId) {
    final segs = _segments[taskId];
    if (segs == null) return;
    final downloaded = segs.fold<int>(0, (sum, s) => sum + s.downloaded);
    final total = segs.fold<int>(0, (sum, s) => sum + s.total);
    final speed = _calculateSpeed(taskId, downloaded);
    _updateTask(taskId, downloadedSize: downloaded, totalSize: total > 0 ? total : null, speed: speed);
  }

  final Map<String, List<_SpeedPoint>> _speedHistory = {};

  double _calculateSpeed(String taskId, int downloaded) {
    final now = DateTime.now();
    final history = _speedHistory.putIfAbsent(taskId, () => []);
    history.add(_SpeedPoint(downloaded, now));
    while (history.length > 10) history.removeAt(0);
    if (history.length < 2) return 0;
    final first = history.first;
    final last = history.last;
    final dt = last.time.difference(first.time).inMilliseconds / 1000;
    if (dt <= 0) return 0;
    return (last.bytes - first.bytes) / dt;
  }

  void _updateProgress() {
    bool changed = false;
    for (final task in _tasks) {
      if (task.status == DownloadStatus.downloading) {
        final segs = _segments[task.id];
        if (segs != null) {
          final downloaded = segs.fold<int>(0, (sum, s) => sum + s.downloaded);
          final speed = _calculateSpeed(task.id, downloaded);
          final idx = _tasks.indexWhere((t) => t.id == task.id);
          if (idx >= 0) {
            _tasks[idx] = _tasks[idx].copyWith(downloadedSize: downloaded, speed: speed);
            changed = true;
          }
        }
      }
    }
    if (changed) notifyListeners();
  }

  void _updateTask(String taskId, {DownloadStatus? status, int? downloadedSize, int? totalSize, double? speed, String? error, DateTime? completedAt}) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    _tasks[idx] = _tasks[idx].copyWith(
      status: status,
      downloadedSize: downloadedSize,
      totalSize: totalSize,
      speed: speed,
      error: error,
      completedAt: completedAt,
    );
    notifyListeners();
  }

  Future<void> pauseTask(String taskId) async {
    final segs = _segments[taskId];
    if (segs != null) {
      for (final seg in segs) {
        seg.cancelled = true;
        seg.cancelToken?.cancel();
      }
    }
    _updateTask(taskId, status: DownloadStatus.paused);
  }

  Future<void> resumeTask(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (task.status != DownloadStatus.paused) return;

    final segs = _segments[taskId];
    if (segs == null || segs.isEmpty) {
      // Single connection mode, restart
      _updateTask(taskId, status: DownloadStatus.idle);
      unawaited(_startDownload(task, const {}));
      return;
    }

    _updateTask(taskId, status: DownloadStatus.downloading);
    final tempFiles = _tempFiles[taskId] ?? [];
    for (final seg in segs) {
      seg.cancelled = false;
      seg.cancelToken = CancelToken();
    }
    final futures = segs.where((s) => s.downloaded < s.total).map((seg) {
      return _downloadSegment(task, seg, tempFiles[seg.index], const {});
    }).toList();

    await Future.wait(futures, eagerError: false);
    final allDone = segs.every((s) => s.downloaded >= s.total);
    if (allDone && _tasks.any((t) => t.id == taskId && t.status != DownloadStatus.canceled)) {
      await _mergeSegments(task, tempFiles);
      _updateTask(taskId, status: DownloadStatus.completed, completedAt: DateTime.now());
    }
  }

  Future<void> cancelTask(String taskId) async {
    final segs = _segments[taskId];
    if (segs != null) {
      for (final seg in segs) {
        seg.cancelled = true;
        seg.cancelToken?.cancel();
      }
    }
    final tempFiles = _tempFiles[taskId];
    if (tempFiles != null) {
      for (final f in tempFiles) {
        if (await f.exists()) await f.delete();
      }
    }
    _segments.remove(taskId);
    _tempFiles.remove(taskId);
    _speedHistory.remove(taskId);
    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  void clearCompleted() {
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed || t.status == DownloadStatus.failed);
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final segs in _segments.values) {
      for (final seg in segs) {
        seg.cancelToken?.cancel();
      }
    }
    super.dispose();
  }
}
