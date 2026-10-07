import 'dart:async';

import 'package:flutter/material.dart';

import '../core/utils/app_log.dart';
import '../core/utils/formatters.dart';
import '../data/networks/network_config.dart';
import '../data/wallet/wallet_storage.dart';

/// How long the app may stay in the background before it locks itself.
///
/// [seconds] is `null` for "Never"; `0` locks the moment the app is hidden.
enum AutoLockDelay {
  immediately('Immediately', 0),
  seconds30('After 30 seconds', 30),
  minute1('After 1 minute', 60),
  minutes5('After 5 minutes', 300),
  never('Never', null);

  const AutoLockDelay(this.label, this.seconds);

  final String label;
  final int? seconds;
}

/// User preferences: theme, display currency, active network and switches.
class SettingsController extends ChangeNotifier {
  SettingsController({this._storage = const WalletStorage()});

  final WalletStorage _storage;

  ThemeMode _themeMode = ThemeMode.system;
  AppCurrency _currency = AppCurrency.usd;
  NetworkConfig _network = NetworkCatalog.bitcoin;
  int? _autoLockSeconds = AutoLockDelay.minute1.seconds;
  bool _notificationsEnabled = false;

  ThemeMode get themeMode => _themeMode;
  AppCurrency get currency => _currency;

  /// The blockchain currently being viewed.
  NetworkConfig get network => _network;

  /// Seconds the app may stay backgrounded before locking, or `null` for never.
  int? get autoLockSeconds => _autoLockSeconds;

  /// Whether the app should lock itself after being backgrounded.
  bool get autoLockEnabled => _autoLockSeconds != null;

  /// Whether confirmation notifications are turned on.
  bool get notificationsEnabled => _notificationsEnabled;

  /// Restores the persisted network and currency choices at app start.
  Future<void> load() async {
    try {
      final String? id = await _storage.readNetworkId();
      final String? code = await _storage.readCurrencyCode();
      final int? autoLock = await _storage.readAutoLockSeconds();
      final String? themeName = await _storage.readThemeMode();
      final bool? notifications = await _storage.readNotificationsEnabled();
      bool changed = false;

      if (id != null) {
        final NetworkConfig network = NetworkCatalog.byId(id);
        if (network != _network) {
          _network = network;
          changed = true;
        }
      }

      final AppCurrency currency = AppCurrency.values.firstWhere(
        (AppCurrency value) => value.code == code,
        orElse: () => _currency,
      );
      if (currency != _currency) {
        _currency = currency;
        changed = true;
      }

      if (themeName != null) {
        final ThemeMode theme = ThemeMode.values.firstWhere(
          (ThemeMode value) => value.name == themeName,
          orElse: () => _themeMode,
        );
        if (theme != _themeMode) {
          _themeMode = theme;
          changed = true;
        }
      }

      if (autoLock != null) {
        // Storage uses -1 for an explicit "Never"; `null` there means the user
        // has not chosen yet, so the default stands.
        final int? seconds = autoLock < 0 ? null : autoLock;
        if (seconds != _autoLockSeconds) {
          _autoLockSeconds = seconds;
          changed = true;
        }
      }

      if (notifications != null && notifications != _notificationsEnabled) {
        _notificationsEnabled = notifications;
        changed = true;
      }

      if (changed) {
        notifyListeners();
      }
    } catch (error, stackTrace) {
      // Preferences are not critical: fall back to the defaults rather than
      // blocking app start.
      AppLog.warning('Could not restore settings', error, stackTrace);
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();
    unawaited(_storage.writeThemeMode(mode.name));
  }

  /// Switches the display currency and persists the choice.
  void setCurrency(AppCurrency currency) {
    if (_currency == currency) {
      return;
    }
    _currency = currency;
    notifyListeners();
    unawaited(_storage.writeCurrencyCode(currency.code));
  }

  /// Switches the active network and persists the choice.
  void setNetwork(NetworkConfig network) {
    if (_network == network) {
      return;
    }
    _network = network;
    notifyListeners();
    unawaited(_storage.writeNetworkId(network.id));
  }

  /// Changes how long the app may stay backgrounded before locking itself.
  void setAutoLockDelay(AutoLockDelay delay) {
    if (_autoLockSeconds == delay.seconds) {
      return;
    }
    _autoLockSeconds = delay.seconds;
    notifyListeners();
    unawaited(_storage.writeAutoLockSeconds(delay.seconds));
  }

  /// Turns confirmation notifications on or off and persists the choice.
  void setNotificationsEnabled(bool enabled) {
    if (_notificationsEnabled == enabled) {
      return;
    }
    _notificationsEnabled = enabled;
    notifyListeners();
    unawaited(_storage.writeNotificationsEnabled(enabled));
  }
}
