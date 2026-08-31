import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:provider/provider.dart';
import '../models/drive_account.dart';
import '../providers/drive_provider_factory.dart';
import '../services/credential_storage.dart';

class LoginWebViewScreen extends StatefulWidget {
  final DriveType driveType;
  const LoginWebViewScreen({super.key, required this.driveType});

  @override
  State<LoginWebViewScreen> createState() => _LoginWebViewScreenState();
}

class _LoginWebViewScreenState extends State<LoginWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _saving = false;
  double _progress = 0;

  static const String desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(desktopUA)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) => setState(() => _loading = true),
        onProgress: (p) => setState(() => _progress = p / 100),
        onPageFinished: (url) => setState(() => _loading = false),
      ))
      ..loadRequest(Uri.parse(widget.driveType.loginUrl));

    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
    }
  }

  Future<Map<String, dynamic>> _captureCredentials() async {
    // Extract cookies using CookieManager
    final cookieManager = WebViewCookieManager();
    final cookies = await cookieManager.getCookies(Uri.parse(widget.driveType.loginUrl));
    final cookieMap = <String, String>{};
    for (final c in cookies) {
      cookieMap[c.name] = c.value;
    }

    // Also try document.cookie as fallback
    try {
      final docCookie = await _controller.runJavaScriptReturningResult('document.cookie') as String? ?? '';
      for (final pair in docCookie.split(';')) {
        final idx = pair.indexOf('=');
        if (idx > 0) {
          final key = pair.substring(0, idx).trim();
          final value = pair.substring(idx + 1).trim();
          if (key.isNotEmpty && !cookieMap.containsKey(key)) {
            cookieMap[key] = value;
          }
        }
      }
    } catch (_) {}

    // Try to get token from localStorage
    String? accessToken;
    String? refreshToken;
    try {
      final ls = await _controller.runJavaScriptReturningResult('JSON.stringify(localStorage)') as String?;
      if (ls != null && ls.isNotEmpty && ls != '{}') {
        final parsed = jsonDecode(ls.replaceAll('\\', ''));
        accessToken = parsed['access_token'] ?? parsed['token'] ?? parsed['accessToken'];
        refreshToken = parsed['refresh_token'] ?? parsed['refreshToken'];
      }
    } catch (_) {}

    final url = await _controller.currentUrl() ?? '';
    return {
      'cookies': cookieMap,
      'cookie': cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; '),
      'url': url,
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'userAgent': desktopUA,
      'capturedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _saveCredentials() async {
    setState(() => _saving = true);
    try {
      final credential = await _captureCredentials();
      final provider = DriveProviderFactory.create(widget.driveType);
      final account = await provider.parseCredential(credential);
      if (account != null) {
        if (!mounted) return;
        await context.read<CredentialStorage>().addAccount(account, credential);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.driveType.label} 登录成功'), backgroundColor: Colors.green),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未检测到登录信息，请先完成登录'), backgroundColor: Colors.orange),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('登录 ${widget.driveType.label}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _controller.reload()),
          TextButton(
            onPressed: _saving ? null : _saveCredentials,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存凭证', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: LinearProgressIndicator(value: _loading ? _progress : 0, minHeight: 2),
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
