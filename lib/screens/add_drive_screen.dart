import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drive_account.dart';
import '../services/credential_storage.dart';
import 'login_webview_screen.dart';
import 'login_password_screen.dart';
import 'manual_cookie_screen.dart';

class AddDriveScreen extends StatelessWidget {
  const AddDriveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<CredentialStorage>();
    final loggedInTypes = storage.accounts.map((e) => e.type).toSet();
    return Scaffold(
      appBar: AppBar(title: const Text('添加网盘')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.4,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: DriveType.values.length,
        itemBuilder: (context, index) {
          final type = DriveType.values[index];
          final isLoggedIn = loggedInTypes.contains(type);
          return Card(
            child: InkWell(
              onTap: isLoggedIn ? null : () => _showLoginOptions(context, type),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                          color: type.color.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                      child: Icon(type.icon, color: type.color, size: 32),
                    ),
                    const SizedBox(height: 12),
                    Text(type.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    if (isLoggedIn)
                      const Text('已登录', style: TextStyle(fontSize: 12, color: Colors.green))
                    else
                      Text('点击登录', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showLoginOptions(BuildContext context, DriveType type) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text('登录 ${type.label}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (type.supportsPasswordLogin)
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('账号密码登录'),
                subtitle: const Text('输入账号和密码直接登录'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LoginPasswordScreen(driveType: type),
                  ));
                },
              ),
            ListTile(
              leading: const Icon(Icons.web),
              title: const Text('WebView 登录'),
              subtitle: const Text('在应用内浏览器中登录'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LoginWebViewScreen(driveType: type),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.cookie),
              title: const Text('手动填Cookie'),
              subtitle: const Text('从浏览器复制Cookie粘贴'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ManualCookieScreen(driveType: type),
                ));
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
