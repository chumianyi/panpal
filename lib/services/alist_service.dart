import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AListService {
  Process? _process;
  bool _isRunning = false;
  int _port = 5244;
  String? _adminPassword;
  String? _token;
  Timer? _healthCheckTimer;
  final StreamController<bool> _statusController = StreamController<bool>.broadcast();

  bool get isRunning => _isRunning;
  int get port => _port;
  String get baseUrl => 'http://127.0.0.1:$_port';
  String? get token => _token;
  Stream<bool> get statusStream => _statusController.stream;

  Future<void> init() async {
    await _ensureBinary();
  }

  Future<void> _ensureBinary() async {
    final appDir = await getApplicationDocumentsDirectory();
    final alistDir = Directory(p.join(appDir.path, 'alist'));
    if (!await alistDir.exists()) {
      await alistDir.create(recursive: true);
    }
    final binary = File(p.join(alistDir.path, 'alist'));
    if (!await binary.exists()) {
      // Combine split binary parts from assets
      final parts = ['assets/alist/alist.partaa', 'assets/alist/alist.partab'];
      final bytesBuilder = BytesBuilder();
      for (final part in parts) {
        final bytes = await rootBundle.load(part);
        bytesBuilder.add(bytes.buffer.asUint8List());
      }
      await binary.writeAsBytes(bytesBuilder.toBytes());
    }
    await Process.run('chmod', ['+x', binary.path]);
  }

  Future<String> get binaryPath async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, 'alist', 'alist');
  }

  Future<String> get dataDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'alist', 'data'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> start({int port = 5244}) async {
    if (_isRunning) return;
    _port = port;

    final binPath = await binaryPath;
    final dataPath = await dataDir;

    final binaryFile = File(binPath);
    if (!await binaryFile.exists()) {
      throw Exception('AList 二进制文件不存在，请先初始化');
    }

    _process = await Process.start(
      binPath,
      ['server', '--data', dataPath],
      environment: {'ALIST_PORT': port.toString()},
    );

    _isRunning = true;
    _statusController.add(true);

    // Monitor process output
    _process!.stdout.transform(utf8.decoder).listen((line) {
      // Parse admin password from output if present
      final match = RegExp(r'password[:：]\s*(\S+)').firstMatch(line);
      if (match != null && _adminPassword == null) {
        _adminPassword = match.group(1);
      }
    });
    _process!.stderr.transform(utf8.decoder).listen((line) {
      // ignore: avoid_print
      print('[AList ERR] $line');
    });

    // Auto-restart on crash
    _process!.exitCode.then((code) {
      if (_isRunning) {
        _isRunning = false;
        _statusController.add(false);
        // Auto restart after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (!_isRunning) start(port: port);
        });
      }
    });

    // Wait for server to be ready
    await _waitForReady();

    // Login to get token
    await _login();

    // Start health check
    _startHealthCheck();
  }

  Future<void> _waitForReady() async {
    for (int i = 0; i < 30; i++) {
      try {
        final socket = await Socket.connect('127.0.0.1', _port, timeout: const Duration(seconds: 1));
        await socket.close();
        return;
      } catch (_) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    throw Exception('AList 服务启动超时');
  }

  Future<void> _login() async {
    try {
      final client = HttpClient();
      final request = await client.post('127.0.0.1', _port, '/api/auth/login');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'username': 'admin',
        'password': _adminPassword ?? 'admin',
      }));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data['code'] == 200) {
        _token = data['data']['token'];
      }
      client.close();
    } catch (e) {
      // ignore: avoid_print
      print('AList login failed: $e');
    }
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final client = HttpClient();
        final request = await client.get('127.0.0.1', _port, '/api/public/settings');
        final response = await request.close();
        response.drain();
        client.close();
      } catch (_) {
        // Server might be down, process monitor will restart
      }
    });
  }

  Future<void> stop() async {
    _isRunning = false;
    _healthCheckTimer?.cancel();
    _statusController.add(false);
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
    _token = null;
  }

  Future<void> restart({int? port}) async {
    await stop();
    await Future.delayed(const Duration(seconds: 1));
    await start(port: port ?? _port);
  }

  // Get admin password (for first time setup)
  Future<String?> getAdminPassword() async {
    if (_adminPassword != null) return _adminPassword;
    final binPath = await binaryPath;
    final dataPath = await dataDir;
    final result = await Process.run(
      binPath,
      ['admin', '--data', dataPath],
    );
    final output = result.stdout.toString();
    final match = RegExp(r'password[:：]\s*(\S+)').firstMatch(output);
    if (match != null) {
      _adminPassword = match.group(1);
    }
    return _adminPassword;
  }

  void dispose() {
    stop();
    _statusController.close();
  }
}
