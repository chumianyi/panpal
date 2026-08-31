import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const _keyConnections = 'panpal_connections';
  static const _keyTheme = 'panpal_theme';
  static const _keyParserApi = 'panpal_parser_api';
  static const _keyParserMode = 'panpal_parser_mode';
  static const _keyDownloadPath = 'panpal_download_path';

  late SharedPreferences _prefs;
  bool _initialized = false;

  int _defaultConnections = 16;
  ThemeMode _themeMode = ThemeMode.system;
  String _parserApi = 'https://zl.390kk.com/parser?url=';
  bool _useBuiltinParser = true;
  String _downloadPath = '/storage/emulated/0/Download/PanPal';

  int get defaultConnections => _defaultConnections;
  ThemeMode get themeMode => _themeMode;
  String get parserApi => _parserApi;
  bool get useBuiltinParser => _useBuiltinParser;
  String get downloadPath => _downloadPath;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _defaultConnections = _prefs.getInt(_keyConnections) ?? 16;
    final themeStr = _prefs.getString(_keyTheme);
    _themeMode = switch (themeStr) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _parserApi = _prefs.getString(_keyParserApi) ?? 'https://zl.390kk.com/parser?url=';
    _useBuiltinParser = _prefs.getBool(_keyParserMode) ?? true;
    _downloadPath = _prefs.getString(_keyDownloadPath) ?? '/storage/emulated/0/Download/PanPal';
    _initialized = true;
  }

  set defaultConnections(int v) {
    _defaultConnections = v.clamp(1, 64);
    _prefs.setInt(_keyConnections, _defaultConnections);
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs.setString(_keyTheme, mode.name);
    notifyListeners();
  }

  set parserApi(String v) {
    _parserApi = v;
    _prefs.setString(_keyParserApi, v);
    notifyListeners();
  }

  set useBuiltinParser(bool v) {
    _useBuiltinParser = v;
    _prefs.setBool(_keyParserMode, v);
    notifyListeners();
  }

  set downloadPath(String v) {
    _downloadPath = v;
    _prefs.setString(_keyDownloadPath, v);
    notifyListeners();
  }
}
