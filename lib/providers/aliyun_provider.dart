import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/cloud_file.dart';
import '../models/drive_account.dart';
import 'base_provider.dart';

class AliyunProvider extends BaseDriveProvider {
  @override
  DriveType get type => DriveType.aliyun;

  @override
  String get loginUrl => 'https://www.aliyundrive.com/';

  final Dio _dio = Dio();
  String _accessToken = '';
  String _refreshToken = '';
  String _driveId = '';
  String _cookieStr = '';

  AliyunProvider() {
    _dio.options.baseUrl = 'https://api.aliyundrive.com';
    _dio.options.headers['User-Agent'] = desktopUA;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_accessToken',
        'User-Agent': desktopUA,
        'Content-Type': 'application/json',
        'Referer': 'https://www.aliyundrive.com/',
        if (_cookieStr.isNotEmpty) 'Cookie': _cookieStr,
      };

  @override
  Future<DriveAccount?> parseCredential(Map<String, dynamic> cred) async {
    credential = cred;
    _accessToken = cred['access_token'] as String? ?? cred['token'] as String? ?? '';
    _refreshToken = cred['refresh_token'] as String? ?? '';
    final cookies = cred['cookies'] as Map<String, dynamic>? ?? {};
    _cookieStr = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    if (_cookieStr.isEmpty && (cred['cookie'] as String? ?? '').isNotEmpty) {
      _cookieStr = cred['cookie'] as String;
    }
    if (_accessToken.isEmpty && _cookieStr.isEmpty) return null;

    // Try refresh token if access token is empty
    if (_accessToken.isEmpty && _refreshToken.isNotEmpty) {
      try {
        await _refreshAccessToken();
      } catch (_) {}
    }

    try {
      await _getDriveId();
      final info = await getStorageInfo();
      return DriveAccount(
        id: 'aliyun_${DateTime.now().millisecondsSinceEpoch}',
        type: DriveType.aliyun,
        displayName: '阿里云盘用户',
        usedSpace: info.used,
        totalSpace: info.total,
        addedAt: DateTime.now(),
        credential: cred,
      );
    } catch (_) {
      return DriveAccount(
        id: 'aliyun_${DateTime.now().millisecondsSinceEpoch}',
        type: DriveType.aliyun,
        displayName: '阿里云盘用户',
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

  Future<void> _refreshAccessToken() async {
    final resp = await _dio.post(
      'https://auth.aliyundrive.com/v2/account/token',
      data: {'grant_type': 'refresh_token', 'refresh_token': _refreshToken},
      options: Options(headers: {'Content-Type': 'application/json', 'User-Agent': desktopUA}),
    );
    final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
    _accessToken = data['access_token'] ?? '';
    _refreshToken = data['refresh_token'] ?? '';
  }

  Future<void> _getDriveId() async {
    try {
      final resp = await _dio.post(
        'https://user.aliyundrive.com/v2/user/get',
        data: {},
        options: Options(headers: {'Authorization': 'Bearer $_accessToken', 'User-Agent': desktopUA}),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      _driveId = data['default_drive_id'] ?? '';
    } catch (_) {}
  }

  @override
  Future<List<CloudFile>> listFiles({String path = '/', String? fileId}) async {
    try {
      final resp = await _dio.post(
        'https://api.aliyundrive.com/adrive/v3/file/list',
        data: {
          'drive_id': _driveId,
          'parent_file_id': fileId ?? 'root',
          'limit': 100,
          'order_by': 'updated_at',
          'order_direction': 'DESC',
          'marker': '',
        },
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final items = data['items'] as List? ?? [];
      return items.map((item) {
        final type = item['type'] as String?;
        final isDir = type == 'folder';
        return CloudFile(
          id: item['file_id'] ?? '',
          name: item['name'] ?? '',
          isDir: isDir,
          size: item['size'] ?? 0,
          modifiedAt: item['updated_at'] != null ? DateTime.tryParse(item['updated_at']) : null,
          path: path,
          fileId: item['file_id'],
          downloadUrl: item['download_url'],
          thumbnail: item['thumbnail'],
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
      final resp = await _dio.post(
        'https://api.aliyundrive.com/adrive/v3/file/search',
        data: {'drive_id': _driveId, 'query': 'name match "$keyword"', 'limit': 50},
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final items = data['items'] as List? ?? [];
      return items
          .map((item) => CloudFile(
                id: item['file_id'] ?? '',
                name: item['name'] ?? '',
                isDir: item['type'] == 'folder',
                size: item['size'] ?? 0,
                modifiedAt: item['updated_at'] != null ? DateTime.tryParse(item['updated_at']) : null,
                path: '',
                fileId: item['file_id'],
                raw: Map<String, dynamic>.from(item),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String> getDownloadUrl(CloudFile file) async {
    try {
      final resp = await _dio.post(
        'https://api.aliyundrive.com/v2/file/get_download_url',
        data: {'drive_id': _driveId, 'file_id': file.fileId},
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      return data['url'] ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<ShareResult> shareFile(CloudFile file, {String? password, int? expireDays}) async {
    final resp = await _dio.post(
      'https://api.aliyundrive.com/adrive/v2/share_link/create',
      data: {
        'drive_id': _driveId,
        'file_id_list': [file.fileId],
        'share_pwd': password ?? '',
        'expiration': expireDays != null ? '${expireDays}d' : '',
        'share_msg': '',
      },
      options: Options(headers: _headers),
    );
    final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
    final shareUrl = data['share_url'] as String?;
    final sharePwd = data['share_pwd'] as String?;
    if (shareUrl != null) {
      return ShareResult(url: shareUrl, password: sharePwd);
    }
    throw Exception('分享失败');
  }

  @override
  Future<bool> deleteFiles(List<CloudFile> files) async {
    try {
      for (final f in files) {
        await _dio.post(
          'https://api.aliyundrive.com/v2/recyclebin/trash',
          data: {'drive_id': _driveId, 'file_id': f.fileId},
          options: Options(headers: _headers),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> createFolder(String path, String name) async {
    try {
      await _dio.post(
        'https://api.aliyundrive.com/adrive/v2/file/createWithFolders',
        data: {'drive_id': _driveId, 'parent_file_id': 'root', 'name': name, 'type': 'folder', 'check_name_mode': 'refuse'},
        options: Options(headers: _headers),
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
        'https://api.aliyundrive.com/adrive/v1/user/driveCapacityDetails',
        data: {},
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      return StorageInfo(used: data['used_size'] ?? 0, total: data['total_size'] ?? 0);
    } catch (_) {
      return const StorageInfo();
    }
  }

  @override
  Future<void> logout() async {
    credential.clear();
    _accessToken = '';
    _refreshToken = '';
    _driveId = '';
    _cookieStr = '';
  }
}
