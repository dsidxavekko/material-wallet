import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around local notifications, used to tell the user a transfer
/// confirmed while they were away.
///
/// Every call fails soft: on platforms without notification support (web,
/// desktop, tests) the plugin throws, and the app carries on silently.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialized = false;
  bool _enabled = false;

  /// `true` once the OS has granted the permission and notifications are usable.
  bool get enabled => _enabled;

  /// Prepares the plugin. Pass `request: true` to prompt for permission (used
  /// when the user turns the setting on).
  Future<bool> initialize({bool request = false}) async {
    try {
      if (!_initialized) {
        const AndroidInitializationSettings android =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        const InitializationSettings settings =
            InitializationSettings(android: android);
        await _plugin.initialize(settings: settings);
        _initialized = true;
      }
      if (request) {
        final AndroidFlutterLocalNotificationsPlugin? android = _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        // `null` off Android, or a `false` when the user declines.
        _enabled = await android?.requestNotificationsPermission() ?? false;
      }
    } catch (error) {
      debugPrint('Notifications unavailable: $error');
      _enabled = false;
    }
    return _enabled;
  }

  /// Shows a confirmation notification. [id] dedupes per transaction.
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_enabled) {
      return;
    }
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'transfer_confirmations',
            'Transfer confirmations',
            channelDescription: 'Tells you when an outgoing transfer confirms.',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (error) {
      debugPrint('Could not show a notification: $error');
    }
  }
}
