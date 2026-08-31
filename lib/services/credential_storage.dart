import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/drive_account.dart';

class CredentialStorage extends ChangeNotifier {
  static const _accountsKey = 'panpal_accounts_v2';
  static const _credPrefix = 'panpal_cred_';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  late SharedPreferences _prefs;
  bool _initialized = false;
  List<DriveAccount> _accounts = [];
  List<DriveAccount> get accounts => List.unmodifiable(_accounts);

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _loadAccounts();
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

  Future<void> saveCredential(String accountId, Map<String, dynamic> credential) async {
    await _secureStorage.write(
      key: '$_credPrefix$accountId',
      value: jsonEncode(credential),
    );
  }

  Future<Map<String, dynamic>?> getCredential(String accountId) async {
    final raw = await _secureStorage.read(key: '$_credPrefix$accountId');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
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
}
