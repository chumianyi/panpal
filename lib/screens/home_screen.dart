import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drive_account.dart';
import '../services/credential_storage.dart';
import '../utils/format_utils.dart';
import 'add_drive_screen.dart';
import 'file_manager_screen.dart';
import 'login_webview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CredentialStorage>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<CredentialStorage>();
    final accounts = storage.accounts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PanPal', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加网盘',
            onPressed: () => _showAddDrive(),
          ),
        ],
      ),
      body: accounts.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: accounts.length,
              itemBuilder: (context, index) => _buildDriveCard(accounts[index]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDrive(),
        icon: const Icon(Icons.add),
        label: const Text('添加网盘'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('还没有添加网盘', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('点击下方按钮添加你的第一个网盘', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showAddDrive(),
            icon: const Icon(Icons.add),
            label: const Text('添加网盘'),
          ),
        ],
      ),
    );
  }

  Widget _buildDriveCard(DriveAccount account) {
    final usedPercent = account.totalSpace > 0 ? account.usedSpace / account.totalSpace : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openDrive(account),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: account.type.color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                    child: Icon(account.type.icon, color: account.type.color, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(account.type.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                              child: const Text('已登录', style: TextStyle(fontSize: 10, color: Colors.green)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(account.displayName.isEmpty ? account.type.label : account.displayName, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) => _handleMenu(v, account),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'open', child: Text('打开')),
                      const PopupMenuItem(value: 'logout', child: Text('退出登录')),
                    ],
                  ),
                ],
              ),
              if (account.totalSpace > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: usedPercent, minHeight: 6, backgroundColor: Colors.grey[200]),
                ),
                const SizedBox(height: 6),
                Text('${FormatUtils.fileSize(account.usedSpace)} / ${FormatUtils.fileSize(account.totalSpace)}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDrive() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddDriveScreen()));
  }

  void _openDrive(DriveAccount account) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FileManagerScreen(account: account)));
  }

  void _handleMenu(String value, DriveAccount account) {
    switch (value) {
      case 'open':
        _openDrive(account);
        break;
      case 'logout':
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('退出登录'),
            content: Text('确定要退出 ${account.type.label} 吗？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await context.read<CredentialStorage>().removeAccount(account.id);
                },
                child: const Text('退出'),
              ),
            ],
          ),
        );
        break;
    }
  }
}
