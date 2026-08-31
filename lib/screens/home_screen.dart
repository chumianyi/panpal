import 'package:flutter/material.dart';
import '../services/alist_service.dart';
import '../services/alist_api_client.dart';
import '../services/notification_service.dart';
import 'file_manager_screen.dart';
import 'add_drive_screen.dart';

class HomeScreen extends StatefulWidget {
  final AListService alistService;
  const HomeScreen({super.key, required this.alistService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AListDriver> _drivers = [];
  bool _loading = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    widget.alistService.statusStream.listen((running) {
      if (mounted) setState(() {});
      if (running) _loadDrivers();
    });
    if (widget.alistService.isRunning) {
      _loadDrivers();
    }
  }

  Future<void> _startAList() async {
    setState(() => _starting = true);
    try {
      await widget.alistService.start(port: 5244);
      await NotificationService.startForegroundService(
        title: 'AList 运行中',
        body: '端口 5244 · 点击打开 PanPal',
      );
      await _loadDrivers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _loadDrivers() async {
    if (!widget.alistService.isRunning) return;
    setState(() => _loading = true);
    try {
      final client = AListApiClient(widget.alistService);
      final drivers = await client.listDrivers();
      if (mounted) setState(() => _drivers = drivers);
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.alistService.isRunning;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PanPal', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: running ? _loadDrivers : null),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加网盘',
            onPressed: running
                ? () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AddDriveScreen(alistService: widget.alistService),
                    ));
                    _loadDrivers();
                  }
                : null,
          ),
        ],
      ),
      body: !running
          ? _buildStartView()
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _drivers.isEmpty
                  ? _buildEmptyView()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _drivers.length,
                      itemBuilder: (context, index) => _buildDriverCard(_drivers[index]),
                    ),
    );
  }

  Widget _buildStartView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.cloud_outlined, size: 48, color: Colors.blue),
          ),
          const SizedBox(height: 24),
          const Text('AList 服务未启动', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('启动 AList 后可管理所有网盘', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _starting ? null : _startAList,
            icon: _starting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.play_arrow),
            label: Text(_starting ? '启动中...' : '启动 AList'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('还没有添加网盘', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AddDriveScreen(alistService: widget.alistService),
              ));
              _loadDrivers();
            },
            icon: const Icon(Icons.add),
            label: const Text('添加网盘'),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCard(AListDriver driver) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FileManagerScreen(
            alistService: widget.alistService,
            mountPath: driver.mountPath ?? '/${driver.name}',
            title: driver.name,
          ),
        )),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: _driverColor(driver.type).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(_driverIcon(driver.type), color: _driverColor(driver.type), size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('${driver.type} · ${driver.mountPath ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: driver.status ? Colors.green.withOpacity(0.15) : Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(driver.status ? '正常' : '异常',
                    style: TextStyle(fontSize: 11, color: driver.status ? Colors.green : Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _driverColor(String type) {
    switch (type.toLowerCase()) {
      case 'baidu': case 'baidunetdisk': return Colors.blue;
      case 'aliyundrive': case 'alipan': return Colors.deepPurple;
      case '123pan': return Colors.orange;
      case 'quark': return Colors.teal;
      case 'cloud189': case 'tianyi': return Colors.red;
      case 'lanzou': return Colors.blueGrey;
      case 'local': return Colors.green;
      default: return Colors.grey;
    }
  }

  IconData _driverIcon(String type) {
    switch (type.toLowerCase()) {
      case 'baidu': case 'baidunetdisk': return Icons.cloud;
      case 'aliyundrive': case 'alipan': return Icons.cloud_queue;
      case '123pan': return Icons.folder;
      case 'quark': return Icons.all_inclusive;
      case 'cloud189': case 'tianyi': return Icons.wifi;
      case 'lanzou': return Icons.link;
      case 'local': return Icons.sd_storage;
      default: return Icons.extension;
    }
  }
}
