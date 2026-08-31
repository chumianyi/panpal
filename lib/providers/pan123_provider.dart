import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/cloud_file.dart';
import '../models/drive_account.dart';
import 'base_provider.dart';

class Pan123Provider extends BaseDriveProvider {
  @override
  DriveType get type => DriveType.pan123;

  @override
  String get loginUrl => 'https://www.123pan.com/';

  final Dio _dio = Dio();
  String _token = '';
  String _cookieStr = '';

  Pan123Provider() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  Map<String, String> get _authHeaders => {
        'Authorization': _token.isNotEmpty ? 'Bearer $_token' : '',
        'App-Version': '3',
        'platform': 'web',
        'Origin': 'https://yun.123pan.cn',
        'Referer': 'https://yun.123pan.cn/',
        'User-Agent': desktopUA,
        'Content-Type': 'application/json',
        if (_cookieStr.isNotEmpty) 'Cookie': _cookieStr,
      };

  @override
  Future<DriveAccount?> loginWithPassword(String username, String password) async {
    final resp = await _dio.post(
      'https://user.123pan.cn/api/user/sign_in',
      data: {'remember': true, 'passport': username, 'password': password},
      options: Options(headers: {
        'Content-Type': 'application/json',
        'App-Version': '3',
        'platform': 'web',
        'Origin': 'https://yun.123pan.cn',
        'Referer': 'https://yun.123pan.cn/',
        'User-Agent': desktopUA,
      }),
    );
    final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
    if (data['code'] != 200) {
      throw Exception(data['message'] ?? '登录失败');
    }
    _token = data['data']['token'] as String? ?? '';
    if (_token.isEmpty) throw Exception('未获取到token');
    final cred = {'token': _token, 'loginType': 'password', 'username': username};
    credential = cred;
    final info = await getStorageInfo();
    return DriveAccount(
      id: 'pan123_${DateTime.now().millisecondsSinceEpoch}',
      type: DriveType.pan123,
      displayName: username,
      usedSpace: info.used,
      totalSpace: info.total,
      addedAt: DateTime.now(),
      credential: cred,
    );
  }

  @override
  Future<DriveAccount?> parseCredential(Map<String, dynamic> cred) async {
    credential = cred;
    _token = cred['token'] as String? ?? '';
    final cookies = cred['cookies'] as Map<String, dynamic>? ?? {};
    _cookieStr = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    if (_token.isEmpty && _cookieStr.isEmpty) return null;
    try {
      final info = await getStorageInfo();
      return DriveAccount(
        id: 'pan123_${DateTime.now().millisecondsSinceEpoch}',
        type: DriveType.pan123,
        displayName: cred['username'] as String? ?? '123云盘用户',
        usedSpace: info.used,
        totalSpace: info.total,
        addedAt: DateTime.now(),
        credential: cred,
      );
    } catch (_) {
      return DriveAccount(
        id: 'pan123_${DateTime.now().millisecondsSinceEpoch}',
        type: DriveType.pan123,
        displayName: cred['username'] as String? ?? '123云盘用户',
        addedAt: DateTime.now(),
        credential: cred,
      );
    }
  }

  @override
  Future<DriveAccount?> parseCookie(String cookieStr) async {
    _cookieStr = cookieStr;
    final cred = {'cookie': cookieStr, 'loginType': 'cookie'};
    return parseCredential(cred);
  }

  @override
  Future<List<CloudFile>> listFiles({String path = '/', String? fileId}) async {
    try {
      final resp = await _dio.get(
        'https://www.123pan.com/b/api/file/list/new',
        queryParameters: {
          'driveId': 0,
          'limit': 100,
          'next': 0,
          'orderBy': 'file_id',
          'orderDirection': 'desc',
          'parentFileId': fileId ?? 0,
          'trashed': false,
          'SearchData': '',
          'Page': 1,
        },
        options: Options(headers: _authHeaders),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      if (data['code'] != 0) return [];
      final list = data['data']['InfoList'] as List? ?? [];
      return list.map((item) {
        final isDir = item['Type'] == 1;
        return CloudFile(
          id: item['FileId']?.toString() ?? '',
          name: item['FileName'] ?? '',
          isDir: isDir,
          size: item['Size'] ?? 0,
          modifiedAt: item['UpdateAt'] != null ? DateTime.tryParse(item['UpdateAt'].toString()) : null,
          path: path,
          fileId: item['FileId']?.toString(),
          raw: Map<String, dynamic>.from(item),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<CloudFile>> searchFiles(String keyword, {String path = '/'}) async {
    try {
      final resp = await _dio.get(
        'https://www.123pan.com/b/api/file/list/new',
        queryParameters: {'driveId': 0, 'limit': 50, 'SearchData': keyword, 'Page': 1, 'parentFileId': 0},
        options: Options(headers: _authHeaders),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = data['data']['InfoList'] as List? ?? [];
      return list.map((item) => CloudFile(
            id: item['FileId']?.toString() ?? '',
            name: item['FileName'] ?? '',
            isDir: item['Type'] == 1,
            size: item['Size'] ?? 0,
            path: '',
            fileId: item['FileId']?.toString(),
            raw: Map<String, dynamic>.from(item),
          )).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String> getDownloadUrl(CloudFile file) async {
    try {
      final raw = file.raw;
      final resp = await _dio.post(
        'https://www.123pan.com/a/api/file/download_info',
        data: {
          'driveId': 0,
          'etag': raw['Etag'] ?? '',
          'fileId': int.tryParse(file.fileId ?? '0') ?? 0,
          's3keyFlag': raw['S3KeyFlag'] ?? 0,
          'type': raw['Type'] ?? 0,
          'fileName': file.name,
          'size': file.size,
        },
        options: Options(headers: _authHeaders),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      if (data['code'] != 0) return '';
      final downloadUrl = data['data']['DownloadUrl'] as String? ?? '';
      if (downloadUrl.isEmpty) return '';
      final match = RegExp(r'params=([^&]+)').firstMatch(downloadUrl);
      if (match != null) {
        try {
          final decoded = utf8.decode(base64Decode(match.group(1)!));
          final redirectResp = await _dio.get(decoded,
              options: Options(followRedirects: false, validateStatus: (s) => s! < 400));
          return redirectResp.headers.value('location') ?? downloadUrl;
        } catch (_) {
          return downloadUrl;
        }
      }
      return downloadUrl;
    } catch (_) {
      return '';
    }
  }

  @override
  Future<ShareResult> shareFile(CloudFile file, {String? password, int? expireDays}) async {
    final resp = await _dio.post(
      'https://www.123pan.com/a/api/share/create',
      data: {
        'FileIDList': [int.tryParse(file.fileId ?? '0') ?? 0],
        'SharePwd': password ?? '',
        'ShareDay': expireDays ?? 0,
      },
      options: Options(headers: _authHeaders),
    );
    final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
    final shareUrl = data['data']['ShareUrl'] as String?;
    if (shareUrl != null) {
      return ShareResult(url: shareUrl, password: data['data']['SharePwd']);
    }
    throw Exception('分享失败');
  }

  @override
  Future<bool> deleteFiles(List<CloudFile> files) async {
    try {
      final ids = files.map((f) => int.tryParse(f.fileId ?? '0') ?? 0).toList();
      await _dio.post(
        'https://www.123pan.com/a/api/file/trash',
        data: {'driveId': 0, 'fileTrashInfoList': ids, 'operation': true},
        options: Options(headers: _authHeaders),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> createFolder(String path, String name) async {
    try {
      await _dio.post(
        'https://www.123pan.com/a/api/file/upload_request',
        data: {
          'driveId': 0,
          'etag': '',
          'fileName': name,
          'parentFileId': 0,
          'size': 0,
          'type': 1,
          'duplicate': 1,
          'NotReuse': true,
          'event': 'newCreateFolder',
          'operateType': 1,
        },
        options: Options(headers: _authHeaders),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<StorageInfo> getStorageInfo() async {
    try {
      final resp = await _dio.post(
        'https://www.123pan.com/api/v1/user/info',
        data: {},
        options: Options(headers: _authHeaders),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      return StorageInfo(used: data['data']['usedSize'] ?? 0, total: data['data']['totalSize'] ?? 0);
    } catch (_) {
      return const StorageInfo();
    }
  }

  @override
  Future<void> logout() async {
    credential.clear();
    _token = '';
    _cookieStr = '';
  }
}
