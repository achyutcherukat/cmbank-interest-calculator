import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for backup events and the day-close summary.
///
/// Backup notifications are sent ONLY for scheduled Drive backup failures.
/// No notifications for successful backups, photo sync, storage warnings, or
/// local backup operations. The day-close summary fires unconditionally
/// whenever Day End & Close commits successfully.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _backupChannelId = 'cmb_backup';
  static const _backupChannelName = 'CM Bank Backup';
  static const _dayCloseChannelId = 'cmb_dayclose';
  static const _dayCloseChannelName = 'CM Bank Day Close';
  static const backupFailedId = 1001;
  static const daySummaryId = 1002;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Set once at app startup (see main.dart) so notification taps can route
  /// without a BuildContext. Payload-keyed, dispatched by the host app.
  Future<void> Function(String payload)? _onTap;

  /// Safe to call multiple times. Creates the notification channels and
  /// registers the tap handler on first call only.
  Future<void> init({Future<void> Function(String payload)? onTap}) async {
    if (_initialized) return;
    _onTap = onTap;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _onTap?.call(payload);
      },
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _backupChannelId,
          _backupChannelName,
          importance: Importance.high,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _dayCloseChannelId,
          _dayCloseChannelName,
          importance: Importance.defaultImportance,
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
        _backupChannelId,
        _backupChannelName,
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

  /// Shown after Day End & Close commits successfully for [businessDate].
  /// Silently does nothing if notification permission was denied — the
  /// caller must not treat a failure here as blocking the day lock.
  Future<void> showDaySummary({
    required String title,
    required String body,
  }) async {
    await init();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _dayCloseChannelId,
        _dayCloseChannelName,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(body),
      ),
    );
    await _plugin.show(
      daySummaryId,
      title,
      body,
      details,
      payload: 'open_cash_book',
    );
  }
}
