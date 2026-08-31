import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/credential_storage.dart';
import 'services/download_service.dart';
import 'services/settings_service.dart';
import 'services/chumian_drive_service.dart';
import 'services/notification_service.dart';
import 'services/alist_service.dart';
import 'screens/home_screen.dart';
import 'screens/parser_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/download_screen.dart';
import 'screens/chumian_drive_screen.dart';

class PanPalApp extends StatefulWidget {
  const PanPalApp({super.key});

  @override
  State<PanPalApp> createState() => _PanPalAppState();
}

class _PanPalAppState extends State<PanPalApp> {
  ThemeMode _themeMode = ThemeMode.system;
  int _currentIndex = 0;
  bool _initialized = false;
  final ChumianDriveService _chumianService = ChumianDriveService();
  final AListService _alistService = AListService();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final settings = context.read<SettingsService>();
    await settings.init();
    final credStorage = context.read<CredentialStorage>();
    await credStorage.init();
    await _chumianService.init();
    await NotificationService.init();
    if (!mounted) return;
    setState(() {
      _themeMode = settings.themeMode;
      _initialized = true;
    });
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    context.read<SettingsService>().setThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PanPal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: _initialized
          ? Scaffold(
              body: IndexedStack(
                index: _currentIndex,
                children: [
                  HomeScreen(alistService: _alistService),
                  ChumianDriveScreen(service: _chumianService),
                  const ParserScreen(),
                  const DownloadScreen(),
                  const SettingsScreen(),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (i) => setState(() => _currentIndex = i),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.cloud_outlined), selectedIcon: Icon(Icons.cloud), label: '网盘'),
                  NavigationDestination(icon: Icon(Icons.rocket_launch_outlined), selectedIcon: Icon(Icons.rocket_launch), label: '初眠'),
                  NavigationDestination(icon: Icon(Icons.link_outlined), selectedIcon: Icon(Icons.link), label: '解析'),
                  NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: '下载'),
                  NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '我的'),
                ],
              ),
            )
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
