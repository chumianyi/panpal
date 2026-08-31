import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clipboard/clipboard.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/download_service.dart';
import '../services/parser_service.dart';
import '../services/settings_service.dart';
import '../utils/format_utils.dart';

class ParserScreen extends StatefulWidget {
  const ParserScreen({super.key});

  @override
  State<ParserScreen> createState() => _ParserScreenState();
}

class _ParserScreenState extends State<ParserScreen> {
  final _urlController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _parsing = false;
  ParseResult? _result;
  String? _error;

  // Background WebView for third-party parsing
  WebViewController? _browserController;
  bool _browserReady = false;
  Timer? _browserTimeout;
  Completer<ParseResult>? _browserCompleter;

  static const String _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _initBrowser();
  }

  void _initBrowser() {
    _browserController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_desktopUA)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) => _onBrowserPageFinished(url),
        ),
      )
      ..loadRequest(Uri.parse('about:blank')).then((_) {
        if (mounted) setState(() => _browserReady = true);
      });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _passwordController.dispose();
    _browserTimeout?.cancel();
    _browserController = null;
    super.dispose();
  }

  Future<void> _parse() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '请输入分享链接');
      return;
    }

    setState(() {
      _parsing = true;
      _error = null;
      _result = null;
    });

    try {
      final settings = context.read<SettingsService>();
      if (settings.useBuiltinParser) {
        // Built-in parser (direct HTTP for official APIs)
        final parser = ParserService();
        final result = await parser.parse(
          url,
          password: _passwordController.text.isEmpty ? null : _passwordController.text,
          useBuiltin: true,
        );
        if (mounted) setState(() => _result = result);
      } else {
        // Third-party parser via background WebView
        final apiBase = settings.parserApi;
        final result = await _parseWithBrowser(url, apiBase);
        if (mounted) setState(() => _result = result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<ParseResult> _parseWithBrowser(String shareUrl, String apiBase) async {
    if (_browserController == null) {
      throw Exception('浏览器未初始化');
    }

    final apiUrl = apiBase.endsWith('=') ? '$apiBase$shareUrl' : '$apiBase?url=$shareUrl';
    _browserCompleter = Completer<ParseResult>();

    // Set 30 second timeout
    _browserTimeout?.cancel();
    _browserTimeout = Timer(const Duration(seconds: 30), () {
      if (_browserCompleter != null && !_browserCompleter!.isCompleted) {
        _browserCompleter!.completeError(Exception('解析超时（30秒），请重试'));
      }
    });

    // Load the parser URL in the hidden WebView
    await _browserController!.loadRequest(Uri.parse(apiUrl));

    return _browserCompleter!.future;
  }

  Future<void> _onBrowserPageFinished(String url) async {
    if (_browserCompleter == null || _browserCompleter!.isCompleted) return;
    if (url == 'about:blank') return;

    // Wait additional time for JS to render the result
    await Future.delayed(const Duration(seconds: 4));

    if (_browserCompleter == null || _browserCompleter!.isCompleted) return;

    try {
      final result = await _extractFromBrowser();
      if (_browserCompleter != null && !_browserCompleter!.isCompleted) {
        _browserTimeout?.cancel();
        _browserCompleter!.complete(result);
      }
    } catch (e) {
      if (_browserCompleter != null && !_browserCompleter!.isCompleted) {
        _browserTimeout?.cancel();
        _browserCompleter!.completeError(Exception('解析失败: $e'));
      }
    }
  }

  Future<ParseResult> _extractFromBrowser() async {
    // Run comprehensive JS extraction
    final jsResult = await _browserController!.runJavaScriptReturningResult('''
      (function() {
        var result = {title: document.title, bodyText: '', preText: '', links: [], json: null};

        // Try to find JSON in pre/code tags
        var pres = document.querySelectorAll('pre, code, .json, #json, .result');
        for (var i = 0; i < pres.length; i++) {
          var text = pres[i].textContent.trim();
          if (text.length > 10 && (text.startsWith('{') || text.startsWith('['))) {
            result.preText = text.substring(0, 10000);
            break;
          }
        }

        // Try global JSON variables
        try {
          if (window.__data__) result.json = window.__data__;
          if (window.data) result.json = window.data;
          if (window.result) result.json = window.result;
          if (window.parseResult) result.json = window.parseResult;
        } catch(e) {}

        // Find all download links
        var links = document.querySelectorAll('a');
        for (var i = 0; i < links.length; i++) {
          var a = links[i];
          var href = a.href || '';
          var text = (a.textContent || '').trim();
          if (href && href !== '#' && !href.startsWith('javascript:') && !href.startsWith('mailto:')) {
            if (href.indexOf('download') > -1 || href.indexOf('http') === 0 || text.indexOf('下载') > -1 || text.indexOf('download') > -1) {
              result.links.push({href: href, text: text.substring(0, 200)});
            }
          }
        }

        // Get body text (first 8000 chars)
        result.bodyText = (document.body ? document.body.innerText : '').substring(0, 8000);

        return JSON.stringify(result);
      })()
    ''');

    final raw = jsResult.toString();
    final cleaned = raw.startsWith('"') && raw.endsWith('"')
        ? jsonDecode(raw)
        : raw;

    final data = jsonDecode(cleaned) as Map<String, dynamic>;

    // Try to parse JSON from preText first
    String? fileName;
    int fileSize = 0;
    String? downloadUrl;

    if (data['preText'] != null && data['preText'].toString().isNotEmpty) {
      try {
        final parsed = jsonDecode(data['preText']);
        final extracted = _extractFromJson(parsed);
        fileName ??= extracted['fileName'];
        fileSize = extracted['fileSize'] ?? 0;
        downloadUrl ??= extracted['downloadUrl'];
      } catch (_) {}
    }

    // Try global json
    if (downloadUrl == null && data['json'] != null) {
      try {
        final parsed = data['json'] is String ? jsonDecode(data['json']) : data['json'];
        final extracted = _extractFromJson(parsed);
        fileName ??= extracted['fileName'];
        fileSize = fileSize > 0 ? fileSize : (extracted['fileSize'] ?? 0);
        downloadUrl ??= extracted['downloadUrl'];
      } catch (_) {}
    }

    // Try to find download URL from links
    if (downloadUrl == null && data['links'] != null) {
      final links = data['links'] as List;
      for (final link in links) {
        final href = link['href']?.toString() ?? '';
        final text = link['text']?.toString() ?? '';
        if (href.isNotEmpty &&
            (href.contains('download') ||
                href.contains('getfile') ||
                text.contains('下载') ||
                text.contains('download') ||
                _looksLikeDownloadUrl(href))) {
          downloadUrl = href;
          if (fileName == null && text.isNotEmpty && text.length < 100) {
            fileName = text;
          }
          break;
        }
      }
    }

    // Try to parse from body text
    if (downloadUrl == null && data['bodyText'] != null) {
      final bodyText = data['bodyText'].toString();
      // Look for URL patterns
      final urlMatch = RegExp('https?://[^\\s<>"\']+', caseSensitive: false).firstMatch(bodyText);
      if (urlMatch != null) {
        final candidate = urlMatch.group(0)!;
        if (_looksLikeDownloadUrl(candidate)) {
          downloadUrl = candidate;
        }
      }
      // Look for file name in body text
      if (fileName == null) {
        final nameMatch = RegExp(r'文件名[：:]\s*(.+)', caseSensitive: false).firstMatch(bodyText);
        if (nameMatch != null) fileName = nameMatch.group(1)!.trim();
      }
      // Look for file size
      if (fileSize == 0) {
        final sizeMatch = RegExp(r'(?:文件大小|大小|size)[：:]\s*([\d.]+)\s*(KB|MB|GB|TB|B)', caseSensitive: false)
            .firstMatch(bodyText);
        if (sizeMatch != null) {
          fileSize = _parseSizeString(sizeMatch.group(1)!, sizeMatch.group(2)!);
        }
      }
    }

    // Use page title as fallback file name
    fileName ??= (data['title']?.toString() ?? '未知文件')
        .replaceAll(RegExp(r'[-_]?(网盘|云盘|解析|分享).*$'), '')
        .trim();

    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw Exception('未找到下载链接，请检查链接或稍后重试');
    }

    return ParseResult(
      fileName: fileName,
      fileSize: fileSize,
      downloadUrl: downloadUrl,
      sourceUrl: _urlController.text.trim(),
    );
  }

  Map<String, dynamic> _extractFromJson(dynamic data) {
    String? fileName;
    int fileSize = 0;
    String? downloadUrl;

    if (data is Map) {
      // Navigate common structures
      dynamic inner = data;
      if (data['data'] is Map) inner = data['data'];
      if (data['data'] is List && (data['data'] as List).isNotEmpty) inner = data['data'][0];
      if (data['result'] is Map) inner = data['result'];

      if (inner is Map) {
        fileName = inner['name'] ?? inner['fileName'] ?? inner['filename'] ?? inner['title'];
        fileSize = _parseSizeDynamic(inner['size'] ?? inner['fileSize'] ?? inner['filesize']);
        downloadUrl = inner['url'] ??
            inner['downloadUrl'] ??
            inner['download_url'] ??
            inner['directUrl'] ??
            inner['download'] ??
            inner['link'];
      }

      // Also check top level
      fileName ??= data['name'] ?? data['fileName'];
      downloadUrl ??= data['url'] ?? data['downloadUrl'];
    }

    return {'fileName': fileName, 'fileSize': fileSize, 'downloadUrl': downloadUrl};
  }

  bool _looksLikeDownloadUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.zip') ||
        lower.contains('.rar') ||
        lower.contains('.7z') ||
        lower.contains('.apk') ||
        lower.contains('.exe') ||
        lower.contains('.mp4') ||
        lower.contains('.mkv') ||
        lower.contains('.mp3') ||
        lower.contains('.flac') ||
        lower.contains('.pdf') ||
        lower.contains('.doc') ||
        lower.contains('.iso') ||
        lower.contains('.tar') ||
        lower.contains('.gz') ||
        lower.contains('download') ||
        lower.contains('getfile') ||
        lower.contains('downfile');
  }

  int _parseSizeDynamic(dynamic size) {
    if (size == null) return 0;
    if (size is int) return size;
    if (size is num) return size.toInt();
    if (size is String) {
      final match = RegExp(r'(\d+(?:\.\d+)?)\s*(KB|MB|GB|TB|B)?', caseSensitive: false).firstMatch(size);
      if (match != null) {
        return _parseSizeString(match.group(1)!, match.group(2) ?? 'B');
      }
    }
    return 0;
  }

  int _parseSizeString(String numStr, String unit) {
    final value = double.tryParse(numStr) ?? 0;
    final u = unit.toUpperCase();
    switch (u) {
      case 'TB':
        return (value * 1024 * 1024 * 1024 * 1024).toInt();
      case 'GB':
        return (value * 1024 * 1024 * 1024).toInt();
      case 'MB':
        return (value * 1024 * 1024).toInt();
      case 'KB':
        return (value * 1024).toInt();
      default:
        return value.toInt();
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final text = await FlutterClipboard.paste();
      if (text.isNotEmpty) {
        setState(() => _urlController.text = text);
      }
    } catch (_) {}
  }

  Future<void> _download() async {
    if (_result == null) return;
    final downloadService = context.read<DownloadService>();
    await downloadService.addTask(
      url: _result!.downloadUrl,
      fileName: _result!.fileName,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加下载: ${_result!.fileName}'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('链接解析', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            labelText: '分享链接',
                            hintText: '粘贴网盘分享链接',
                            prefixIcon: const Icon(Icons.link),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.content_paste),
                              onPressed: _pasteFromClipboard,
                              tooltip: '粘贴',
                            ),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: '提取码（可选）',
                            hintText: '如果链接有密码',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _parsing ? null : _parse,
                          icon: _parsing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.search),
                          label: Text(_parsing ? '解析中...' : '解析链接'),
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.red.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.insert_drive_file, color: Colors.blue, size: 28),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_result!.fileName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text(
                                      _result!.fileSize > 0 ? FormatUtils.fileSize(_result!.fileSize) : '大小未知',
                                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text('下载地址', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _result!.downloadUrl,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: Colors.grey[600], fontFamily: 'monospace'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _download,
                                  icon: const Icon(Icons.download),
                                  label: const Text('立即下载'),
                                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  FlutterClipboard.copy(_result!.downloadUrl);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('下载地址已复制')),
                                  );
                                },
                                icon: const Icon(Icons.copy),
                                label: const Text('复制链接'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text('支持解析：蓝奏云、123云盘、百度网盘、阿里云盘、夸克网盘等分享链接',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]), textAlign: TextAlign.center),
              ],
            ),
          ),
          // Hidden background WebView for third-party parsing
          Offstage(
            offstage: true,
            child: SizedBox(
              width: 1,
              height: 1,
              child: _browserController != null
                  ? WebViewWidget(controller: _browserController!)
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}
