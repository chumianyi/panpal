import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import '../models/drive_account.dart';

class CredentialStorage extends ChangeNotifier {
  static const _accountsKey = 'panpal_accounts';
  static const _credPrefix = 'panpal_cred_';
  static const _settingsKey = 'panpal_settings';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  late SharedPreferences _prefs;
  bool _initialized = false;

  List<DriveAccount> _accounts = [];
  List<DriveAccount> get accounts => List.unmodifiable(_accounts);

  Map<String, dynamic> _settings = {};
  Map<String, dynamic> get settings => Map.unmodifiable(_settings);

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _loadAccounts();
    await _loadSettings();
    _initialized = true;
  }

  Future<void> _loadAccounts() async {
    final raw = _prefs.getString(_accountsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _accounts = list.map((e) => DriveAccount.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        _accounts = [];
      }
    }
    notifyListeners();
  }

  Future<void> _saveAccounts() async {
    await _prefs.setString(_accountsKey, jsonEncode(_accounts.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final raw = _prefs.getString(_settingsKey);
    if (raw != null) {
      try {
        _settings = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        _settings = {};
      }
    }
  }

  Future<void> _saveSettings() async {
    await _prefs.setString(_settingsKey, jsonEncode(_settings));
  }

  String _deriveKey(String accountId) {
    final bytes = utf8.encode('panpal_salt_$accountId');
    return sha256.convert(bytes).toString().substring(0, 32);
  }

  Future<void> saveCredential(String accountId, Map<String, dynamic> credential) async {
    final key = enc.Key.fromUtf8(_deriveKey(accountId));
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(jsonEncode(credential), iv: iv);
    final data = jsonEncode({'iv': base64Encode(iv.bytes), 'data': encrypted.base64});
    await _secureStorage.write(key: '$_credPrefix$accountId', value: data);
  }

  Future<Map<String, dynamic>?> getCredential(String accountId) async {
    final raw = await _secureStorage.read(key: '$_credPrefix$accountId');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final iv = enc.IV.fromBase64(map['iv'] as String);
      final key = enc.Key.fromUtf8(_deriveKey(accountId));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decrypt64(map['data'] as String, iv: iv);
      return jsonDecode(decrypted) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> removeCredential(String accountId) async {
    await _secureStorage.delete(key: '$_credPrefix$accountId');
  }

  Future<void> addAccount(DriveAccount account, Map<String, dynamic> credential) async {
    _accounts.removeWhere((e) => e.id == account.id);
    _accounts.add(account);
    await _saveAccounts();
    await saveCredential(account.id, credential);
  }

  Future<void> updateAccount(DriveAccount account) async {
    final idx = _accounts.indexWhere((e) => e.id == account.id);
    if (idx >= 0) {
      _accounts[idx] = account;
      await _saveAccounts();
    }
  }

  Future<void> removeAccount(String accountId) async {
    _accounts.removeWhere((e) => e.id == accountId);
    await _saveAccounts();
    await removeCredential(accountId);
  }

  Future<void> clearAllCredentials() async {
    for (final acc in _accounts) {
      await removeCredential(acc.id);
    }
    _accounts.clear();
    await _saveAccounts();
  }

  Future<void> clearCache() async {
    await _prefs.remove('panpal_file_cache');
  }

  // Settings
  int get defaultConnections => (_settings['defaultConnections'] as int?) ?? 16;
  set defaultConnections(int v) {
    _settings['defaultConnections'] = v;
    _saveSettings();
  }

  int get maxConcurrentTasks => (_settings['maxConcurrentTasks'] as int?) ?? 3;
  set maxConcurrentTasks(int v) {
    _settings['maxConcurrentTasks'] = v;
    _saveSettings();
  }

  String get downloadPath => (_settings['downloadPath'] as String?) ?? '/storage/emulated/0/Download/PanPal';
  set downloadPath(String v) {
    _settings['downloadPath'] = v;
    _saveSettings();
  }

  Future<ThemeMode> getThemeMode() async {
    final v = _settings['themeMode'] as String?;
    switch (v) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  void setThemeMode(ThemeMode mode) {
    _settings['themeMode'] = mode.name;
    _saveSettings();
  }
}
