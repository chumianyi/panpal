import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ChumianFile {
  final String name;
  final int size;
  final DateTime modifiedAt;
  final String path;

  ChumianFile({
    required this.name,
    required this.size,
    required this.modifiedAt,
    required this.path,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
        'modifiedAt': modifiedAt.toIso8601String(),
        'path': path,
      };
}

class ChumianDriveService {
  HttpServer? _server;
  late Directory _storageDir;
  int _port = 8080;
  bool _isRunning = false;
  String? _localIp;

  int get port => _port;
  bool get isRunning => _isRunning;
  String? get localIp => _localIp;
  String get baseUrl => _localIp != null ? 'http://$_localIp:$_port' : '';

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _storageDir = Directory(p.join(appDir.path, 'chumian_drive'));
    if (!await _storageDir.exists()) {
      await _storageDir.create(recursive: true);
    }
    _localIp = await _getLocalIp();
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254')) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> startServer({int port = 8080}) async {
    if (_isRunning) return;
    _port = port;
    _localIp = await _getLocalIp();

    _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    _isRunning = true;

    _server!.listen((HttpRequest request) async {
      try {
        await _handleRequest(request);
      } catch (e) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(jsonEncode({'error': e.toString()}));
        await request.response.close();
      }
    });
  }

  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
    _isRunning = false;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    // CORS headers
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', '*');

    if (method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    if (path == '/' || path == '/index.html') {
      await _serveIndex(request);
      return;
    }

    if (path == '/api/files' && method == 'GET') {
      await _listFiles(request);
      return;
    }

    if (path == '/upload' && method == 'POST') {
      await _handleUpload(request);
      return;
    }

    if (path.startsWith('/file/') && method == 'GET') {
      await _serveFile(request);
      return;
    }

    if (path.startsWith('/api/files/') && method == 'DELETE') {
      await _deleteFile(request);
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    request.response.write(jsonEncode({'error': 'Not found'}));
    await request.response.close();
  }

  Future<void> _serveIndex(HttpRequest request) async {
    final files = await listFiles();
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>初眠网盘</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f5f5f5; padding: 20px; }
    .container { max-width: 800px; margin: 0 auto; }
    h1 { color: #1976d2; margin-bottom: 20px; }
    .upload-area { background: white; border: 2px dashed #1976d2; border-radius: 12px; padding: 40px; text-align: center; margin-bottom: 20px; cursor: pointer; }
    .upload-area:hover { background: #e3f2fd; }
    .file-list { background: white; border-radius: 12px; overflow: hidden; }
    .file-item { display: flex; align-items: center; padding: 16px; border-bottom: 1px solid #eee; }
    .file-item:last-child { border-bottom: none; }
    .file-icon { font-size: 32px; margin-right: 16px; }
    .file-info { flex: 1; }
    .file-name { font-weight: 600; color: #333; word-break: break-all; }
    .file-size { color: #999; font-size: 13px; margin-top: 4px; }
    .file-actions a { color: #1976d2; text-decoration: none; margin-left: 12px; }
    .empty { text-align: center; padding: 40px; color: #999; }
    input[type=file] { display: none; }
  </style>
</head>
<body>
  <div class="container">
    <h1>☁️ 初眠网盘</h1>
    <label class="upload-area" for="fileInput">
      <div style="font-size:48px;">📤</div>
      <div style="margin-top:12px;color:#666;">点击选择文件上传</div>
      <input type="file" id="fileInput" multiple>
    </label>
    <div class="file-list">
      ${files.isEmpty ? '<div class="empty">暂无文件</div>' : files.map((f) => '''
      <div class="file-item">
        <div class="file-icon">📄</div>
        <div class="file-info">
          <div class="file-name">${f.name}</div>
          <div class="file-size">${_formatSize(f.size)}</div>
        </div>
        <div class="file-actions">
          <a href="/file/${Uri.encodeComponent(f.name)}" download>下载</a>
        </div>
      </div>
      ''').join()}
    </div>
  </div>
  <script>
    document.getElementById('fileInput').addEventListener('change', async function(e) {
      const files = e.target.files;
      for (const file of files) {
        const formData = new FormData();
        formData.append('file', file);
        await fetch('/upload', { method: 'POST', body: formData });
      }
      location.reload();
    });
  </script>
</body>
</html>
''';
    request.response.headers.contentType = ContentType.html;
    request.response.write(html);
    await request.response.close();
  }

  Future<void> _listFiles(HttpRequest request) async {
    final files = await listFiles();
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(files.map((f) => f.toJson()).toList()));
    await request.response.close();
  }

  Future<void> _handleUpload(HttpRequest request) async {
    final contentType = request.headers.contentType;
    if (contentType == null || !contentType.mimeType.contains('multipart/form-data')) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': '需要 multipart/form-data'}));
      await request.response.close();
      return;
    }

    final boundary = contentType.parameters['boundary']!;
    final bodyBytes = await request.expand((chunk) => chunk).toList();
    final bodyStr = utf8.decode(bodyBytes, allowMalformed: true);

    String? fileName;
    List<int> fileBytes = [];

    // Manual multipart parsing
    final boundaryMarker = '--$boundary';
    final parts = bodyStr.split(boundaryMarker);
    for (final part in parts) {
      if (part.isEmpty || part == '--\r\n' || part == '--') continue;
      final headerEnd = part.indexOf('\r\n\r\n');
      if (headerEnd == -1) continue;
      final headers = part.substring(0, headerEnd);
      final filenameMatch = RegExp(r'filename="([^"]+)"').firstMatch(headers);
      if (filenameMatch != null) {
        fileName = filenameMatch.group(1);
        // Body starts after \r\n\r\n, ends with \r\n
        var bodyStart = headerEnd + 4;
        var bodyEnd = part.length;
        if (part.endsWith('\r\n')) bodyEnd -= 2;
        final partBodyStr = part.substring(bodyStart, bodyEnd);
        fileBytes = utf8.encode(partBodyStr);
        break;
      }
    }

    if (fileName == null || fileBytes.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': '未找到文件'}));
      await request.response.close();
      return;
    }

    // Sanitize filename
    fileName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final file = File(p.join(_storageDir.path, fileName));
    await file.writeAsBytes(fileBytes);

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'success': true,
      'fileName': fileName,
      'size': fileBytes.length,
      'url': '$baseUrl/file/${Uri.encodeComponent(fileName)}',
    }));
    await request.response.close();
  }

  Future<void> _serveFile(HttpRequest request) async {
    final fileName = Uri.decodeComponent(request.uri.path.substring('/file/'.length));
    final file = File(p.join(_storageDir.path, fileName));

    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(jsonEncode({'error': '文件不存在'}));
      await request.response.close();
      return;
    }

    final stat = await file.stat();
    request.response.headers.contentType = ContentType.parse('application/octet-stream');
    request.response.headers.add('Content-Disposition', 'attachment; filename="${Uri.encodeComponent(fileName)}"');
    request.response.headers.contentLength = stat.size;

    // Support range requests
    final rangeHeader = request.headers.value('range');
    if (rangeHeader != null) {
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
      if (match != null) {
        final start = int.parse(match.group(1)!);
        final end = match.group(2)!.isNotEmpty ? int.parse(match.group(2)!) : stat.size - 1;
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.add('Content-Range', 'bytes $start-$end/${stat.size}');
        request.response.headers.contentLength = end - start + 1;
        final stream = file.openRead(start, end + 1);
        await stream.pipe(request.response);
        return;
      }
    }

    await file.openRead().pipe(request.response);
  }

  Future<void> _deleteFile(HttpRequest request) async {
    final fileName = Uri.decodeComponent(request.uri.path.substring('/api/files/'.length));
    final file = File(p.join(_storageDir.path, fileName));

    if (await file.exists()) {
      await file.delete();
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'success': true}));
    await request.response.close();
  }

  // ========== 公共 API ==========
  Future<List<ChumianFile>> listFiles() async {
    if (!await _storageDir.exists()) return [];
    final entities = await _storageDir.list().toList();
    final files = <ChumianFile>[];
    for (final entity in entities) {
      if (entity is File) {
        final stat = await entity.stat();
        files.add(ChumianFile(
          name: p.basename(entity.path),
          size: stat.size,
          modifiedAt: stat.modified,
          path: entity.path,
        ));
      }
    }
    files.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return files;
  }

  Future<File> saveFile(String name, List<int> bytes) async {
    final safeName = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final file = File(p.join(_storageDir.path, safeName));
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> deleteFile(String name) async {
    final file = File(p.join(_storageDir.path, name));
    if (await file.exists()) {
      await file.delete();
    }
  }

  String getShareUrl(String fileName) {
    return '$baseUrl/file/${Uri.encodeComponent(fileName)}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
