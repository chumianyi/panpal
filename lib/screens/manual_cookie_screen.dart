import 'package:flutter/material.dart';
import 'package:clipboard/clipboard.dart';
import 'package:provider/provider.dart';
import '../models/drive_account.dart';
import '../providers/drive_provider_factory.dart';
import '../services/credential_storage.dart';

class ManualCookieScreen extends StatefulWidget {
  final DriveType driveType;
  const ManualCookieScreen({super.key, required this.driveType});

  @override
  State<ManualCookieScreen> createState() => _ManualCookieScreenState();
}

class _ManualCookieScreenState extends State<ManualCookieScreen> {
  final _cookieController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final text = await FlutterClipboard.paste();
      if (text.isNotEmpty) {
        setState(() => _cookieController.text = text);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final cookie = _cookieController.text.trim();
    if (cookie.isEmpty) {
      setState(() => _error = '请输入Cookie');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = DriveProviderFactory.create(widget.driveType);
      final account = await provider.parseCookie(cookie);
      if (account != null) {
        if (!mounted) return;
        final cred = {'cookie': cookie, 'loginType': 'manual_cookie'};
        await context.read<CredentialStorage>().addAccount(account, cred);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.driveType.label} Cookie已保存'), backgroundColor: Colors.green),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() => _error = 'Cookie无效或无法验证，请检查后重试');
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.driveType.label} 手动Cookie')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: widget.driveType.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.cookie, color: widget.driveType.color, size: 40),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text('手动填写Cookie', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('从浏览器登录后复制Cookie粘贴到下方',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]), textAlign: TextAlign.center),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('获取方法', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[700])),
                  const SizedBox(height: 8),
                  Text('1. 在浏览器中打开 ${widget.driveType.loginUrl} 并登录',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Text('2. 按 F12 打开开发者工具 → Application/应用 → Cookies',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Text('3. 复制所有Cookie值，格式如: key1=value1; key2=value2',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _cookieController,
              decoration: InputDecoration(
                labelText: 'Cookie',
                hintText: 'key1=value1; key2=value2; ...',
                prefixIcon: const Icon(Icons.cookie_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste),
                  onPressed: _pasteFromClipboard,
                  tooltip: '粘贴',
                ),
              ),
              maxLines: 5,
              keyboardType: TextInputType.multiline,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _save,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存Cookie', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
