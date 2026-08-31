import '../models/drive_account.dart';
import 'base_provider.dart';
import 'baidu_provider.dart';
import 'aliyun_provider.dart';
import 'pan123_provider.dart';
import 'quark_provider.dart';
import 'tianyi_provider.dart';
import 'lanzou_provider.dart';
import 'caiyun_provider.dart';

class DriveProviderFactory {
  static final Map<DriveType, BaseDriveProvider> _cache = {};

  static BaseDriveProvider create(DriveType type) {
    if (_cache.containsKey(type)) return _cache[type]!;
    final provider = switch (type) {
      DriveType.baidu => BaiduProvider(),
      DriveType.aliyun => AliyunProvider(),
      DriveType.pan123 => Pan123Provider(),
      DriveType.quark => QuarkProvider(),
      DriveType.tianyi => TianyiProvider(),
      DriveType.lanzou => LanzouProvider(),
      DriveType.caiyun => CaiyunProvider(),
    };
    _cache[type] = provider;
    return provider;
  }

  static Future<BaseDriveProvider> createWithCredential(DriveType type, Map<String, dynamic> credential) async {
    final provider = create(type);
    provider.credential = credential;
    return provider;
  }

  static void clearCache() => _cache.clear();
}
