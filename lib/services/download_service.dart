import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/download_task.dart';
import 'gopeed_engine.dart';
import 'credential_storage.dart';

class DownloadService extends ChangeNotifier {
  final GopeedDownloadEngine _engine = GopeedDownloadEngine();
  final List<DownloadTask> _tasks = [];
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  List<DownloadTask> get activeTasks => _tasks.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.paused).toList();
  List<DownloadTask> get completedTasks => _tasks.where((t) => t.status == DownloadStatus.completed).toList();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _notifications.initialize(initSettings);
  }

  void configure({required int defaultConnections, required int maxConcurrentTasks, required String downloadPath}) {
    _engine.defaultConnections = defaultConnections;
    _engine.maxConcurrentTasks = maxConcurrentTasks;
  }

  Future<DownloadTask?> addTask({
    required String url,
    required String fileName,
    String? savePath,
    int? connections,
    Map<String, String> headers = const {},
  }) async {
    if (url.isEmpty) return null;
    final task = await _engine.createTask(
      url: url,
      fileName: fileName,
      savePath: savePath,
      connections: connections ?? _engine.defaultConnections,
      headers: headers,
    );
    _tasks.insert(0, task);
    notifyListeners();

    // 检查并发数
    final active = activeTasks.length;
    if (active < _engine.maxConcurrentTasks) {
      _startTask(task);
    }
    return task;
  }

  void _startTask(DownloadTask task) {
    _engine.start(
      task,
      onProgress: (t) {
        final idx = _tasks.indexWhere((e) => e.id == t.id);
        if (idx >= 0) {
          _tasks[idx] = t;
          notifyListeners();
        }
      },
      onComplete: (t) {
        final idx = _tasks.indexWhere((e) => e.id == t.id);
        if (idx >= 0) {
          _tasks[idx] = t;
          notifyListeners();
        }
        _showNotification(t.fileName, '下载完成');
        _startNextWaiting();
      },
      onError: (t, error) {
        final idx = _tasks.indexWhere((e) => e.id == t.id);
        if (idx >= 0) {
          _tasks[idx] = t;
          notifyListeners();
        }
        _startNextWaiting();
      },
    );
  }

  void _startNextWaiting() {
    final waiting = _tasks.where((t) => t.status == DownloadStatus.idle).toList();
    if (waiting.isNotEmpty && activeTasks.length < _engine.maxConcurrentTasks) {
      _startTask(waiting.first);
    }
  }

  void pauseTask(String taskId) {
    _engine.pause(taskId);
  }

  void resumeTask(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    if (activeTasks.length < _engine.maxConcurrentTasks) {
      _engine.resume(taskId);
    }
  }

  void cancelTask(String taskId) {
    _engine.cancel(taskId);
    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
    _startNextWaiting();
  }

  void removeTask(String taskId) {
    cancelTask(taskId);
  }

  void clearCompleted() {
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed || t.status == DownloadStatus.failed || t.status == DownloadStatus.canceled);
    notifyListeners();
  }

  Future<void> _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'download_channel',
      '下载通知',
      channelDescription: '下载完成通知',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(DateTime.now().millisecond, title, body, details);
  }
}
