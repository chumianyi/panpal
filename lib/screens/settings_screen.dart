import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../services/credential_storage.dart';
import '../services/download_service.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeMode currentTheme;
  final ValueChanged<ThemeMode> onThemeChanged;

  const SettingsScreen({super.key, required this.currentTheme, required this.onThemeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _connections;
  late int _concurrentTasks;
  late TextEditingController _pathController;
  String _version = '1.0.0';

  @override
  void initState() {
    super.initState();
    final storage = context.read<CredentialStorage>();
    _connections = storage.defaultConnections;
    _concurrentTasks = storage.maxConcurrentTasks;
    _pathController = TextEditingController(text: storage.downloadPath);
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _version = info.version);
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<CredentialStorage>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _buildSectionHeader('下载设置 (Gopeed 下载器)'),
          ListTile(
            leading: const Icon(Icons.device_hub),
            title: const Text('默认连接数'),
            subtitle: Text('$_connections 连接（16-64）'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: _connections.toDouble(),
                min: 16,
                max: 64,
                divisions: 48,
                label: '$_connections',
                onChanged: (v) => setState(() => _connections = v.toInt()),
                onChangeEnd: (v) {
                  storage.defaultConnections = v.toInt();
                  context.read<DownloadService>().configure(defaultConnections: v.toInt(), maxConcurrentTasks: _concurrentTasks, downloadPath: storage.downloadPath);
                },
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.queue),
            title: const Text('并发任务数'),
            subtitle: Text('最多同时下载 $_concurrentTasks 个'),
            trailing: DropdownButton<int>(
              value: _concurrentTasks,
              items: [1, 2, 3, 5, 8].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
              onChanged: (v) {
                setState(() => _concurrentTasks = v ?? 3);
                storage.maxConcurrentTasks = v ?? 3;
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('下载路径'),
            subtitle: Text(_pathController.text),
            onTap: () => _editDownloadPath(storage),
          ),
          const Divider(),
          _buildSectionHeader('主题设置'),
          RadioListTile<ThemeMode>(
            title: const Text('浅色'),
            value: ThemeMode.light,
            groupValue: widget.currentTheme,
            onChanged: (v) => widget.onThemeChanged(v!),
            secondary: const Icon(Icons.light_mode),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('深色'),
            value: ThemeMode.dark,
            groupValue: widget.currentTheme,
            onChanged: (v) => widget.onThemeChanged(v!),
            secondary: const Icon(Icons.dark_mode),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('跟随系统'),
            value: ThemeMode.system,
            groupValue: widget.currentTheme,
            onChanged: (v) => widget.onThemeChanged(v!),
            secondary: const Icon(Icons.brightness_auto),
          ),
          const Divider(),
          _buildSectionHeader('数据管理'),
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('清除缓存'),
            onTap: () async {
              await storage.clearCache();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('缓存已清除')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('清除所有凭证', style: TextStyle(color: Colors.red)),
            subtitle: const Text('将退出所有已登录的网盘'),
            onTap: () => _showClearCredentialsDialog(storage),
          ),
          const Divider(),
          _buildSectionHeader('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('PanPal'),
            subtitle: Text('版本 $_version · 纯前端多网盘管理工具'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('开源声明'),
            subtitle: const Text('基于 Flutter 构建，集成 Gopeed 下载引擎'),
            onTap: () => showLicensePage(context: context, applicationName: 'PanPal', applicationVersion: _version),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[600])),
    );
  }

  void _editDownloadPath(CredentialStorage storage) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载路径'),
        content: TextField(controller: _pathController, decoration: const InputDecoration(hintText: '/storage/emulated/0/Download/PanPal')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              storage.downloadPath = _pathController.text;
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showClearCredentialsDialog(CredentialStorage storage) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除所有凭证'),
        content: const Text('此操作将退出所有已登录的网盘，并删除所有保存的凭证。此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await storage.clearAllCredentials();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('所有凭证已清除')));
            },
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
  }
}
