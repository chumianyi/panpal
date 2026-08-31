import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clipboard/clipboard.dart';
import '../services/download_service.dart';
import '../services/local_parser_service.dart';
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

  final LocalParserService _parser = LocalParserService();

  @override
  void dispose() {
    _urlController.dispose();
    _passwordController.dispose();
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
      final result = await _parser.parse(
        url,
        password: _passwordController.text.isEmpty ? null : _passwordController.text,
      );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _parsing = false);
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
      body: SingleChildScrollView(
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
            Text('支持解析：蓝奏云、123云盘等分享链接（本地解析器，无需第三方API）',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
