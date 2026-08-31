import '../models/cloud_file.dart';
import '../models/drive_account.dart';

abstract class BaseDriveProvider {
  DriveType get type;
  String get loginUrl;

  String get desktopUA =>
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  Map<String, dynamic> credential = {};

  Future<DriveAccount?> parseCredential(Map<String, dynamic> cred);

  Future<DriveAccount?> loginWithPassword(String username, String password) async => null;

  Future<DriveAccount?> parseCookie(String cookieStr) async => null;

  Future<List<CloudFile>> listFiles({String path = '/', String? fileId});

  Future<List<CloudFile>> searchFiles(String keyword, {String path = '/'});

  Future<String> getDownloadUrl(CloudFile file);

  Future<bool> uploadFile(String localPath, String remotePath, {Function(double)? onProgress}) async => false;

  Future<ShareResult> shareFile(CloudFile file, {String? password, int? expireDays});

  Future<bool> deleteFiles(List<CloudFile> files);

  Future<bool> createFolder(String path, String name);

  Future<StorageInfo> getStorageInfo();

  Future<void> logout();
}

class ShareResult {
  final String url;
  final String? password;
  final DateTime? expireAt;
  const ShareResult({required this.url, this.password, this.expireAt});
}

class StorageInfo {
  final int used;
  final int total;
  const StorageInfo({this.used = 0, this.total = 0});
}
