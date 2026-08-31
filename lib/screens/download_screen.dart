import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/download_task.dart';
import '../services/download_service.dart';
import '../utils/format_utils.dart';

class DownloadScreen extends StatelessWidget {
  const DownloadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloadService = context.watch<DownloadService>();
    final tasks = downloadService.tasks;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('下载管理', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            tabs: [Tab(text: '下载中'), Tab(text: '已完成')],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清除已完成',
              onPressed: () => downloadService.clearCompleted(),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildTaskList(tasks.where((t) => t.status != DownloadStatus.completed).toList(), downloadService),
            _buildTaskList(tasks.where((t) => t.status == DownloadStatus.completed).toList(), downloadService),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList(List<DownloadTask> tasks, DownloadService service) {
    if (tasks.isEmpty) {
      return Center(child: Text('暂无下载任务', style: TextStyle(color: Colors.grey[600])));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_getFileIcon(task.fileName), size: 32, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(task.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                            task.status == DownloadStatus.downloading
                                ? '${FormatUtils.fileSize(task.downloadedSize)} / ${FormatUtils.fileSize(task.totalSize)} · ${FormatUtils.speed(task.speed)}'
                                : task.status == DownloadStatus.paused
                                    ? '已暂停 · ${FormatUtils.fileSize(task.downloadedSize)} / ${FormatUtils.fileSize(task.totalSize)}'
                                    : task.status == DownloadStatus.completed
                                        ? '${FormatUtils.fileSize(task.totalSize)} · 下载完成'
                                        : task.status == DownloadStatus.failed
                                            ? '下载失败: ${task.error ?? ''}'
                                            : '等待中...',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.paused)
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'pause') service.pauseTask(task.id);
                          if (v == 'resume') service.resumeTask(task.id);
                          if (v == 'cancel') service.cancelTask(task.id);
                        },
                        itemBuilder: (context) => [
                          if (task.status == DownloadStatus.downloading)
                            const PopupMenuItem(value: 'pause', child: Text('暂停')),
                          if (task.status == DownloadStatus.paused)
                            const PopupMenuItem(value: 'resume', child: Text('继续')),
                          const PopupMenuItem(value: 'cancel', child: Text('取消')),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: task.status == DownloadStatus.completed ? 1.0 : task.progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('${task.progressPercent}%', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getFileIcon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'mp4':
      case 'mkv':
      case 'avi':
        return Icons.movie;
      case 'mp3':
      case 'flac':
        return Icons.music_note;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.archive;
      case 'apk':
        return Icons.android;
      default:
        return Icons.download;
    }
  }
}
