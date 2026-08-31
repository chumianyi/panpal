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

  /// 获取 AList 工作目录（使用 filesDir，允许执行二进制）
  Future<Directory> _getAlistDir() async {
    // getApplicationSupportDirectory 在 Android 上返回 /data/data/<pkg>/files
    // 该目录允许执行二进制文件，不同于 app_flutter 目录
    final supportDir = await getApplicationSupportDirectory();
    final alistDir = Directory(p.join(supportDir.path, 'alist'));
    if (!await alistDir.exists()) {
      await alistDir.create(recursive: true);
    }
    return alistDir;
  }

  Future<void> _ensureBinary() async {
    final alistDir = await _getAlistDir();
    final binary = File(p.join(alistDir.path, 'alist'));

    if (!await binary.exists()) {
      // ignore: avoid_print
      print('[AList] 二进制不存在，开始从 assets 复制并合并分片...');
      print('[AList] 目标目录: ${alistDir.path}');

      final parts = ['assets/alist/alist.partaa', 'assets/alist/alist.partab'];
      final bytesBuilder = BytesBuilder();
      for (final part in parts) {
        try {
          // ignore: avoid_print
          print('[AList] 加载分片: $part');
          final bytes = await rootBundle.load(part);
          // ignore: avoid_print
          print('[AList] 分片 $part 大小: ${bytes.lengthInBytes} 字节');
          bytesBuilder.add(bytes.buffer.asUint8List());
        } catch (e) {
          // ignore: avoid_print
          print('[AList] 加载分片失败 $part: $e');
          throw Exception('无法加载 AList 二进制分片 $part: $e');
        }
      }
      await binary.writeAsBytes(bytesBuilder.toBytes());
      final finalSize = await binary.length();
      // ignore: avoid_print
      print('[AList] 二进制合并完成，大小: $finalSize 字节 (${(finalSize / 1024 / 1024).toStringAsFixed(1)}MB)');
    } else {
      final existingSize = await binary.length();
      // ignore: avoid_print
      print('[AList] 二进制已存在: ${binary.path}, 大小: $existingSize 字节');
    }

    // 设置可执行权限（使用 Android 系统 chmod，755 = rwxr-xr-x）
    // ignore: avoid_print
    print('[AList] 设置可执行权限: chmod 755 ${binary.path}');
    final chmodResult = await Process.run('/system/bin/chmod', ['755', binary.path]);
    // ignore: avoid_print
    print('[AList] chmod exit code: ${chmodResult.exitCode}');
    if (chmodResult.exitCode != 0) {
      // ignore: avoid_print
      print('[AList] chmod stderr: ${chmodResult.stderr}');
      // 尝试备用方式
      await Process.run('sh', ['-c', 'chmod 755 "${binary.path}"']);
    }

    // 验证权限
    final lsResult = await Process.run('ls', ['-la', binary.path]);
    // ignore: avoid_print
    print('[AList] 权限验证: ${lsResult.stdout.toString().trim()}');
  }

  Future<String> get binaryPath async {
    final alistDir = await _getAlistDir();
    return p.join(alistDir.path, 'alist');
  }

  Future<String> get alistDirPath async {
    final alistDir = await _getAlistDir();
    return alistDir.path;
  }

  Future<String> get dataDir async {
    final alistDir = await _getAlistDir();
    final dir = Directory(p.join(alistDir.path, 'data'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> start({int port = 5244}) async {
    if (_isRunning) return;
    _port = port;

    // 确保二进制存在且权限正确
    await _ensureBinary();

    final binPath = await binaryPath;
    final workDir = await alistDirPath;
    final dataPath = await dataDir;

    final binaryFile = File(binPath);
    if (!await binaryFile.exists()) {
      throw Exception('AList 二进制文件不存在: $binPath');
    }

    final fileSize = await binaryFile.length();
    if (fileSize < 1000000) {
      throw Exception('AList 二进制文件损坏（大小: $fileSize 字节）');
    }

    // ignore: avoid_print
    print('[AList] 启动服务');
    print('[AList]   二进制: $binPath');
    print('[AList]   工作目录: $workDir');
    print('[AList]   数据目录: $dataPath');
    print('[AList]   端口: $port');
    print('[AList]   大小: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB');

    // 通过 sh 执行，绕过 Android 对直接执行二进制的 SELinux 限制
    // 使用 workingDirectory 确保相对路径正确
    final command = 'ALIST_PORT=$port ./alist server --data ./data';
    // ignore: avoid_print
    print('[AList] 执行命令: sh -c "$command" (cwd: $workDir)');

    _process = await Process.start(
      '/system/bin/sh',
      ['-c', command],
      workingDirectory: workDir,
      environment: {'ALIST_PORT': port.toString()},
    );

    _isRunning = true;
    _statusController.add(true);

    // 监控 stdout
    _process!.stdout.transform(utf8.decoder).listen((line) {
      // ignore: avoid_print
      print('[AList OUT] $line');
      final match = RegExp(r'password[:：]\s*(\S+)').firstMatch(line);
      if (match != null && _adminPassword == null) {
        _adminPassword = match.group(1);
        // ignore: avoid_print
        print('[AList] 解析到管理员密码');
      }
    });

    // 监控 stderr
    _process!.stderr.transform(utf8.decoder).listen((line) {
      // ignore: avoid_print
      print('[AList ERR] $line');
    });

    // 崩溃自动重启
    _process!.exitCode.then((code) {
      // ignore: avoid_print
      print('[AList] 进程退出，code: $code, _isRunning: $_isRunning');
      if (_isRunning) {
        _isRunning = false;
        _statusController.add(false);
        Future.delayed(const Duration(seconds: 3), () {
          if (!_isRunning) {
            // ignore: avoid_print
            print('[AList] 自动重启...');
            start(port: port);
          }
        });
      }
    });

    // 等待服务就绪
    await _waitForReady();
    // 登录获取 token
    await _login();
    // 启动健康检查
    _startHealthCheck();
  }

  Future<void> _waitForReady() async {
    // ignore: avoid_print
    print('[AList] 等待服务就绪（端口 $_port）...');
    for (int i = 0; i < 30; i++) {
      try {
        final socket = await Socket.connect('127.0.0.1', _port, timeout: const Duration(seconds: 1));
        await socket.close();
        // ignore: avoid_print
        print('[AList] 服务已就绪（${i + 1}秒）');
        return;
      } catch (_) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    throw Exception('AList 服务启动超时（30秒）');
  }

  Future<void> _login() async {
    try {
      // ignore: avoid_print
      print('[AList] 登录获取 token...');
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
        // ignore: avoid_print
        print('[AList] 登录成功，token 已获取');
      } else {
        // ignore: avoid_print
        print('[AList] 登录失败: ${data['message']}');
      }
      client.close();
    } catch (e) {
      // ignore: avoid_print
      print('[AList] 登录异常: $e');
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
        // 服务可能挂了，进程监控会自动重启
      }
    });
  }

  Future<void> stop() async {
    // ignore: avoid_print
    print('[AList] 停止服务');
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

  /// 获取管理员密码（首次启动时使用）
  Future<String?> getAdminPassword() async {
    if (_adminPassword != null) return _adminPassword;
    final binPath = await binaryPath;
    final workDir = await alistDirPath;
    // ignore: avoid_print
    print('[AList] 获取管理员密码...');
    // 通过 sh 执行
    final result = await Process.run(
      '/system/bin/sh',
      ['-c', './alist admin --data ./data'],
      workingDirectory: workDir,
    );
    final output = result.stdout.toString();
    // ignore: avoid_print
    print('[AList] admin 命令输出: $output');
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
