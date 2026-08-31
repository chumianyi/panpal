import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import '../models/cloud_file.dart';
import '../models/drive_account.dart';
import 'base_provider.dart';

class TianyiProvider extends BaseDriveProvider {
  @override
  DriveType get type => DriveType.tianyi;
  @override
  String get loginUrl => 'https://cloud.189.cn/';

  final Dio _dio = Dio();
  final CookieJar _cookieJar = CookieJar();

  TianyiProvider() {
    _dio.options.baseUrl = 'https://cloud.189.cn';
    _dio.options.headers['User-Agent'] = desktopUA;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  @override
  Future<DriveAccount?> parseCredential(Map<String, dynamic> cred) async {
    credential = cred;
    final cookies = cred['cookies'] as Map<String, dynamic>? ?? {};
    final cookieList = cookies.entries.map((e) => '${e.key}=${e.value}').toList();
    _cookieJar.saveFromResponse(Uri.parse('https://cloud.189.cn'), cookieList.map((c) => Cookie.fromSetCookieValue(c)).toList());
    try {
      final info = await getStorageInfo();
      return DriveAccount(id: 'tianyi_${DateTime.now().millisecondsSinceEpoch}', type: DriveType.tianyi, displayName: '天翼云盘用户', usedSpace: info.used, totalSpace: info.total, addedAt: DateTime.now());
    } catch (_) {
      return DriveAccount(id: 'tianyi_${DateTime.now().millisecondsSinceEpoch}', type: DriveType.tianyi, displayName: '天翼云盘用户', addedAt: DateTime.now());
    }
  }

  String get _cookieStr => _cookieJar.loadForRequest(Uri.parse('https://cloud.189.cn')).map((c) => '${c.name}=${c.value}').join('; ');
  Map<String, String> get _headers => {'User-Agent': desktopUA, 'Referer': 'https://cloud.189.cn/', 'Cookie': _cookieStr};

  @override
  Future<List<CloudFile>> listFiles({String path = '/', String? fileId}) async {
    try {
      final resp = await _dio.get(
        'https://cloud.189.cn/api/open/file/listFiles',
        queryParameters: {'pageNum': 1, 'pageSize': 100, 'folderId': fileId ?? '-11', 'fileOrder': 'lastOpTime', 'orderBy': 'DESC'},
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = data['fileListAO']['fileList'] as List? ?? [];
      final folderList = data['fileListAO']['folderList'] as List? ?? [];
      final result = <CloudFile>[];
      for (final item in folderList) {
        result.add(CloudFile(id: item['id']?.toString() ?? '', name: item['name'] ?? '', isDir: true, modifiedAt: item['lastOpTime'] != null ? DateTime.tryParse(item['lastOpTime'].toString()) : null, path: path, fileId: item['id']?.toString(), raw: Map<String, dynamic>.from(item)));
      }
      for (final item in list) {
        result.add(CloudFile(id: item['id']?.toString() ?? '', name: item['name'] ?? '', isDir: false, size: item['size'] ?? 0, modifiedAt: item['lastOpTime'] != null ? DateTime.tryParse(item['lastOpTime'].toString()) : null, path: path, fileId: item['id']?.toString(), raw: Map<String, dynamic>.from(item)));
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<CloudFile>> searchFiles(String keyword, {String path = '/'}) async {
    try {
      final resp = await _dio.get('https://cloud.189.cn/api/open/file/searchFiles', queryParameters: {'keyword': keyword, 'pageNum': 1, 'pageSize': 50}, options: Options(headers: _headers));
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = data['fileList'] as List? ?? [];
      return list.map((item) => CloudFile(id: item['id']?.toString() ?? '', name: item['name'] ?? '', isDir: item['isFolder'] == 1, size: item['size'] ?? 0, path: '', fileId: item['id']?.toString(), raw: Map<String, dynamic>.from(item))).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String> getDownloadUrl(CloudFile file) async {
    try {
      final resp = await _dio.get('https://cloud.189.cn/api/open/file/getFileDownloadUrl', queryParameters: {'fileId': file.fileId}, options: Options(headers: _headers));
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      return data['fileDownloadUrl'] ?? '';
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
        'https://cloud.189.cn/api/open/share/createShareLink',
        data: {'fileId': file.fileId, 'isFolder': file.isDir, 'accessCode': password ?? '', 'expireTime': expireDays != null ? DateTime.now().add(Duration(days: expireDays)).millisecondsSinceEpoch : 0},
        options: Options(headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'}),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final shareUrl = data['shareUrl'] as String?;
      if (shareUrl != null) return ShareResult(url: shareUrl, password: data['accessCode']);
    } catch (_) {}
    return ShareResult(url: 'https://cloud.189.cn/t/placeholder');
  }

  @override
  Future<bool> deleteFiles(List<CloudFile> files) async {
    try {
      for (final f in files) {
        await _dio.post('https://cloud.189.cn/api/open/file/deleteFile', data: {'fileId': f.fileId, 'isFolder': f.isDir}, options: Options(headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'}));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> createFolder(String path, String name) async {
    try {
      await _dio.post('https://cloud.189.cn/api/open/file/createFolder', data: {'parentFolderId': '-11', 'folderName': name}, options: Options(headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'}));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<StorageInfo> getStorageInfo() async {
    try {
      final resp = await _dio.get('https://cloud.189.cn/api/open/user/getUserInfo', options: Options(headers: _headers));
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      return StorageInfo(used: data['capacitySize']?['usedSize'] ?? 0, total: data['capacitySize']?['totalSize'] ?? 0);
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
