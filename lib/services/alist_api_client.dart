import 'dart:convert';
import 'dart:io';
import 'alist_service.dart';

class AListFile {
  final String name;
  final int size;
  final bool isDir;
  final DateTime? modifiedAt;
  final String? sign;
  final String? thumb;
  final String? type;
  final Map<String, dynamic> raw;

  AListFile({
    required this.name,
    required this.size,
    required this.isDir,
    this.modifiedAt,
    this.sign,
    this.thumb,
    this.type,
    required this.raw,
  });

  factory AListFile.fromJson(Map<String, dynamic> json) {
    return AListFile(
      name: json['name'] ?? '',
      size: json['size'] ?? 0,
      isDir: json['is_dir'] == true,
      modifiedAt: json['modified'] != null ? DateTime.tryParse(json['modified'].toString()) : null,
      sign: json['sign'],
      thumb: json['thumb'],
      type: json['type']?.toString(),
      raw: json,
    );
  }
}

class AListDriver {
  final int id;
  final String name;
  final String type;
  final bool status;
  final Map<String, dynamic> addition;
  final String? mountPath;
  final int order;

  AListDriver({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.addition,
    this.mountPath,
    required this.order,
  });

  factory AListDriver.fromJson(Map<String, dynamic> json) {
    return AListDriver(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      status: json['status'] == 'WORK' || json['status'] == true,
      addition: json['addition'] is Map ? Map<String, dynamic>.from(json['addition']) : {},
      mountPath: json['mount_path'],
      order: json['order'] ?? 0,
    );
  }
}

class AListApiClient {
  final AListService service;

  AListApiClient(this.service);

  String get _baseUrl => service.baseUrl;
  String? get _token => service.token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': _token!,
      };

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final request = await client.postUrl(uri);
      _headers.forEach((k, v) => request.headers.set(k, v));
      request.write(jsonEncode(body));
      final response = await request.close();
      final respBody = await response.transform(utf8.decoder).join();
      return jsonDecode(respBody) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final request = await client.getUrl(uri);
      _headers.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close();
      final respBody = await response.transform(utf8.decoder).join();
      return jsonDecode(respBody) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  // ========== Auth ==========
  Future<String> login(String username, String password) async {
    final resp = await _post('/api/auth/login', {
      'username': username,
      'password': password,
    });
    if (resp['code'] != 200) {
      throw Exception(resp['message'] ?? '登录失败');
    }
    return resp['data']['token'] as String;
  }

  // ========== File System ==========
  Future<List<AListFile>> listFiles(String path, {String? password, int page = 1, int perPage = 100}) async {
    final resp = await _post('/api/fs/list', {
      'path': path,
      'password': password ?? '',
      'page': page,
      'per_page': perPage,
      'refresh': false,
    });
    if (resp['code'] != 200) {
      throw Exception(resp['message'] ?? '获取文件列表失败');
    }
    final content = resp['data']['content'] as List? ?? [];
    return content.map((e) => AListFile.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Map<String, dynamic>> getFile(String path, {String? password}) async {
    final resp = await _post('/api/fs/get', {
      'path': path,
      'password': password ?? '',
    });
    if (resp['code'] != 200) {
      throw Exception(resp['message'] ?? '获取文件信息失败');
    }
    return Map<String, dynamic>.from(resp['data']);
  }

  Future<String> getDownloadUrl(String path, {String? password}) async {
    final info = await getFile(path, password: password);
    return info['raw_url'] ?? info['url'] ?? '';
  }

  Future<void> makeDir(String path) async {
    final resp = await _post('/api/fs/mkdir', {'path': path});
    if (resp['code'] != 200) {
      throw Exception(resp['message'] ?? '创建文件夹失败');
    }
  }

  Future<void> removeFiles(List<String> paths, List<String> names) async {
    final resp = await _post('/api/fs/remove', {
      'dir': paths.isNotEmpty ? paths.first : '/',
      'names': names,
    });
    if (resp['code'] != 200) {
      throw Exception(resp['message'] ?? '删除失败');
    }
  }

  // ========== Driver Management ==========
  Future<List<AListDriver>> listDrivers() async {
    final resp = await _get('/api/admin/driver/list?page=1&per_page=100');
    if (resp['code'] != 200) {
      throw Exception(resp['message'] ?? '获取驱动列表失败');
    }
    final content = resp['data']['content'] as List? ?? [];
    return content.map((e) => AListDriver.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> createDriver({
    required String type,
    required String name,
    required String mountPath,
    Map<String, dynamic> addition = const {},
  }) async {
    final resp = await _post('/api/admin/driver/create', {
      'type': type,
      'name': name,
      'mount_path': mountPath,
      'order': 0,
      'remark': '',
      'modified': DateTime.now().toIso8601String(),
      'addition': addition,
    });
    if (resp['code'] != 200) {
      throw Exception(resp['message'] ?? '添加驱动失败');
    }
  }

  Future<void> deleteDriver(int id) async {
    final resp = await _post('/api/admin/driver/delete', {'id': id});
    if (resp['code'] != 200) {
      throw Exception(resp['message'] ?? '删除驱动失败');
    }
  }

  Future<void> updateDriver({
    required int id,
    required String type,
    required String name,
    required String mountPath,
    Map<String, dynamic> addition = const {},
    bool status = true,
  }) async {
    final resp = await _post('/api/admin/driver/update', {
      'id': id,
      'type': type,
      'name': name,
      'mount_path': mountPath,
      'order': 0,
      'status': status ? 'WORK' : 'DISABLED',
      'addition': addition,
    });
    if (resp['code'] != 200) {
      throw Exception(resp['message'] ?? '更新驱动失败');
    }
  }

  // ========== Upload ==========
  Future<void> uploadFile(String localPath, String remotePath, String fileName) async {
    final file = File(localPath);
    final fileSize = await file.length();
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_baseUrl/api/fs/put');
      final request = await client.putUrl(uri);
      request.headers.set('Content-Type', 'application/octet-stream');
      request.headers.set('File-Path', Uri.encodeComponent('$remotePath/$fileName'));
      request.headers.set('Content-Length', fileSize.toString());
      if (_token != null) request.headers.set('Authorization', _token!);
      await request.addStream(file.openRead());
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data['code'] != 200) {
        throw Exception(data['message'] ?? '上传失败');
      }
    } finally {
      client.close();
    }
  }
}
