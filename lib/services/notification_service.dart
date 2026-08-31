import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const MethodChannel _channel = MethodChannel('com.panpal.app/foreground');
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  static Future<void> showPersistentNotification({
    required String title,
    required String body,
    int id = 1001,
  }) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      'chumian_drive_service',
      '初眠网盘服务',
      channelDescription: '初眠网盘本地HTTP服务器运行通知',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(id, title, body, details);
  }

  static Future<void> cancelPersistentNotification({int id = 1001}) async {
    await _plugin.cancel(id);
  }

  // Start native foreground service (keeps app alive in background)
  static Future<void> startForegroundService({
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod('startForeground', {
        'title': title,
        'body': body,
      });
    } catch (_) {
      // Fallback to regular persistent notification
      await showPersistentNotification(title: title, body: body);
    }
  }

  static Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopForeground');
    } catch (_) {}
    await cancelPersistentNotification();
  }
}
