import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../l10n/messages.dart';

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

  /// Prepares the plugin in a background worker, where there is no screen to
  /// ask on: it only notices whether the user already allowed notifications.
  Future<bool> initializeForBackground() async {
    try {
      await initialize();
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      _enabled = await android?.areNotificationsEnabled() ?? false;
    } catch (error) {
      debugPrint('Background notifications unavailable: $error');
      _enabled = false;
    }
    return _enabled;
  }

  /// Posts a background notification on the channel for funds arriving
  /// ([incoming]) or for a transfer confirming.
  Future<void> showInBackground({
    required int id,
    required String title,
    required String body,
    required bool incoming,
  }) =>
      incoming
          ? showIncoming(id: id, title: title, body: body)
          : show(id: id, title: title, body: body);

  /// Tells the user funds arrived (its own channel, so it can be silenced
  /// without losing confirmations).
  Future<void> showIncoming({
    required int id,
    required String title,
    required String body,
  }) =>
      _show(
        id: id,
        title: title,
        body: body,
        details: AndroidNotificationDetails(
          'incoming_funds',
          tr('Incoming funds'),
          channelDescription:
              tr('Tells you when funds arrive, even if the app is closed.'),
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  /// Shows a confirmation notification. [id] dedupes per transaction.
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) =>
      _show(
        id: id,
        title: title,
        body: body,
        details: AndroidNotificationDetails(
          'transfer_confirmations',
          tr('Transfer confirmations'),
          channelDescription: tr('Tells you when an outgoing transfer confirms.'),
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required AndroidNotificationDetails details,
  }) async {
    if (!_enabled) {
      return;
    }
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: details),
      );
    } catch (error) {
      debugPrint('Could not show a notification: $error');
    }
  }
}
