import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/credential_storage.dart';
import 'services/download_service.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/download_screen.dart';

class PanPalApp extends StatefulWidget {
  const PanPalApp({super.key});

  @override
  State<PanPalApp> createState() => _PanPalAppState();
}

class _PanPalAppState extends State<PanPalApp> {
  final CredentialStorage _credentialStorage = CredentialStorage();
  final DownloadService _downloadService = DownloadService();
  ThemeMode _themeMode = ThemeMode.system;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _downloadService.init();
  }

  Future<void> _loadTheme() async {
    final mode = await _credentialStorage.getThemeMode();
    setState(() => _themeMode = mode);
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    _credentialStorage.setThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<CredentialStorage>.value(value: _credentialStorage),
        ChangeNotifierProvider<DownloadService>.value(value: _downloadService),
      ],
      child: MaterialApp(
        title: 'PanPal',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _themeMode,
        home: Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: [
              const HomeScreen(),
              const DownloadScreen(),
              SettingsScreen(onThemeChanged: _setThemeMode, currentTheme: _themeMode),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) => setState(() => _currentIndex = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.cloud_outlined), selectedIcon: Icon(Icons.cloud), label: '网盘'),
              NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: '下载'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
            ],
          ),
        ),
      ),
    );
  }
}
