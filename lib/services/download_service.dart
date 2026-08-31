import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/download_task.dart';

class DownloadService extends ChangeNotifier {
  static const _channel = MethodChannel('com.panpal.app/gopeed');

  int _gopeedPort = 0;
  bool _initialized = false;
  final List<DownloadTask> _tasks = [];
  Timer? _pollTimer;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  int get defaultConnections => 16;

  String get _baseUrl => 'http://127.0.0.1:$_gopeedPort';

  Future<void> init() async {
    if (_initialized) return;
    try {
      final port = await _channel.invokeMethod<int>('startGopeed');
      _gopeedPort = port ?? 0;
      if (_gopeedPort > 0) {
        _initialized = true;
        _startPolling();
      }
    } catch (e) {
      debugPrint('Gopeed init failed: $e');
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _syncTasks());
  }

  Future<void> _syncTasks() async {
    if (_gopeedPort == 0) return;
    try {
      final resp = await http.get(Uri.parse('$_baseUrl/api/v1/tasks')).timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final list = data['data'] as List? ?? [];
        for (final item in list) {
          final id = item['id'] as String? ?? '';
          final idx = _tasks.indexWhere((t) => t.id == id);
          final status = _mapStatus(item['status'] as int? ?? 0);
          final task = DownloadTask(
            id: id,
            url: item['url'] as String? ?? '',
            fileName: item['name'] as String? ?? '',
            savePath: item['path'] as String? ?? '',
            totalSize: item['size'] as int? ?? 0,
            downloadedSize: item['downloaded'] as int? ?? 0,
            status: status,
            connections: defaultConnections,
            speed: (item['speed'] as num?)?.toDouble() ?? 0,
            createdAt: DateTime.now(),
            completedAt: status == DownloadStatus.completed ? DateTime.now() : null,
            error: item['error'] as String?,
          );
          if (idx >= 0) {
            _tasks[idx] = task;
          } else {
            _tasks.insert(0, task);
          }
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  DownloadStatus _mapStatus(int status) {
    switch (status) {
      case 1:
        return DownloadStatus.downloading;
      case 2:
        return DownloadStatus.paused;
      case 3:
        return DownloadStatus.failed;
      case 4:
        return DownloadStatus.completed;
      default:
        return DownloadStatus.idle;
    }
  }

  Future<DownloadTask?> addTask({
    required String url,
    required String fileName,
    String? savePath,
    int? connections,
    Map<String, String> headers = const {},
  }) async {
    if (_gopeedPort == 0 || url.isEmpty) return null;
    try {
      final dir = savePath ?? (await getExternalStorageDirectory())?.path ?? '/storage/emulated/0/Download/PanPal';
      final body = jsonEncode({
        'req': {
          'url': url,
          'name': fileName,
          'path': dir,
          if (headers.isNotEmpty) 'extra': {'headers': headers},
        }
      });
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/api/v1/tasks'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final taskId = data['data']?['id'] as String? ?? '';
        final task = DownloadTask(
          id: taskId,
          url: url,
          fileName: fileName,
          savePath: '$dir/$fileName',
          connections: connections ?? defaultConnections,
          createdAt: DateTime.now(),
        );
        _tasks.insert(0, task);
        notifyListeners();
        return task;
      }
    } catch (e) {
      debugPrint('Add task failed: $e');
    }
    return null;
  }

  Future<void> pauseTask(String taskId) async {
    if (_gopeedPort == 0) return;
    try {
      await http.put(Uri.parse('$_baseUrl/api/v1/tasks/$taskId/pause')).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> resumeTask(String taskId) async {
    if (_gopeedPort == 0) return;
    try {
      await http.put(Uri.parse('$_baseUrl/api/v1/tasks/$taskId/continue')).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> cancelTask(String taskId) async {
    if (_gopeedPort == 0) return;
    try {
      await http.delete(Uri.parse('$_baseUrl/api/v1/tasks/$taskId?force=true')).timeout(const Duration(seconds: 5));
      _tasks.removeWhere((t) => t.id == taskId);
      notifyListeners();
    } catch (_) {}
  }

  void clearCompleted() {
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed || t.status == DownloadStatus.failed);
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
