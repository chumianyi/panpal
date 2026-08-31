import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../models/cloud_file.dart';

class ParseResult {
  final String fileName;
  final int fileSize;
  final String downloadUrl;
  final String sourceUrl;
  final String? password;

  ParseResult({
    required this.fileName,
    required this.fileSize,
    required this.downloadUrl,
    required this.sourceUrl,
    this.password,
  });
}

class LocalParserService {
  final Dio _dio = Dio();

  LocalParserService() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
  }

  Future<ParseResult> parse(String url, {String? password}) async {
    final lower = url.toLowerCase();

    if (lower.contains('lanzou') || lower.contains('lanzoui') || lower.contains('woozooo')) {
      return _parseLanzou(url, password);
    }
    if (lower.contains('123pan') || lower.contains('123云盘')) {
      return _parse123Pan(url, password);
    }
    if (lower.contains('pan.baidu') || lower.contains('baidu.com')) {
      return _parseBaidu(url, password);
    }
    if (lower.contains('alipan') || lower.contains('aliyundrive')) {
      return _parseAliyun(url, password);
    }
    if (lower.contains('pan.quark') || lower.contains('quark.cn')) {
      return _parseQuark(url, password);
    }

    // Generic fallback: try to extract from page
    return _parseGeneric(url);
  }

  // ========== 蓝奏云解析 ==========
  Future<ParseResult> _parseLanzou(String url, String? password) async {
    try {
      // Step 1: Fetch share page
      final resp = await _dio.get(url,
          options: Options(headers: {
            'User-Agent': _dio.options.headers['User-Agent'],
            'Accept': 'text/html,application/xhtml+xml',
          }));
      String html = resp.data.toString();

      // Check if password required
      if (html.contains('pwd') || html.contains('输入密码') || html.contains('passwd')) {
        if (password == null || password.isEmpty) {
          throw Exception('该链接需要提取码，请输入密码');
        }
        // Submit password
        final signMatch = RegExp(r'name="sign"\s+value="([^"]+)"').firstMatch(html);
        final sign = signMatch?.group(1) ?? '';
        final postUrl = url.contains('?') ? url : '$url?';
        final pwdResp = await _dio.post(
          url,
          data: {'pwd': password, 'sign': sign},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {'User-Agent': _dio.options.headers['User-Agent']},
          ),
        );
        html = pwdResp.data.toString();
      }

      // Extract file name
      String fileName = '未知文件';
      final nameMatch = RegExp(r'<title>([^<]+)</title>').firstMatch(html);
      if (nameMatch != null) {
        fileName = nameMatch.group(1)!.replaceAll(RegExp(r'[-_]\s*蓝奏云.*$'), '').trim();
      }
      final fnMatch = RegExp(r'''filename[=:]\s*["']?([^"'<>\s]+)''', caseSensitive: false).firstMatch(html);
      if (fnMatch != null) fileName = fnMatch.group(1)!;

      // Extract file size
      int fileSize = 0;
      final sizeMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(KB|MB|GB|TB|B)', caseSensitive: false).firstMatch(html);
      if (sizeMatch != null) {
        fileSize = _parseSize(sizeMatch.group(1)!, sizeMatch.group(2)!);
      }

      // Extract iframe or direct download URL
      String? downloadUrl;

      // Try iframe src
      final iframeMatch = RegExp(r'<iframe[^>]+src="([^"]+)"', caseSensitive: false).firstMatch(html);
      if (iframeMatch != null) {
        var iframeSrc = iframeMatch.group(1)!;
        if (iframeSrc.startsWith('/')) {
          final uri = Uri.parse(url);
          iframeSrc = '${uri.scheme}://${uri.host}$iframeSrc';
        }
        // Fetch iframe page
        final iframeResp = await _dio.get(iframeSrc,
            options: Options(headers: {'User-Agent': _dio.options.headers['User-Agent']}));
        final iframeHtml = iframeResp.data.toString();

        // Extract download URL from iframe
        final dlMatch = RegExp(r'''(?:url|src|href)\s*[=:]\s*["'](https?://[^"']+)''', caseSensitive: false)
            .firstMatch(iframeHtml);
        if (dlMatch != null) downloadUrl = dlMatch.group(1);

        // Try to find the ajaxdata / post data for download
        final ajaxMatch = RegExp(r'''ajaxdata\s*=\s*['"]([^'"]+)['"]''').firstMatch(iframeHtml);
        if (ajaxMatch != null && downloadUrl == null) {
          // Need to POST to get download URL
          final postData = ajaxMatch.group(1)!;
          final actionMatch = RegExp(r'''data\s*:\s*['"]([^'"]+)['"]''').firstMatch(iframeHtml);
          try {
            final postResp = await _dio.post(
              'https://www.lanzou.com/ajaxm.php',
              data: postData,
              options: Options(
                contentType: Headers.formUrlEncodedContentType,
                headers: {
                  'User-Agent': _dio.options.headers['User-Agent'],
                  'Referer': iframeSrc,
                },
              ),
            );
            final postDataJson = postResp.data is String ? jsonDecode(postResp.data) : postResp.data;
            if (postDataJson['dom'] != null && postDataJson['url'] != null) {
              downloadUrl = '${postDataJson['dom']}/file/${postDataJson['url']}';
            }
          } catch (_) {}
        }
      }

      // Try direct URL patterns in main html
      downloadUrl ??= _extractUrl(html);

      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception('未能解析出下载链接');
      }

      return ParseResult(
        fileName: fileName,
        fileSize: fileSize,
        downloadUrl: downloadUrl,
        sourceUrl: url,
        password: password,
      );
    } catch (e) {
      throw Exception('蓝奏云解析失败: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ========== 123云盘解析 ==========
  Future<ParseResult> _parse123Pan(String url, String? password) async {
    try {
      // Extract share key from URL
      final shareKeyMatch = RegExp(r'/s/([A-Za-z0-9]+)').firstMatch(url);
      if (shareKeyMatch == null) {
        throw Exception('无法识别123云盘分享链接');
      }
      final shareKey = shareKeyMatch.group(1)!;

      // Call 123pan share info API
      final resp = await _dio.post(
        'https://www.123pan.com/b/api/share/get',
        data: jsonEncode({'ShareKey': shareKey, 'SharePwd': password ?? ''}),
        options: Options(headers: {
          'Content-Type': 'application/json',
          'App-Version': '3',
          'platform': 'web',
          'Origin': 'https://www.123pan.com',
          'Referer': 'https://www.123pan.com/',
          'User-Agent': _dio.options.headers['User-Agent'],
        }),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      if (data['code'] != 0) {
        throw Exception(data['message'] ?? '解析失败');
      }

      final info = data['data'] ?? {};
      final fileName = info['FileName'] ?? info['Name'] ?? '123云盘文件';
      final fileSize = info['Size'] ?? 0;

      // Get download URL
      final fileId = info['FileId']?.toString() ?? '';
      final shareId = info['ShareId']?.toString() ?? '';

      String? downloadUrl;
      try {
        final dlResp = await _dio.post(
          'https://www.123pan.com/b/api/share/download/info',
          data: jsonEncode({
            'ShareKey': shareKey,
            'SharePwd': password ?? '',
            'FileId': int.tryParse(fileId) ?? 0,
            'ShareId': int.tryParse(shareId) ?? 0,
          }),
          options: Options(headers: {
            'Content-Type': 'application/json',
            'App-Version': '3',
            'platform': 'web',
            'Origin': 'https://www.123pan.com',
            'Referer': 'https://www.123pan.com/',
            'User-Agent': _dio.options.headers['User-Agent'],
          }),
        );
        final dlData = dlResp.data is String ? jsonDecode(dlResp.data) : dlResp.data;
        downloadUrl = dlData['data']?['DownloadUrl'] ?? dlData['data']?['download_url'];
      } catch (_) {}

      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception('未能获取下载链接');
      }

      return ParseResult(
        fileName: fileName,
        fileSize: (fileSize is num) ? fileSize.toInt() : 0,
        downloadUrl: downloadUrl,
        sourceUrl: url,
        password: password,
      );
    } catch (e) {
      throw Exception('123云盘解析失败: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ========== 百度网盘解析 ==========
  Future<ParseResult> _parseBaidu(String url, String? password) async {
    try {
      // Fetch share page to get surl and uk
      final resp = await _dio.get(url,
          options: Options(headers: {
            'User-Agent': _dio.options.headers['User-Agent'],
            'Accept': 'text/html',
          }));
      final html = resp.data.toString();

      // Extract surl
      final surlMatch = RegExp(r'surl=([A-Za-z0-9_-]+)').firstMatch(html);
      final surl = surlMatch?.group(1) ?? '';

      // Extract uk
      final ukMatch = RegExp(r'uk["\s:=]+(\d+)').firstMatch(html);
      final uk = ukMatch?.group(1) ?? '';

      // Extract shareid
      final shareIdMatch = RegExp(r'shareid["\s:=]+(\d+)').firstMatch(html);
      final shareId = shareIdMatch?.group(1) ?? '';

      if (surl.isEmpty) {
        throw Exception('无法识别百度网盘分享链接');
      }

      // For baidu, we need to verify password and get the file list
      // This requires the baidu API with access_token, which we don't have for anonymous parsing
      // As a fallback, extract info from page
      String fileName = '百度网盘文件';
      int fileSize = 0;

      final titleMatch = RegExp(r'<title>([^<]+)</title>').firstMatch(html);
      if (titleMatch != null) {
        fileName = titleMatch.group(1)!.replaceAll(RegExp(r'[-_]\s*百度网盘.*$'), '').trim();
      }

      // Try to find file name in page data
      final fnMatch = RegExp(r'"server_filename"\s*:\s*"([^"]+)"').firstMatch(html);
      if (fnMatch != null) fileName = fnMatch.group(1)!;

      final fsMatch = RegExp(r'"size"\s*:\s*(\d+)').firstMatch(html);
      if (fsMatch != null) fileSize = int.tryParse(fsMatch.group(1)!) ?? 0;

      // Baidu anonymous download requires redirect, we'll provide the share page
      // In practice, baidu requires login for downloads
      throw Exception('百度网盘分享需要登录后才能下载，请在首页绑定百度网盘账号');
    } catch (e) {
      if (e.toString().contains('需要登录')) rethrow;
      throw Exception('百度网盘解析失败: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ========== 阿里云盘解析 ==========
  Future<ParseResult> _parseAliyun(String url, String? password) async {
    try {
      // Extract share ID
      final shareIdMatch = RegExp(r'/s/([A-Za-z0-9]+)').firstMatch(url);
      if (shareIdMatch == null) {
        throw Exception('无法识别阿里云盘分享链接');
      }
      final shareId = shareIdMatch.group(1)!;

      // Call aliyun share API
      final resp = await _dio.post(
        'https://api.aliyundrive.com/adrive/v1.0/openShare/getShareInfo',
        data: jsonEncode({'share_id': shareId, 'share_pwd': password ?? ''}),
        options: Options(headers: {
          'Content-Type': 'application/json',
          'User-Agent': _dio.options.headers['User-Agent'],
        }),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;

      final fileName = data['name'] ?? data['file_name'] ?? '阿里云盘文件';
      final fileSize = data['size'] ?? 0;

      // Get download URL
      String? downloadUrl;
      final fileId = data['file_id'] ?? data['file_list']?[0]?['file_id'];
      if (fileId != null) {
        try {
          final dlResp = await _dio.post(
            'https://api.aliyundrive.com/adrive/v1.0/openShare/getDownloadUrl',
            data: jsonEncode({'share_id': shareId, 'file_id': fileId}),
            options: Options(headers: {
              'Content-Type': 'application/json',
              'User-Agent': _dio.options.headers['User-Agent'],
            }),
          );
          final dlData = dlResp.data is String ? jsonDecode(dlResp.data) : dlResp.data;
          downloadUrl = dlData['url'] ?? dlData['download_url'];
        } catch (_) {}
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception('阿里云盘分享需要登录后下载，请绑定阿里云盘账号');
      }

      return ParseResult(
        fileName: fileName,
        fileSize: (fileSize is num) ? fileSize.toInt() : 0,
        downloadUrl: downloadUrl,
        sourceUrl: url,
        password: password,
      );
    } catch (e) {
      if (e.toString().contains('需要登录')) rethrow;
      throw Exception('阿里云盘解析失败: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ========== 夸克网盘解析 ==========
  Future<ParseResult> _parseQuark(String url, String? password) async {
    try {
      final resp = await _dio.get(url,
          options: Options(headers: {
            'User-Agent': _dio.options.headers['User-Agent'],
            'Accept': 'text/html',
          }));
      final html = resp.data.toString();

      String fileName = '夸克网盘文件';
      final titleMatch = RegExp(r'<title>([^<]+)</title>').firstMatch(html);
      if (titleMatch != null) {
        fileName = titleMatch.group(1)!.replaceAll(RegExp(r'[-_]\s*夸克.*$'), '').trim();
      }

      throw Exception('夸克网盘分享需要登录后下载，请绑定夸克网盘账号');
    } catch (e) {
      if (e.toString().contains('需要登录')) rethrow;
      throw Exception('夸克网盘解析失败: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ========== 通用解析 ==========
  Future<ParseResult> _parseGeneric(String url) async {
    try {
      final resp = await _dio.get(url,
          options: Options(headers: {
            'User-Agent': _dio.options.headers['User-Agent'],
            'Accept': 'text/html,application/xhtml+xml',
          }));
      final html = resp.data.toString();

      String fileName = '未知文件';
      int fileSize = 0;

      final titleMatch = RegExp(r'<title>([^<]+)</title>').firstMatch(html);
      if (titleMatch != null) fileName = titleMatch.group(1)!.trim();

      final sizeMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(KB|MB|GB|TB|B)', caseSensitive: false).firstMatch(html);
      if (sizeMatch != null) {
        fileSize = _parseSize(sizeMatch.group(1)!, sizeMatch.group(2)!);
      }

      final downloadUrl = _extractUrl(html);
      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception('未能从页面中提取下载链接');
      }

      return ParseResult(
        fileName: fileName,
        fileSize: fileSize,
        downloadUrl: downloadUrl,
        sourceUrl: url,
      );
    } catch (e) {
      throw Exception('解析失败: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ========== 工具方法 ==========
  String? _extractUrl(String html) {
    // Look for direct download URLs
    final patterns = [
      RegExp(r'''(?:download_url|downloadUrl|direct_url|directUrl|url)\s*[:=]\s*["'](https?://[^"']+)''', caseSensitive: false),
      RegExp(r'''href\s*=\s*["'](https?://[^"']*(?:download|getfile|downfile)[^"']*)["']''', caseSensitive: false),
      RegExp(r'''(https?://[^\s<>"']+\.(?:zip|rar|7z|apk|exe|mp4|mkv|mp3|flac|pdf|doc|iso|tar|gz))''', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  int _parseSize(String numStr, String unit) {
    final value = double.tryParse(numStr) ?? 0;
    switch (unit.toUpperCase()) {
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
}
