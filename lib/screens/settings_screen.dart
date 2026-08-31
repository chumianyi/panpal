import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../services/credential_storage.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _parserApiController;
  String _version = '2.0.0';

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _parserApiController = TextEditingController(text: settings.parserApi);
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _version = info.version);
  }

  @override
  void dispose() {
    _parserApiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final credStorage = context.watch<CredentialStorage>();
    return Scaffold(
      appBar: AppBar(title: const Text('我的', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        children: [
          _buildSectionHeader('下载设置'),
          ListTile(
            leading: const Icon(Icons.device_hub),
            title: const Text('默认连接数'),
            subtitle: Text('${settings.defaultConnections} 连接（1-64）'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: settings.defaultConnections.toDouble(),
                min: 1,
                max: 64,
                divisions: 63,
                label: '${settings.defaultConnections}',
                onChanged: (v) => settings.defaultConnections = v.toInt(),
              ),
            ),
          ),
          const Divider(),
          _buildSectionHeader('解析设置'),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome),
            title: const Text('使用内置解析'),
            subtitle: const Text('关闭后使用第三方解析API'),
            value: settings.useBuiltinParser,
            onChanged: (v) => settings.useBuiltinParser = v,
          ),
          ListTile(
            leading: const Icon(Icons.api),
            title: const Text('第三方解析API'),
            subtitle: Text(settings.parserApi, maxLines: 1, overflow: TextOverflow.ellipsis),
            enabled: !settings.useBuiltinParser,
            onTap: () => _editParserApi(settings),
          ),
          const Divider(),
          _buildSectionHeader('主题设置'),
          RadioListTile<ThemeMode>(
            title: const Text('浅色'),
            value: ThemeMode.light,
            groupValue: settings.themeMode,
            onChanged: (v) => settings.setThemeMode(v!),
            secondary: const Icon(Icons.light_mode),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('深色'),
            value: ThemeMode.dark,
            groupValue: settings.themeMode,
            onChanged: (v) => settings.setThemeMode(v!),
            secondary: const Icon(Icons.dark_mode),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('跟随系统'),
            value: ThemeMode.system,
            groupValue: settings.themeMode,
            onChanged: (v) => settings.setThemeMode(v!),
            secondary: const Icon(Icons.brightness_auto),
          ),
          const Divider(),
          _buildSectionHeader('数据管理'),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('清除所有凭证', style: TextStyle(color: Colors.red)),
            subtitle: const Text('将退出所有已登录的网盘'),
            onTap: () => _showClearCredentialsDialog(credStorage),
          ),
          const Divider(),
          _buildSectionHeader('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('PanPal'),
            subtitle: Text('版本 $_version · 多网盘管理器'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('开源声明'),
            subtitle: const Text('基于 Flutter 构建，内置多连接下载引擎'),
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

  void _editParserApi(SettingsService settings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('第三方解析API'),
        content: TextField(
          controller: _parserApiController,
          decoration: const InputDecoration(hintText: 'https://zl.390kk.com/parser?url='),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              settings.parserApi = _parserApiController.text;
              Navigator.pop(ctx);
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
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('所有凭证已清除')));
              }
            },
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
  }
}
