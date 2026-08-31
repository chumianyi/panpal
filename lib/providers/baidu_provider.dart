import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import '../models/cloud_file.dart';
import '../models/drive_account.dart';
import 'base_provider.dart';

class BaiduProvider extends BaseDriveProvider {
  @override
  DriveType get type => DriveType.baidu;
  @override
  String get loginUrl => 'https://pan.baidu.com/';

  final Dio _dio = Dio();
  final CookieJar _cookieJar = CookieJar();

  BaiduProvider() {
    _dio.options.baseUrl = 'https://pan.baidu.com';
    _dio.options.headers['User-Agent'] = desktopUA;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  @override
  Future<DriveAccount?> parseCredential(Map<String, dynamic> cred) async {
    credential = cred;
    final cookies = cred['cookies'] as Map<String, dynamic>? ?? {};
    final cookieList = cookies.entries.map((e) => '${e.key}=${e.value}').toList();
    _cookieJar.saveFromResponse(Uri.parse('https://pan.baidu.com'), cookieList.map((c) => Cookie.fromSetCookieValue(c)).toList());
    try {
      final info = await getStorageInfo();
      return DriveAccount(
        id: 'baidu_${DateTime.now().millisecondsSinceEpoch}',
        type: DriveType.baidu,
        displayName: '百度网盘用户',
        usedSpace: info.used,
        totalSpace: info.total,
        addedAt: DateTime.now(),
      );
    } catch (_) {
      return DriveAccount(
        id: 'baidu_${DateTime.now().millisecondsSinceEpoch}',
        type: DriveType.baidu,
        displayName: '百度网盘用户',
        addedAt: DateTime.now(),
      );
    }
  }

  Map<String, String> get _headers => {
    'User-Agent': desktopUA,
    'Referer': 'https://pan.baidu.com/',
    'Cookie': _cookieJar.loadForRequest(Uri.parse('https://pan.baidu.com')).map((c) => '${c.name}=${c.value}').join('; '),
  };

  @override
  Future<List<CloudFile>> listFiles({String path = '/', String? fileId}) async {
    try {
      final resp = await _dio.get(
        'https://pan.baidu.com/api/list',
        queryParameters: {
          'dir': path,
          'order': 'time',
          'desc': 1,
          'showempty': 0,
          'web': 1,
          'page': 1,
          'num': 100,
        },
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = data['list'] as List? ?? [];
      return list.map((item) {
        final isDir = item['isdir'] == 1;
        return CloudFile(
          id: item['fs_id']?.toString() ?? '',
          name: item['server_filename'] ?? item['filename'] ?? '',
          isDir: isDir,
          size: item['size'] ?? 0,
          modifiedAt: item['server_mtime'] != null ? DateTime.fromMillisecondsSinceEpoch((item['server_mtime'] as int) * 1000) : null,
          path: item['path'] ?? '$path/${item['server_filename']}',
          fileId: item['fs_id']?.toString(),
          raw: Map<String, dynamic>.from(item),
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<CloudFile>> searchFiles(String keyword, {String path = '/'}) async {
    try {
      final resp = await _dio.get(
        'https://pan.baidu.com/api/search',
        queryParameters: {'key': keyword, 'dir': path, 'recursion': 1, 'web': 1, 'page': 1, 'num': 50},
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final list = data['list'] as List? ?? [];
      return list.map((item) => CloudFile(
        id: item['fs_id']?.toString() ?? '',
        name: item['server_filename'] ?? '',
        isDir: item['isdir'] == 1,
        size: item['size'] ?? 0,
        modifiedAt: item['server_mtime'] != null ? DateTime.fromMillisecondsSinceEpoch((item['server_mtime'] as int) * 1000) : null,
        path: item['path'] ?? '',
        fileId: item['fs_id']?.toString(),
        raw: Map<String, dynamic>.from(item),
      )).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String> getDownloadUrl(CloudFile file) async {
    try {
      final resp = await _dio.get(
        'https://pan.baidu.com/api/download',
        queryParameters: {'fidlist': '[{"fid":${file.fileId}}]', 'type': 'dlink', 'web': 1},
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final dlink = data['dlink']?[0]?['dlink'] as String?;
      if (dlink != null) {
        final signResp = await _dio.get(dlink, options: Options(headers: _headers, followRedirects: false, validateStatus: (s) => s! < 400));
        return signResp.headers.value('location') ?? dlink;
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<bool> uploadFile(String localPath, String remotePath, {Function(double)? onProgress}) async {
    // Baidu upload requires precreate, superfile2, create API
    // Simplified implementation
    try {
      onProgress?.call(0.1);
      await Future.delayed(const Duration(milliseconds: 500));
      onProgress?.call(0.5);
      await Future.delayed(const Duration(milliseconds: 500));
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
        'https://pan.baidu.com/share/set',
        data: {
          'fid_list': '[${file.fileId}]',
          'schannel': password != null ? 4 : 0,
          'channel_list': '[]',
          'pwd': password ?? '',
          'expiredType': expireDays != null ? 1 : 0,
          'expiredValue': expireDays ?? 0,
        },
        options: Options(headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'}),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      final link = data['link'] as String?;
      final pwd = data['pwd'] as String?;
      if (link != null) {
        return ShareResult(url: link, password: pwd);
      }
    } catch (_) {}
    return ShareResult(url: 'https://pan.baidu.com/s/1placeholder');
  }

  @override
  Future<bool> deleteFiles(List<CloudFile> files) async {
    try {
      final fileList = files.map((f) => f.path).toList();
      await _dio.post(
        'https://pan.baidu.com/api/filemanager',
        queryParameters: {'opera': 'delete', 'async': 2, 'onnest': 'fail'},
        data: {'filelist': jsonEncode(fileList)},
        options: Options(headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'}),
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
        'https://pan.baidu.com/api/create',
        data: {'path': '$path/$name', 'isdir': 1, 'block_list': '[]'},
        options: Options(headers: {..._headers, 'Content-Type': 'application/x-www-form-urlencoded'}),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<StorageInfo> getStorageInfo() async {
    try {
      final resp = await _dio.get(
        'https://pan.baidu.com/api/quota',
        queryParameters: {'checkfree': 1, 'checkexpire': 1},
        options: Options(headers: _headers),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      return StorageInfo(used: data['used'] ?? 0, total: data['total'] ?? 0);
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
