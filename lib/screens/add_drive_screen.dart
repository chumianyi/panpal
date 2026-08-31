import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/drive_account.dart';
import '../services/credential_storage.dart';
import 'login_webview_screen.dart';

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
              onTap: isLoggedIn
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => LoginWebViewScreen(driveType: type, credentialStorage: storage),
                      )),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: type.color.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
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
}
