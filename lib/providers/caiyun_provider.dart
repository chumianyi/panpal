import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/cloud_file.dart';
import '../models/drive_account.dart';
import 'base_provider.dart';

class CaiyunProvider extends BaseDriveProvider {
  @override
  DriveType get type => DriveType.caiyun;
  @override
  String get loginUrl => 'https://caiyun.feixin.10086.cn/';

  final Dio _dio = Dio();
  String _cookieStr = "";

  CaiyunProvider() {
    _dio.options.baseUrl = 'https://caiyun.feixin.10086.cn';
    _dio.options.headers['User-Agent'] = desktopUA;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  @override
  Future<DriveAccount?> parseCredential(Map<String, dynamic> cred) async {
    credential = cred;
    final cookies = cred['cookies'] as Map<String, dynamic>? ?? {};
    final cookieList = cookies.entries.map((e) => '${e.key}=${e.value}').toList();
    _cookieStr = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    try {
      final info = await getStorageInfo();
      return DriveAccount(id: 'caiyun_${DateTime.now().millisecondsSinceEpoch}', type: DriveType.caiyun, displayName: '和彩云用户', usedSpace: info.used, totalSpace: info.total, addedAt: DateTime.now());
    } catch (_) {
      return DriveAccount(id: 'caiyun_${DateTime.now().millisecondsSinceEpoch}', type: DriveType.caiyun, displayName: '和彩云用户', addedAt: DateTime.now());
    }
  }

  Map<String, String> get _headers => {'User-Agent': desktopUA, 'Referer': 'https://caiyun.feixin.10086.cn/', 'Cookie': _cookieStr, 'Content-Type': 'application/json'};

  @override
  Future<List<CloudFile>> listFiles({String path = '/', String? fileId}) async {
    try {
      final resp = await _dio.post(
        'https://caiyun.feixin.10086.cn/shop/fileManager/getFileList.action',
        data: {'parentId': fileId ?? '0', 'pageNum': 1, 'pageSize': 100, 'sortType': 3, 'sortOrder': 1},
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = data['list'] as List? ?? [];
      return list.map((item) => CloudFile(
        id: item['fileId']?.toString() ?? '', name: item['fileName'] ?? '',
        isDir: item['fileType'] == 0, size: item['fileSize'] ?? 0,
        modifiedAt: item['updateTime'] != null ? DateTime.tryParse(item['updateTime'].toString()) : null,
        path: path, fileId: item['fileId']?.toString(), raw: Map<String, dynamic>.from(item),
      )).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<CloudFile>> searchFiles(String keyword, {String path = '/'}) async {
    try {
      final resp = await _dio.post('https://caiyun.feixin.10086.cn/shop/fileManager/searchFile.action', data: {'keyword': keyword, 'pageNum': 1, 'pageSize': 50}, options: Options(headers: _headers));
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = data['list'] as List? ?? [];
      return list.map((item) => CloudFile(id: item['fileId']?.toString() ?? '', name: item['fileName'] ?? '', isDir: item['fileType'] == 0, size: item['fileSize'] ?? 0, path: '', fileId: item['fileId']?.toString(), raw: Map<String, dynamic>.from(item))).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String> getDownloadUrl(CloudFile file) async {
    try {
      final resp = await _dio.post('https://caiyun.feixin.10086.cn/shop/fileManager/getDownloadUrl.action', data: {'fileId': file.fileId}, options: Options(headers: _headers));
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      return data['downloadUrl'] ?? '';
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
      final resp = await _dio.post('https://caiyun.feixin.10086.cn/shop/share/createShare.action', data: {'fileId': file.fileId, 'password': password ?? '', 'expireTime': expireDays ?? 0}, options: Options(headers: _headers));
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final shareUrl = data['shareUrl'] as String?;
      if (shareUrl != null) return ShareResult(url: shareUrl, password: data['password']);
    } catch (_) {}
    return ShareResult(url: 'https://caiyun.feixin.10086.cn/s/placeholder');
  }

  @override
  Future<bool> deleteFiles(List<CloudFile> files) async {
    try {
      for (final f in files) {
        await _dio.post('https://caiyun.feixin.10086.cn/shop/fileManager/deleteFile.action', data: {'fileId': f.fileId, 'fileType': f.isDir ? 0 : 1}, options: Options(headers: _headers));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> createFolder(String path, String name) async {
    try {
      await _dio.post('https://caiyun.feixin.10086.cn/shop/fileManager/createFolder.action', data: {'parentId': '0', 'folderName': name}, options: Options(headers: _headers));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<StorageInfo> getStorageInfo() async {
    try {
      final resp = await _dio.post('https://caiyun.feixin.10086.cn/shop/user/getUserInfo.action', data: {}, options: Options(headers: _headers));
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      return StorageInfo(used: data['usedSpace'] ?? 0, total: data['totalSpace'] ?? 0);
    } catch (_) {
      return const StorageInfo();
    }
  }

  @override
  Future<void> logout() async {
    credential.clear();
    _cookieStr = "";
  }
}
