import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/download_task.dart';

/// Gopeed 多连接下载引擎
/// 支持 16-64 连接数，基于 HTTP Range 请求实现多线程分段下载
class GopeedDownloadEngine {
  final Map<String, _DownloadWorker> _workers = {};
  int defaultConnections = 16;
  int maxConcurrentTasks = 3;

  Future<DownloadTask> createTask({
    required String url,
    required String fileName,
    String? savePath,
    int connections = 16,
    Map<String, String> headers = const {},
  }) async {
    final dir = savePath ?? (await getExternalStorageDirectory())?.path ?? '/storage/emulated/0/Download/PanPal';
    final saveDir = Directory(dir);
    if (!await saveDir.exists()) await saveDir.create(recursive: true);

    final task = DownloadTask(
      id: _genId(),
      url: url,
      fileName: fileName,
      savePath: '$dir/$fileName',
      connections: connections.clamp(1, 64),
      headers: headers,
    );
    return task;
  }

  Future<void> start(DownloadTask task, {
    required Function(DownloadTask) onProgress,
    required Function(DownloadTask) onComplete,
    required Function(DownloadTask, String) onError,
  }) async {
    final worker = _DownloadWorker(task, onProgress: onProgress, onComplete: onComplete, onError: onError);
    _workers[task.id] = worker;
    await worker.start();
  }

  void pause(String taskId) => _workers[taskId]?.pause();
  void resume(String taskId) => _workers[taskId]?.resume();
  void cancel(String taskId) {
    _workers[taskId]?.cancel();
    _workers.remove(taskId);
  }

  String _genId() => DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(9999).toString();
}

class _DownloadWorker {
  final DownloadTask task;
  final Function(DownloadTask) onProgress;
  final Function(DownloadTask) onComplete;
  final Function(DownloadTask, String) onError;

  bool _paused = false;
  bool _canceled = false;
  final List<_ChunkDownloader> _chunks = [];
  Timer? _speedTimer;
  int _lastDownloaded = 0;

  _DownloadWorker(this.task, {required this.onProgress, required this.onComplete, required this.onError});

  Future<void> start() async {
    try {
      task.status = DownloadStatus.downloading;
      onProgress(task);

      // 获取文件大小
      final totalSize = await _getFileSize();
      task.totalSize = totalSize;
      if (totalSize <= 0) {
        throw Exception('无法获取文件大小');
      }

      // 计算分段
      final chunkSize = (totalSize / task.connections).ceil();
      _chunks.clear();
      for (var i = 0; i < task.connections; i++) {
        final start = i * chunkSize;
        final end = min((i + 1) * chunkSize - 1, totalSize - 1);
        if (start > end) continue;
        _chunks.add(_ChunkDownloader(
          url: task.url,
          savePath: '${task.savePath}.part$i',
          start: start,
          end: end,
          headers: task.headers,
        ));
      }

      // 启动速度统计
      _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final current = _getTotalDownloaded();
        task.speed = (current - _lastDownloaded).toDouble();
        _lastDownloaded = current;
        task.downloadedSize = current;
        onProgress(task);
      });

      // 并发下载所有分段
      await Future.wait(_chunks.map((c) => _runChunk(c)));

      if (_canceled) {
        _cleanup();
        return;
      }

      // 合并文件
      await _mergeChunks();
      _cleanup();

      task.status = DownloadStatus.completed;
      task.downloadedSize = task.totalSize;
      task.completedAt = DateTime.now();
      task.speed = 0;
      onComplete(task);
    } catch (e) {
      _cleanup();
      task.status = DownloadStatus.failed;
      task.error = e.toString();
      onError(task, e.toString());
    }
  }

  Future<void> _runChunk(_ChunkDownloader chunk) async {
    while (!_canceled) {
      if (_paused) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }
      try {
        await chunk.download();
        return;
      } catch (_) {
        if (_canceled) return;
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<int> _getFileSize() async {
    final client = HttpClient();
    try {
      final request = await client.headUrl(Uri.parse(task.url));
      task.headers.forEach((k, v) => request.headers.set(k, v));
      request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
      final response = await request.close();
      final length = response.contentLength;
      if (length > 0) return length;
      // 如果 HEAD 不支持，用 GET Range 探测
      final getReq = await client.getUrl(Uri.parse(task.url));
      task.headers.forEach((k, v) => getReq.headers.set(k, v));
      getReq.headers.set('Range', 'bytes=0-0');
      final getResp = await getReq.close();
      final contentRange = getResp.headers.value('content-range');
      if (contentRange != null) {
        final match = RegExp(r'bytes \d+-\d+/(\d+)').firstMatch(contentRange);
        if (match != null) return int.parse(match.group(1)!);
      }
      return getResp.contentLength;
    } finally {
      client.close();
    }
  }

  int _getTotalDownloaded() {
    var total = 0;
    for (final chunk in _chunks) {
      total += chunk.downloaded;
    }
    return total;
  }

  Future<void> _mergeChunks() async {
    final output = File(task.savePath);
    final sink = output.openWrite();
    for (var i = 0; i < _chunks.length; i++) {
      final part = File('${task.savePath}.part$i');
      if (await part.exists()) {
        await sink.addStream(part.openRead());
        await part.delete();
      }
    }
    await sink.close();
  }

  void _cleanup() {
    _speedTimer?.cancel();
    for (final chunk in _chunks) {
      chunk.cancel();
    }
  }

  void pause() {
    _paused = true;
    task.status = DownloadStatus.paused;
    onProgress(task);
  }

  void resume() {
    _paused = false;
    task.status = DownloadStatus.downloading;
    onProgress(task);
  }

  void cancel() {
    _canceled = true;
    _cleanup();
    // 清理临时文件
    for (var i = 0; i < _chunks.length; i++) {
      final part = File('${task.savePath}.part$i');
      part.exists().then((e) => e ? part.delete() : null);
    }
    task.status = DownloadStatus.canceled;
    onProgress(task);
  }
}

class _ChunkDownloader {
  final String url;
  final String savePath;
  final int start;
  final int end;
  final Map<String, String> headers;
  int downloaded = 0;
  bool _canceled = false;
  HttpClient? _client;

  _ChunkDownloader({required this.url, required this.savePath, required this.start, required this.end, this.headers = const {}});

  Future<void> download() async {
    _client = HttpClient();
    try {
      final file = File(savePath);
      var currentStart = start;
      // 支持断点续传
      if (await file.exists()) {
        currentStart = start + await file.length();
        if (currentStart > end) {
          downloaded = end - start + 1;
          return;
        }
      }

      final request = await _client!.getUrl(Uri.parse(url));
      headers.forEach((k, v) => request.headers.set(k, v));
      request.headers.set('Range', 'bytes=$currentStart-$end');
      request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');

      final response = await request.close();
      if (response.statusCode != 206 && response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final sink = file.openWrite(mode: currentStart > start ? FileMode.append : FileMode.write);
      await response.listen((data) {
        if (_canceled) throw Exception('canceled');
        sink.add(data);
        downloaded += data.length;
      }).asFuture();
      await sink.close();
      downloaded = end - start + 1;
    } finally {
      _client?.close();
    }
  }

  void cancel() {
    _canceled = true;
    _client?.close(force: true);
  }
}
