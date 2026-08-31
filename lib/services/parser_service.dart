import 'dart:convert';
import 'package:dio/dio.dart';
import '../providers/lanzou_provider.dart';

class ParseResult {
  final String fileName;
  final int fileSize;
  final String downloadUrl;
  final String sourceUrl;
  final String? password;

  const ParseResult({
    required this.fileName,
    required this.fileSize,
    required this.downloadUrl,
    required this.sourceUrl,
    this.password,
  });
}

class ParserService {
  final Dio _dio = Dio();

  ParserService() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  }

  Future<ParseResult> parse(String url, {String? password, bool useBuiltin = true, String? customApi}) async {
    if (useBuiltin) {
      return _builtinParse(url, password: password);
    } else if (customApi != null && customApi.isNotEmpty) {
      return _thirdPartyParse(url, customApi);
    }
    return _builtinParse(url, password: password);
  }

  Future<ParseResult> _builtinParse(String url, {String? password}) async {
    var shareUrl = url.trim();
    if (!shareUrl.startsWith('http')) shareUrl = 'https://$shareUrl';

    // Detect drive type
    if (shareUrl.contains('lanzou') || shareUrl.contains('lanzoui')) {
      final lanzou = LanzouProvider();
      final result = await lanzou.parseShareUrl(shareUrl, password: password);
      return ParseResult(
        fileName: result.fileName,
        fileSize: result.fileSize,
        downloadUrl: result.downloadUrl,
        sourceUrl: result.sourceUrl,
        password: password,
      );
    }

    // For other drives, try to fetch the share page and extract download info
    // This is a generic parser that works for simple share pages
    try {
      final resp = await _dio.get(shareUrl,
          options: Options(headers: {
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'zh-CN,zh;q=0.9',
          }));
      final html = resp.data.toString();

      // Extract file name from title
      final nameMatch = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(html);
      var fileName = nameMatch?.group(1)?.trim() ?? '未知文件';
      fileName = fileName.replaceAll(RegExp(r'[-_]?(网盘|云盘|分享).*$'), '').trim();

      // Try to find direct download URL in the page
      final directMatch = RegExp(r'(https?://[^\s"\'<>]+\.(?:zip|rar|7z|apk|exe|mp4|mkv|mp3|flac|pdf|doc|docx|xls|xlsx|ppt|pptx|txt|iso|img|tar|gz)[^\s"\'<>]*)',
              caseSensitive: false)
          .firstMatch(html);
      if (directMatch != null) {
        return ParseResult(
          fileName: fileName,
          fileSize: 0,
          downloadUrl: directMatch.group(1)!,
          sourceUrl: shareUrl,
          password: password,
        );
      }

      // Try to find a download button/link that redirects
      final downloadMatch = RegExp(r'href="([^"]*(?:download|down|getfile|getFile)[^"]*)"', caseSensitive: false)
          .firstMatch(html);
      if (downloadMatch != null) {
        var downUrl = downloadMatch.group(1)!;
        if (downUrl.startsWith('/')) {
          final uri = Uri.parse(shareUrl);
          downUrl = '${uri.scheme}://${uri.host}$downUrl';
        }
        return ParseResult(
          fileName: fileName,
          fileSize: 0,
          downloadUrl: downUrl,
          sourceUrl: shareUrl,
          password: password,
        );
      }

      throw Exception('无法从页面解析下载地址，请尝试使用第三方解析API');
    } catch (e) {
      throw Exception('内置解析失败: $e');
    }
  }

  Future<ParseResult> _thirdPartyParse(String url, String apiBase) async {
    try {
      final apiUrl = apiBase.endsWith('=') ? '$apiBase$url' : '$apiBase?url=$url';
      final resp = await _dio.get(apiUrl).timeout(const Duration(seconds: 30));
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;

      // Common response formats
      String? fileName;
      int fileSize = 0;
      String? downloadUrl;

      // Format 1: {code:0, data:{name, size, url}}
      if (data['data'] is Map) {
        final d = data['data'];
        fileName = d['name'] ?? d['fileName'] ?? d['filename'];
        fileSize = _parseSize(d['size'] ?? d['fileSize']);
        downloadUrl = d['url'] ?? d['downloadUrl'] ?? d['download_url'] ?? d['directUrl'];
      }

      // Format 2: {code:0, msg, data:[{...}]}
      if (downloadUrl == null && data['data'] is List && (data['data'] as List).isNotEmpty) {
        final d = data['data'][0];
        fileName = d['name'] ?? d['fileName'];
        fileSize = _parseSize(d['size']);
        downloadUrl = d['url'] ?? d['downloadUrl'];
      }

      // Format 3: direct fields
      fileName ??= data['name'] ?? data['fileName'];
      downloadUrl ??= data['url'] ?? data['downloadUrl'] ?? data['download_url'];

      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception('第三方API未返回下载地址');
      }

      return ParseResult(
        fileName: fileName ?? '未知文件',
        fileSize: fileSize,
        downloadUrl: downloadUrl,
        sourceUrl: url,
      );
    } catch (e) {
      throw Exception('第三方解析失败: $e');
    }
  }

  int _parseSize(dynamic size) {
    if (size == null) return 0;
    if (size is int) return size;
    if (size is num) return size.toInt();
    final str = size.toString();
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*(KB|MB|GB|TB|B)?', caseSensitive: false).firstMatch(str);
    if (match == null) return 0;
    final num = double.parse(match.group(1)!);
    final unit = (match.group(2) ?? 'B').toUpperCase();
    return switch (unit) {
      'TB' => (num * 1024 * 1024 * 1024 * 1024).toInt(),
      'GB' => (num * 1024 * 1024 * 1024).toInt(),
      'MB' => (num * 1024 * 1024).toInt(),
      'KB' => (num * 1024).toInt(),
      _ => num.toInt(),
    };
  }
}
