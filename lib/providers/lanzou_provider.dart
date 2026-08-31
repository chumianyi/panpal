import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/cloud_file.dart';
import '../models/drive_account.dart';
import 'base_provider.dart';

class LanzouProvider extends BaseDriveProvider {
  @override
  DriveType get type => DriveType.lanzou;

  @override
  String get loginUrl => 'https://www.lanzou.com/';

  final Dio _dio = Dio();

  LanzouProvider() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers['User-Agent'] = desktopUA;
  }

  @override
  Future<DriveAccount?> parseCredential(Map<String, dynamic> cred) async {
    credential = cred;
    return DriveAccount(
      id: 'lanzou_${DateTime.now().millisecondsSinceEpoch}',
      type: DriveType.lanzou,
      displayName: '蓝奏云解析',
      addedAt: DateTime.now(),
      credential: cred,
    );
  }

  @override
  Future<DriveAccount?> parseCookie(String cookieStr) async {
    final cred = {'cookie': cookieStr, 'loginType': 'cookie'};
    return parseCredential(cred);
  }

  @override
  Future<List<CloudFile>> listFiles({String path = '/', String? fileId}) async => [];

  @override
  Future<List<CloudFile>> searchFiles(String keyword, {String path = '/'}) async => [];

  @override
  Future<String> getDownloadUrl(CloudFile file) async => '';

  @override
  Future<ShareResult> shareFile(CloudFile file, {String? password, int? expireDays}) async {
    throw Exception('蓝奏云不支持分享');
  }

  @override
  Future<bool> deleteFiles(List<CloudFile> files) async => false;

  @override
  Future<bool> createFolder(String path, String name) async => false;

  @override
  Future<StorageInfo> getStorageInfo() async => const StorageInfo();

  @override
  Future<void> logout() async {
    credential.clear();
  }

  Future<ParseResult> parseShareUrl(String url, {String? password}) async {
    try {
      // Normalize URL
      var shareUrl = url.trim();
      if (!shareUrl.startsWith('http')) shareUrl = 'https://$shareUrl';

      final resp = await _dio.get(
        shareUrl,
        options: Options(headers: {
          'User-Agent': desktopUA,
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        }),
      );

      final html = resp.data.toString();

      // Extract file name
      final nameMatch = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(html);
      var fileName = nameMatch?.group(1)?.trim() ?? '未知文件';
      fileName = fileName.replaceAll(RegExp(r'[-_]?蓝奏云.*$'), '').trim();

      // Extract file size
      var fileSize = 0;
      final sizeMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(KB|MB|GB|B)', caseSensitive: false).firstMatch(html);
      if (sizeMatch != null) {
        final num = double.parse(sizeMatch.group(1)!);
        final unit = sizeMatch.group(2)!.toUpperCase();
        fileSize = switch (unit) {
          'GB' => (num * 1024 * 1024 * 1024).toInt(),
          'MB' => (num * 1024 * 1024).toInt(),
          'KB' => (num * 1024).toInt(),
          _ => num.toInt(),
        };
      }

      // Extract iframe src for download
      final iframeMatch = RegExp(r'<iframe[^>]*src="([^"]*)"[^>]*name="[^"]*"', dotAll: true).firstMatch(html);
      String? iframeSrc = iframeMatch?.group(1);
      if (iframeSrc != null && iframeSrc.startsWith('/')) {
        final uri = Uri.parse(shareUrl);
        iframeSrc = '${uri.scheme}://${uri.host}$iframeSrc';
      }

      if (iframeSrc == null) {
        // Try alternative: find the download form action
        final formMatch = RegExp(r'action="([^"]*ajaxm\.php[^"]*)"', dotAll: true).firstMatch(html);
        iframeSrc = formMatch?.group(1);
      }

      if (iframeSrc == null) {
        throw Exception('无法解析下载页面');
      }

      // Get the iframe page to find the actual download parameters
      final iframeResp = await _dio.get(
        iframeSrc,
        options: Options(headers: {
          'User-Agent': desktopUA,
          'Referer': shareUrl,
        }),
      );
      final iframeHtml = iframeResp.data.toString();

      // Extract sign and parameters from the iframe
      final signMatch = RegExp(r"var\s+ajaxdata\s*=\s*'([^']*)'", dotAll: true).firstMatch(iframeHtml);
      var ajaxData = signMatch?.group(1) ?? '';

      if (ajaxData.isEmpty) {
        // Try alternative pattern
        final altMatch = RegExp(r'name="(\w+)"\s+value="([^"]*)"', dotAll: true).allMatches(iframeHtml);
        final params = <String, String>{};
        for (final m in altMatch) {
          params[m.group(1)!] = m.group(2)!;
        }
        ajaxData = params.entries.map((e) => '${e.key}=${e.value}').join('&');
      }

      // POST to ajaxm.php to get the download URL
      final host = Uri.parse(shareUrl).host;
      final ajaxUrl = 'https://$host/ajaxm.php';
      final ajaxResp = await _dio.post(
        ajaxUrl,
        data: ajaxData,
        options: Options(headers: {
          'User-Agent': desktopUA,
          'Referer': iframeSrc,
          'Content-Type': 'application/x-www-form-urlencoded',
        }),
      );

      final ajaxDataResp = ajaxResp.data is String ? jsonDecode(ajaxResp.data) : ajaxResp.data;
      final downUrl = ajaxDataResp['url'] as String? ?? '';

      if (downUrl.isEmpty) {
        throw Exception('无法获取真实下载地址');
      }

      return ParseResult(
        fileName: fileName,
        fileSize: fileSize,
        downloadUrl: downUrl,
        sourceUrl: shareUrl,
      );
    } catch (e) {
      throw Exception('蓝奏云解析失败: $e');
    }
  }
}

class ParseResult {
  final String fileName;
  final int fileSize;
  final String downloadUrl;
  final String sourceUrl;

  const ParseResult({
    required this.fileName,
    required this.fileSize,
    required this.downloadUrl,
    required this.sourceUrl,
  });
}
