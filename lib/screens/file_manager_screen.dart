import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/alist_service.dart';
import '../services/alist_api_client.dart';
import '../services/download_service.dart';
import '../utils/format_utils.dart';

class FileManagerScreen extends StatefulWidget {
  final AListService alistService;
  final String mountPath;
  final String title;
  const FileManagerScreen({super.key, required this.alistService, required this.mountPath, required this.title});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  final List<String> _pathStack = [];
  List<AListFile> _files = [];
  bool _loading = true;
  final Set<String> _selected = {};

  String get _currentPath {
    final base = widget.mountPath.endsWith('/') ? widget.mountPath.substring(0, widget.mountPath.length - 1) : widget.mountPath;
    return _pathStack.isEmpty ? base : '$base/${_pathStack.join('/')}';
  }

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      final client = AListApiClient(widget.alistService);
      final files = await client.listFiles(_currentPath);
      if (mounted) setState(() => _files = files);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadFile(AListFile file) async {
    try {
      final client = AListApiClient(widget.alistService);
      final url = await client.getDownloadUrl('$_currentPath/${file.name}');
      if (url.isEmpty) throw Exception('无法获取下载链接');
      final downloadService = context.read<DownloadService>();
      await downloadService.addTask(url: url, fileName: file.name);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加下载: ${file.name}'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除选中的 ${_selected.length} 项？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final client = AListApiClient(widget.alistService);
      await client.removeFiles([_currentPath], _selected.toList());
      setState(() {
        _files.removeWhere((f) => _selected.contains(f.name));
        _selected.clear();
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: '文件夹名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('创建')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final client = AListApiClient(widget.alistService);
      await client.makeDir('$_currentPath/$name');
      _loadFiles();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectMode = _selected.isNotEmpty;
    return WillPopScope(
      onWillPop: () async {
        if (selectMode) { setState(() => _selected.clear()); return false; }
        if (_pathStack.isNotEmpty) { setState(() => _pathStack.removeLast()); _loadFiles(); return false; }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(selectMode ? '已选 ${_selected.length} 项' : widget.title),
          actions: [
            if (!selectMode) IconButton(icon: const Icon(Icons.create_new_folder), onPressed: _createFolder),
            if (!selectMode) IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFiles),
            if (selectMode) IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: _deleteSelected),
            if (selectMode) IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selected.clear())),
          ],
        ),
        body: Column(
          children: [
            if (_pathStack.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text('${widget.mountPath}/${_pathStack.join('/')}', style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _files.isEmpty
                      ? Center(child: Text('暂无文件', style: TextStyle(color: Colors.grey[600])))
                      : ListView.builder(
                          itemCount: _files.length,
                          itemBuilder: (context, index) {
                            final file = _files[index];
                            final selected = _selected.contains(file.name);
                            return ListTile(
                              leading: Icon(file.isDir ? Icons.folder : Icons.insert_drive_file,
                                  color: file.isDir ? Colors.orange : Colors.blue, size: 28),
                              title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(file.isDir ? '文件夹' : FormatUtils.fileSize(file.size),
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                              trailing: selected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                              selected: selected,
                              onTap: () => selectMode
                                  ? setState(() => _selected.contains(file.name) ? _selected.remove(file.name) : _selected.add(file.name))
                                  : file.isDir
                                      ? setState(() { _pathStack.add(file.name); _loadFiles(); })
                                      : _downloadFile(file),
                              onLongPress: () => setState(() {
                                _selected.contains(file.name) ? _selected.remove(file.name) : _selected.add(file.name);
                              }),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
