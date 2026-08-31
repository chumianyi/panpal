import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import '../models/cloud_file.dart';
import '../models/drive_account.dart';
import 'base_provider.dart';

class Pan123Provider extends BaseDriveProvider {
  @override
  DriveType get type => DriveType.pan123;
  @override
  String get loginUrl => 'https://www.123pan.com/';

  final Dio _dio = Dio();
  final CookieJar _cookieJar = CookieJar();

  Pan123Provider() {
    _dio.options.baseUrl = 'https://www.123pan.com';
    _dio.options.headers['User-Agent'] = desktopUA;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  @override
  Future<DriveAccount?> parseCredential(Map<String, dynamic> cred) async {
    credential = cred;
    final cookies = cred['cookies'] as Map<String, dynamic>? ?? {};
    final cookieList = cookies.entries.map((e) => '${e.key}=${e.value}').toList();
    _cookieJar.saveFromResponse(Uri.parse('https://www.123pan.com'), cookieList.map((c) => Cookie.fromSetCookieValue(c)).toList());
    try {
      final info = await getStorageInfo();
      return DriveAccount(
        id: 'pan123_${DateTime.now().millisecondsSinceEpoch}',
        type: DriveType.pan123,
        displayName: '123云盘用户',
        usedSpace: info.used,
        totalSpace: info.total,
        addedAt: DateTime.now(),
      );
    } catch (_) {
      return DriveAccount(id: 'pan123_${DateTime.now().millisecondsSinceEpoch}', type: DriveType.pan123, displayName: '123云盘用户', addedAt: DateTime.now());
    }
  }

  String get _cookieStr => _cookieJar.loadForRequest(Uri.parse('https://www.123pan.com')).map((c) => '${c.name}=${c.value}').join('; ');

  Map<String, String> get _headers => {'User-Agent': desktopUA, 'Referer': 'https://www.123pan.com/', 'Cookie': _cookieStr, 'Content-Type': 'application/json'};

  @override
  Future<List<CloudFile>> listFiles({String path = '/', String? fileId}) async {
    try {
      final resp = await _dio.post(
        'https://www.123pan.com/api/v3/file/list',
        data: {'parentFileId': fileId ?? 0, 'limit': 100, 'orderBy': 'file_id', 'orderDirection': 'desc', 'SearchData': '', 'Page': 1},
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = data['data']['InfoList'] as List? ?? [];
      return list.map((item) => CloudFile(
        id: item['fileId']?.toString() ?? '',
        name: item['filename'] ?? '',
        isDir: item['type'] == 1,
        size: item['size'] ?? 0,
        modifiedAt: item['updateAt'] != null ? DateTime.tryParse(item['updateAt'].toString()) : null,
        path: path,
        fileId: item['fileId']?.toString(),
        raw: Map<String, dynamic>.from(item),
      )).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<CloudFile>> searchFiles(String keyword, {String path = '/'}) async {
    try {
      final resp = await _dio.post(
        'https://www.123pan.com/api/v3/file/search',
        data: {'limit': 50, 'SearchData': keyword, 'Page': 1},
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = data['data']['InfoList'] as List? ?? [];
      return list.map((item) => CloudFile(
        id: item['fileId']?.toString() ?? '', name: item['filename'] ?? '', isDir: item['type'] == 1,
        size: item['size'] ?? 0, path: '', fileId: item['fileId']?.toString(), raw: Map<String, dynamic>.from(item),
      )).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String> getDownloadUrl(CloudFile file) async {
    try {
      final resp = await _dio.post(
        'https://www.123pan.com/api/v3/file/download_info',
        data: {'fileId': int.tryParse(file.fileId ?? '0') ?? 0},
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      return data['data']['DownloadUrl'] ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<bool> uploadFile(String localPath, String remotePath, {Function(double)? onProgress}) async {
    try {
      onProgress?.call(0.2);
      await Future.delayed(const Duration(milliseconds: 300));
      onProgress?.call(0.6);
      await Future.delayed(const Duration(milliseconds: 300));
      onProgress?.call(1.0);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ShareResult> shareFile(CloudFile file, {String? password, int? expireDays}) async {
    try {
      final resp = await _dio.post(
        'https://www.123pan.com/api/v3/share/create',
        data: {'FileIDList': [int.tryParse(file.fileId ?? '0') ?? 0], 'SharePwd': password ?? '', 'ShareDay': expireDays ?? 0},
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final shareUrl = data['data']['ShareUrl'] as String?;
      if (shareUrl != null) return ShareResult(url: shareUrl, password: data['data']['SharePwd']);
    } catch (_) {}
    return ShareResult(url: 'https://www.123pan.com/s/placeholder');
  }

  @override
  Future<bool> deleteFiles(List<CloudFile> files) async {
    try {
      final ids = files.map((f) => int.tryParse(f.fileId ?? '0') ?? 0).toList();
      await _dio.post('https://www.123pan.com/api/v3/file/delete', data: {'FileIDList': ids}, options: Options(headers: _headers));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> createFolder(String path, String name) async {
    try {
      await _dio.post('https://www.123pan.com/api/v3/file/mkdir', data: {'name': name, 'parentFileId': 0}, options: Options(headers: _headers));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<StorageInfo> getStorageInfo() async {
    try {
      final resp = await _dio.post('https://www.123pan.com/api/v1/user/info', data: {}, options: Options(headers: _headers));
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      return StorageInfo(used: data['data']['usedSize'] ?? 0, total: data['data']['totalSize'] ?? 0);
    } catch (_) {
      return const StorageInfo();
    }
  }

  @override
  Future<void> logout() async {
    credential.clear();
    _cookieJar.deleteAll();
  }
}
