import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/base_provider.dart';

class UploadService extends ChangeNotifier {
  final List<UploadTask> _tasks = [];
  List<UploadTask> get tasks => List.unmodifiable(_tasks);

  Future<List<File>?> pickFiles({bool allowMultiple = true}) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: allowMultiple);
    if (result == null) return null;
    return result.files.where((f) => f.path != null).map((f) => File(f.path!)).toList();
  }

  Future<UploadTask?> upload({
    required BaseDriveProvider provider,
    required File file,
    required String remotePath,
  }) async {
    final task = UploadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: file.uri.pathSegments.last,
      localPath: file.path,
      remotePath: remotePath,
      totalSize: await file.length(),
    );
    _tasks.insert(0, task);
    notifyListeners();

    provider.uploadFile(file.path, remotePath, onProgress: (p) {
      task.progress = p;
      task.uploadedSize = (task.totalSize * p).toInt();
      notifyListeners();
    }).then((success) {
      task.status = success ? UploadStatus.completed : UploadStatus.failed;
      notifyListeners();
    }).catchError((e) {
      task.status = UploadStatus.failed;
      task.error = e.toString();
      notifyListeners();
    });

    return task;
  }
}

enum UploadStatus { pending, uploading, completed, failed, canceled }

class UploadTask {
  final String id;
  final String fileName;
  final String localPath;
  final String remotePath;
  final int totalSize;
  int uploadedSize = 0;
  double progress = 0;
  UploadStatus status = UploadStatus.uploading;
  String? error;

  UploadTask({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.remotePath,
    required this.totalSize,
  });
}
