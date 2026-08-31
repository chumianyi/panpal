import 'package:flutter/material.dart';
import '../services/alist_service.dart';
import '../services/alist_api_client.dart';

class AddDriveScreen extends StatefulWidget {
  final AListService alistService;
  const AddDriveScreen({super.key, required this.alistService});

  @override
  State<AddDriveScreen> createState() => _AddDriveScreenState();
}

class _AddDriveScreenState extends State<AddDriveScreen> {
  String? _selectedType;
  final _nameController = TextEditingController();
  final _mountController = TextEditingController();
  final Map<String, TextEditingController> _configControllers = {};
  bool _saving = false;

  static const List<Map<String, dynamic>> _driverTypes = [
    {'type': 'BaiduNetdisk', 'name': '百度网盘', 'icon': Icons.cloud, 'color': Colors.blue,
     'fields': [
       {'key': 'refresh_token', 'label': 'Refresh Token', 'hint': '百度网盘 refresh_token'},
       {'key': 'access_token', 'label': 'Access Token', 'hint': '百度网盘 access_token（可选）'},
     ]},
    {'type': 'AliyundriveOpen', 'name': '阿里云盘', 'icon': Icons.cloud_queue, 'color': Colors.deepPurple,
     'fields': [
       {'key': 'refresh_token', 'label': 'Refresh Token', 'hint': '阿里云盘 refresh_token'},
     ]},
    {'type': '123Pan', 'name': '123云盘', 'icon': Icons.folder, 'color': Colors.orange,
     'fields': [
       {'key': 'username', 'label': '账号', 'hint': '123云盘账号'},
       {'key': 'password', 'label': '密码', 'hint': '123云盘密码'},
     ]},
    {'type': 'Quark', 'name': '夸克网盘', 'icon': Icons.all_inclusive, 'color': Colors.teal,
     'fields': [
       {'key': 'cookie', 'label': 'Cookie', 'hint': '夸克网盘 Cookie'},
     ]},
    {'type': 'Cloud189', 'name': '天翼云盘', 'icon': Icons.wifi, 'color': Colors.red,
     'fields': [
       {'key': 'username', 'label': '账号', 'hint': '天翼云盘账号'},
       {'key': 'password', 'label': '密码', 'hint': '天翼云盘密码'},
     ]},
    {'type': 'Lanzou', 'name': '蓝奏云', 'icon': Icons.link, 'color': Colors.blueGrey,
     'fields': [
       {'key': 'cookie', 'label': 'Cookie', 'hint': '蓝奏云 Cookie（可选）'},
     ]},
    {'type': 'Local', 'name': '本地存储（初眠网盘）', 'icon': Icons.sd_storage, 'color': Colors.green,
     'fields': [
       {'key': 'root_folder', 'label': '本地路径', 'hint': '手机本地存储路径'},
       {'key': 'thumbnail', 'label': '生成缩略图', 'hint': 'true/false'},
     ]},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _mountController.dispose();
    for (final c in _configControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectType(String type) {
    setState(() => _selectedType = type);
    final driver = _driverTypes.firstWhere((d) => d['type'] == type);
    _nameController.text = driver['name'] as String;
    _mountController.text = '/${driver['name']}';
    _configControllers.clear();
    for (final field in (driver['fields'] as List)) {
      _configControllers[field['key']] = TextEditingController();
    }
  }

  Future<void> _save() async {
    if (_selectedType == null) return;
    if (_nameController.text.isEmpty || _mountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写名称和挂载路径')));
      return;
    }
    setState(() => _saving = true);
    try {
      final client = AListApiClient(widget.alistService);
      final addition = <String, dynamic>{};
      _configControllers.forEach((key, controller) {
        if (controller.text.isNotEmpty) addition[key] = controller.text;
      });
      await client.createDriver(
        type: _selectedType!,
        name: _nameController.text,
        mountPath: _mountController.text,
        addition: addition,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('添加成功'), backgroundColor: Colors.green));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('添加失败: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedType == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('添加网盘')),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _driverTypes.length,
          itemBuilder: (context, index) {
            final d = _driverTypes[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: (d['color'] as Color).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                  child: Icon(d['icon'] as IconData, color: d['color'] as Color),
                ),
                title: Text(d['name'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text(d['type'] as String, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _selectType(d['type'] as String),
              ),
            );
          },
        ),
      );
    }

    final driver = _driverTypes.firstWhere((d) => d['type'] == _selectedType);
    return Scaffold(
      appBar: AppBar(
        title: Text('添加${driver['name']}'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _selectedType = null)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: '名称', hintText: '显示名称')),
            const SizedBox(height: 12),
            TextField(controller: _mountController, decoration: const InputDecoration(labelText: '挂载路径', hintText: '/网盘名称')),
            const SizedBox(height: 24),
            Text('配置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[700])),
            const SizedBox(height: 8),
            for (final field in (driver['fields'] as List))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _configControllers[field['key']],
                  decoration: InputDecoration(labelText: field['label'], hintText: field['hint']),
                  obscureText: field['key'].toString().contains('password') || field['key'].toString().contains('token'),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
              label: Text(_saving ? '保存中...' : '保存'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
