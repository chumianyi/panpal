import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/cloud_file.dart';
import '../models/drive_account.dart';
import '../providers/base_provider.dart';
import '../providers/drive_provider_factory.dart';
import '../services/credential_storage.dart';
import '../services/download_service.dart';
import '../utils/format_utils.dart';
import '../widgets/file_tile.dart';

class FileManagerScreen extends StatefulWidget {
  final DriveAccount account;
  const FileManagerScreen({super.key, required this.account});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  late BaseDriveProvider _provider;
  final List<CloudFile> _files = [];
  final Set<String> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _currentPath = '/';
  String? _currentFileId;
  bool _loading = true;
  bool _searchMode = false;
  String _sortBy = 'time';
  bool _sortDesc = true;

  @override
  void initState() {
    super.initState();
    _initProvider();
  }

  Future<void> _initProvider() async {
    _provider = DriveProviderFactory.create(widget.account.type);
    final storage = context.read<CredentialStorage>();
    final credential = await storage.getCredential(widget.account.id);
    if (credential != null) {
      await _provider.parseCredential(credential);
    }
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      final files = await _provider.listFiles(path: _currentPath, fileId: _currentFileId);
      _sortFiles(files);
      setState(() {
        _files.clear();
        _files.addAll(files);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e')));
    }
  }

  void _sortFiles(List<CloudFile> files) {
    files.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      int cmp;
      switch (_sortBy) {
        case 'name':
          cmp = a.name.compareTo(b.name);
          break;
        case 'size':
          cmp = a.size.compareTo(b.size);
          break;
        case 'time':
        default:
          cmp = (a.modifiedAt ?? DateTime(2000)).compareTo(b.modifiedAt ?? DateTime(2000));
      }
      return _sortDesc ? -cmp : cmp;
    });
  }

  Future<void> _search(String keyword) async {
    if (keyword.isEmpty) {
      _loadFiles();
      return;
    }
    setState(() => _loading = true);
    final results = await _provider.searchFiles(keyword, path: _currentPath);
    setState(() {
      _files.clear();
      _files.addAll(results);
      _loading = false;
    });
  }

  void _navigateTo(CloudFile file) {
    if (!file.isDir) return;
    setState(() {
      _currentPath = file.path.endsWith('/') ? '${file.path}${file.name}' : '${file.path}/${file.name}';
      _currentFileId = file.fileId;
      _selectedIds.clear();
    });
    _loadFiles();
  }

  Future<bool> _onBackPressed() async {
    if (_selectedIds.isNotEmpty) {
      setState(() => _selectedIds.clear());
      return false;
    }
    if (_searchMode) {
      setState(() {
        _searchMode = false;
        _searchController.clear();
      });
      _loadFiles();
      return false;
    }
    if (_currentPath != '/') {
      final parts = _currentPath.split('/')..removeWhere((p) => p.isEmpty);
      parts.removeLast();
      setState(() {
        _currentPath = '/${parts.join('/')}';
        if (_currentPath == '/') _currentFileId = null;
      });
      _loadFiles();
      return false;
    }
    return true;
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _downloadFile(CloudFile file) async {
    if (file.isDir) return;
    final downloadService = context.read<DownloadService>();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('正在获取下载链接: ${file.name}')));
    try {
      final url = await _provider.getDownloadUrl(file);
      if (url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('获取下载链接失败'), backgroundColor: Colors.red));
        return;
      }
      await downloadService.addTask(
        url: url,
        fileName: file.name,
        headers: {'User-Agent': _provider.desktopUA},
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加下载: ${file.name}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _shareFile(CloudFile file) async {
    showDialog(
      context: context,
      builder: (ctx) => _ShareDialog(
        file: file,
        onShare: (password, expireDays) async {
          Navigator.pop(ctx);
          showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
          try {
            final result = await _provider.shareFile(file, password: password, expireDays: expireDays);
            if (mounted) Navigator.pop(context);
            _showShareResult(result.url, result.password);
          } catch (e) {
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分享失败: $e'), backgroundColor: Colors.red));
            }
          }
        },
      ),
    );
  }

  void _showShareResult(String url, String? password) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('分享成功'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('分享链接:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SelectableText(url, style: const TextStyle(color: Colors.blue)),
            if (password != null && password.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('提取码: $password', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: password != null && password.isNotEmpty ? '$url 提取码: $password' : url));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制链接'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final selectedFiles = _files.where((f) => _selectedIds.contains(f.id)).toList();
    if (selectedFiles.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定要删除选中的 ${selectedFiles.length} 个项目吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirm != true) return;
    final success = await _provider.deleteFiles(selectedFiles);
    if (success) {
      setState(() {
        _files.removeWhere((f) => _selectedIds.contains(f.id));
        _selectedIds.clear();
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除成功')));
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除失败'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSelectMode = _selectedIds.isNotEmpty;
    return WillPopScope(
      onWillPop: _onBackPressed,
      child: Scaffold(
        appBar: AppBar(
          title: isSelectMode
              ? Text('已选 ${_selectedIds.length} 项')
              : _searchMode
                  ? TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: '搜索文件...', border: InputBorder.none),
                      onSubmitted: _search,
                    )
                  : Text(widget.account.type.label),
          actions: [
            if (!isSelectMode && !_searchMode)
              IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => _searchMode = true)),
            if (!isSelectMode && !_searchMode)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'name' || v == 'size' || v == 'time') {
                    setState(() {
                      if (_sortBy == v) {
                        _sortDesc = !_sortDesc;
                      } else {
                        _sortBy = v;
                        _sortDesc = true;
                      }
                    });
                    _sortFiles(_files);
                    setState(() {});
                  } else if (v == 'newFolder') {
                    _createFolder();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'name', child: Text('按名称${_sortBy == 'name' ? (_sortDesc ? ' ↓' : ' ↑') : ''}')),
                  PopupMenuItem(value: 'size', child: Text('按大小${_sortBy == 'size' ? (_sortDesc ? ' ↓' : ' ↑') : ''}')),
                  PopupMenuItem(value: 'time', child: Text('按时间${_sortBy == 'time' ? (_sortDesc ? ' ↓' : ' ↑') : ''}')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'newFolder', child: Text('新建文件夹')),
                ],
              ),
            if (isSelectMode) ...[
              IconButton(icon: const Icon(Icons.delete), onPressed: _deleteSelected),
              IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedIds.clear())),
            ],
          ],
        ),
        body: Column(
          children: [
            if (_currentPath != '/')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text(_currentPath, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
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
                            return FileTile(
                              file: file,
                              selected: _selectedIds.contains(file.id),
                              selectMode: isSelectMode,
                              onTap: () => isSelectMode
                                  ? _toggleSelect(file.id)
                                  : (file.isDir ? _navigateTo(file) : _showFileOptions(file)),
                              onLongPress: () => _toggleSelect(file.id),
                              onDownload: () => _downloadFile(file),
                              onShare: () => _shareFile(file),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFileOptions(CloudFile file) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: const Icon(Icons.download),
                title: const Text('下载'),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadFile(file);
                }),
            ListTile(
                leading: const Icon(Icons.share),
                title: const Text('分享'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareFile(file);
                }),
            ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('删除'),
                onTap: () {
                  Navigator.pop(ctx);
                  _provider.deleteFiles([file]).then((_) => _loadFiles());
                }),
          ],
        ),
      ),
    );
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '文件夹名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('创建')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await _provider.createFolder(_currentPath, name);
      _loadFiles();
    }
  }
}

class _ShareDialog extends StatefulWidget {
  final CloudFile file;
  final Function(String?, int?) onShare;
  const _ShareDialog({required this.file, required this.onShare});

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  final TextEditingController _pwdController = TextEditingController();
  int _expireDays = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('分享设置'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pwdController,
            decoration: const InputDecoration(labelText: '提取码（留空则无）', hintText: '4位数字或字母'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            value: _expireDays,
            decoration: const InputDecoration(labelText: '有效期'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('永久')),
              DropdownMenuItem(value: 1, child: Text('1天')),
              DropdownMenuItem(value: 7, child: Text('7天')),
              DropdownMenuItem(value: 30, child: Text('30天')),
            ],
            onChanged: (v) => setState(() => _expireDays = v ?? 0),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
            onPressed: () => widget.onShare(_pwdController.text.isEmpty ? null : _pwdController.text, _expireDays),
            child: const Text('分享')),
      ],
    );
  }
}
