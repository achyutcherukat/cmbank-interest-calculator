import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for backup events.
///
/// Per spec, notifications are sent ONLY for scheduled Drive backup failures.
/// No notifications for successful backups, photo sync, storage warnings, or
/// local backup operations.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _channelId = 'cmb_backup';
  static const _channelName = 'CM Bank Backup';
  static const backupFailedId = 1001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Safe to call multiple times. Creates the high-importance channel.
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          importance: Importance.high,
        ),
      );
      await android.requestNotificationsPermission();
    }
    _initialized = true;
  }

  /// Shown when a *scheduled* Drive backup fails. Tapping opens admin backup
  /// settings (payload handled by the host app's notification tap handler).
  Future<void> showBackupFailed() async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
      backupFailedId,
      'CM Bank Backup Failed',
      'Automatic backup failed. Please check your internet connection and try '
          'manual backup.',
      details,
      payload: 'open_backup_settings',
    );
  }
}
