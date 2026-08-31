import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:clipboard/clipboard.dart';
import 'package:open_filex/open_filex.dart';
import '../services/chumian_drive_service.dart';
import '../services/notification_service.dart';
import '../utils/format_utils.dart';

class ChumianDriveScreen extends StatefulWidget {
  final ChumianDriveService service;
  const ChumianDriveScreen({super.key, required this.service});

  @override
  State<ChumianDriveScreen> createState() => _ChumianDriveScreenState();
}

class _ChumianDriveScreenState extends State<ChumianDriveScreen> {
  List<ChumianFile> _files = [];
  bool _loading = false;
  final TextEditingController _portController = TextEditingController(text: '8080');

  @override
  void initState() {
    super.initState();
    _portController.text = widget.service.port.toString();
    _refreshFiles();
  }

  Future<void> _refreshFiles() async {
    setState(() => _loading = true);
    try {
      final files = await widget.service.listFiles();
      if (mounted) setState(() => _files = files);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleServer() async {
    if (widget.service.isRunning) {
      await widget.service.stopServer();
      await NotificationService.stopForegroundService();
    } else {
      final port = int.tryParse(_portController.text) ?? 8080;
      try {
        await widget.service.startServer(port: port);
        await NotificationService.startForegroundService(
          title: '初眠网盘运行中',
          body: 'http://${widget.service.localIp ?? 'localhost'}:$port',
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('启动失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        if (file.bytes != null) {
          await widget.service.saveFile(file.name, file.bytes!);
        } else if (file.path != null) {
          final bytes = await File(file.path!).readAsBytes();
          await widget.service.saveFile(file.name, bytes);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已上传 ${result.files.length} 个文件'), backgroundColor: Colors.green),
        );
      }
      _refreshFiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteFile(ChumianFile file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定要删除「${file.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.service.deleteFile(file.name);
    _refreshFiles();
  }

  void _copyShareLink(ChumianFile file) {
    final url = widget.service.getShareUrl(file.name);
    FlutterClipboard.copy(url);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('分享链接已复制: $url')),
    );
  }

  void _openFile(ChumianFile file) {
    OpenFilex.open(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return Scaffold(
      appBar: AppBar(
        title: const Text('初眠网盘', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshFiles,
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          // Server status card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: service.isRunning
                    ? [Colors.blue.shade400, Colors.blue.shade600]
                    : [Colors.grey.shade400, Colors.grey.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(service.isRunning ? Icons.cloud_done : Icons.cloud_off, color: Colors.white, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(service.isRunning ? '服务运行中' : '服务已停止',
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          if (service.isRunning && service.localIp != null)
                            Text('http://${service.localIp}:${service.port}',
                                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                    Switch(
                      value: service.isRunning,
                      onChanged: (_) => _toggleServer(),
                      activeColor: Colors.white,
                    ),
                  ],
                ),
                if (service.isRunning) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('同一网络下其他设备可访问上方链接下载文件',
                              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Port setting
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('端口:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    enabled: !service.isRunning,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      hintText: '8080',
                    ),
                  ),
                ),
                const Spacer(),
                Text('${_files.length} 个文件', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // File list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text('暂无文件，点击下方按钮上传', style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _files.length,
                        itemBuilder: (context, index) {
                          final file = _files[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.insert_drive_file, color: Colors.blue),
                              ),
                              title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w500)),
                              subtitle: Text('${FormatUtils.fileSize(file.size)} · ${_formatDate(file.modifiedAt)}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'share') _copyShareLink(file);
                                  if (v == 'open') _openFile(file);
                                  if (v == 'delete') _deleteFile(file);
                                },
                                itemBuilder: (context) => [
                                  if (service.isRunning) const PopupMenuItem(value: 'share', child: Text('复制分享链接')),
                                  const PopupMenuItem(value: 'open', child: Text('打开文件')),
                                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadFile,
        icon: const Icon(Icons.upload_file),
        label: const Text('上传文件'),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
