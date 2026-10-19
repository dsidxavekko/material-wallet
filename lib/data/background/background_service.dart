import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/utils/app_log.dart';
import '../networks/chain_api.dart';
import '../notifications/notification_service.dart';
import 'background_checker.dart';

/// Name of the periodic job; registering it again replaces the old one.
const String _jobName = 'material_wallet_background_check';
const String _taskName = 'check_addresses';

/// Entry point the Android WorkManager starts in a fresh isolate, with the app
/// closed. Must be a top-level function kept by the tree shaker.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    DartPluginRegistrant.ensureInitialized();
    final NotificationService notifications = NotificationService();
    final ChainApi chainApi = ChainApi();
    try {
      await notifications.initializeForBackground();
      final BackgroundChecker checker = BackgroundChecker(
        chainApi: chainApi,
        sink: notifications.showIncomingOrConfirmed,
      );
      await checker.run();
      return true;
    } catch (error, stackTrace) {
      AppLog.error('Background check failed', error, stackTrace);
      // `false` asks WorkManager to retry with its back-off.
      return false;
    } finally {
      chainApi.dispose();
    }
  });
}

/// Switches the periodic background check on and off.
///
/// Android only. WorkManager cannot run more often than every 15 minutes and
/// the system may delay a run further to save battery, so this is "within the
/// next quarter of an hour or so", not instant — the foreground app still
/// reacts within seconds.
class BackgroundService {
  const BackgroundService();

  /// `true` where a background worker can exist at all.
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool _initialized = false;

  /// Starts (or refreshes) the periodic job. Safe to call on every launch.
  Future<void> enable() async {
    if (!supported) {
      return;
    }
    try {
      if (!_initialized) {
        await Workmanager().initialize(backgroundDispatcher);
        _initialized = true;
      }
      await Workmanager().registerPeriodicTask(
        _jobName,
        _taskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (error, stackTrace) {
      AppLog.warning('Could not start background checks', error, stackTrace);
    }
  }

  /// Cancels the job; nothing runs in the background afterwards.
  Future<void> disable() async {
    if (!supported) {
      return;
    }
    try {
      await Workmanager().cancelByUniqueName(_jobName);
    } catch (error, stackTrace) {
      AppLog.warning('Could not stop background checks', error, stackTrace);
    }
  }
}
