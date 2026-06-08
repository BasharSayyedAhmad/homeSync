import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class GasNotificationService {
  static final GasNotificationService _instance =
      GasNotificationService._internal();
  factory GasNotificationService() => _instance;
  GasNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ✅ Channel IDs
  static const String _channelId = 'gas_alert_channel';
  static const String _channelName = 'Gas Alerts';
  static const String _channelDesc = 'Critical gas leak notifications';

  Future<void> initialize() async {
    if (_initialized) return;

    // Android initialization
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization (not used but required)
    const darwinInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channel (Android 8+)
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      sound: RawResourceAndroidNotificationSound(
        'alarm',
      ), // ⬅️ ضع ملف alarm.mp3 في android/app/src/main/res/raw/
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    _initialized = true;
    print('🔔 GasNotificationService initialized');
  }

  // ✅ Show notification based on gas level
  Future<void> showGasAlert(String level) async {
    if (!_initialized) await initialize();

    String title;
    String body;
    Importance importance;
    Priority priority;
    Color? color;

    switch (level) {
      case 'ALERT':
        title = '🚨 تنبيه غاز حرج!';
        body = 'تم اكتشاف تسرب غاز خطير. اغادر المكان فوراً!';
        importance = Importance.max;
        priority = Priority.max;
        color = Colors.red;
        break;
      case 'WARN':
        title = '⚠️ تحذير غاز';
        body = 'مستوى الغاز مرتفع. افتح النوافذ وتأكد من المصدر.';
        importance = Importance.high;
        priority = Priority.high;
        color = Colors.orange;
        break;
      case 'OK':
      default:
        title = '✅ الغاز طبيعي';
        body = 'مستوى الغاز عاد للطبيعي.';
        importance = Importance.defaultImportance;
        priority = Priority.defaultPriority;
        color = Colors.green;
        break;
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: importance,
      priority: priority,
      color: color,
      ledColor: color,
      ledOnMs: 1000,
      ledOffMs: 500,
      enableLights: true,
      playSound: level == 'ALERT',
      sound: level == 'ALERT'
          ? const RawResourceAndroidNotificationSound('alarm')
          : null,
      styleInformation: level == 'ALERT'
          ? const BigTextStyleInformation(
              'تم اكتشاف تسرب غاز خطير. اغادر المكان فوراً!\n\n'
              '• لا تشغل أي كهرباء\n'
              '• افتح النوافذ\n'
              '• اتصل بالطوارئ',
              contentTitle: '🚨 تنبيه غاز حرج!',
            )
          : null,
    );

    const darwinDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _notifications.show(
      0, // notification ID
      title,
      body,
      details,
    );

    print('🔔 Gas notification shown: $level');
  }

  // ✅ Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    print('🔔 All notifications cancelled');
  }

  void _onNotificationTap(NotificationResponse response) {
    print('🔔 Notification tapped: ${response.payload}');
    // Navigate to home screen or specific alert screen if needed
  }
}
