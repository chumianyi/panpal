import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drive_account.dart';
import '../providers/drive_provider_factory.dart';
import '../services/credential_storage.dart';

class LoginPasswordScreen extends StatefulWidget {
  final DriveType driveType;
  const LoginPasswordScreen({super.key, required this.driveType});

  @override
  State<LoginPasswordScreen> createState() => _LoginPasswordScreenState();
}

class _LoginPasswordScreenState extends State<LoginPasswordScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入账号和密码');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = DriveProviderFactory.create(widget.driveType);
      final account = await provider.loginWithPassword(username, password);
      if (account != null) {
        if (!mounted) return;
        await context.read<CredentialStorage>().addAccount(account, account.credential);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.driveType.label} 登录成功'), backgroundColor: Colors.green),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() => _error = '登录失败，请检查账号密码');
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
      appBar: AppBar(title: Text('${widget.driveType.label} 登录')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: widget.driveType.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(widget.driveType.icon, color: widget.driveType.color, size: 40),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(widget.driveType.label,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('使用账号密码登录', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '账号',
                hintText: '手机号 / 邮箱 / 用户名',
                prefixIcon: Icon(Icons.person_outline),
              ),
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '请输入密码',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _login,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('登录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回选择其他登录方式'),
            ),
          ],
        ),
      ),
    );
  }
}
