import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'services/credential_storage.dart';
import 'services/download_service.dart';
import 'services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CredentialStorage()),
        ChangeNotifierProvider(create: (_) => DownloadService()),
        ChangeNotifierProvider(create: (_) => SettingsService()),
      ],
      child: const PanPalApp(),
    ),
  );
}
