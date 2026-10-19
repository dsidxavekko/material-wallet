import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/utils/app_log.dart';
import '../core/utils/formatters.dart';
import '../data/networks/network_config.dart';
import '../data/wallet/wallet_entry.dart';
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
  bool _hideBalances = false;
  Map<String, String> _accountNames = const <String, String>{};

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

  /// Privacy mode: amounts are shown as dots on every screen.
  bool get hideBalances => _hideBalances;

  /// Names are stored by `index` for the first wallet (as before wallets could
  /// be added) and by `walletId:index` for every other.
  static String _nameKey(int index, String walletId) =>
      walletId == primaryWalletId ? '$index' : '$walletId:$index';

  /// The display name of account [index] in wallet [walletId]: the user's own,
  /// else `Account N`.
  String accountName(int index, {String walletId = primaryWalletId}) =>
      _accountNames[_nameKey(index, walletId)] ?? 'Account ${index + 1}';

  /// Whether the user gave account [index] a name of their own.
  bool hasCustomAccountName(int index, {String walletId = primaryWalletId}) =>
      _accountNames.containsKey(_nameKey(index, walletId));

  /// Restores the persisted network and currency choices at app start.
  Future<void> load() async {
    try {
      final String? id = await _storage.readNetworkId();
      final String? code = await _storage.readCurrencyCode();
      final int? autoLock = await _storage.readAutoLockSeconds();
      final String? themeName = await _storage.readThemeMode();
      final bool? notifications = await _storage.readNotificationsEnabled();
      final bool? hide = await _storage.readHideBalances();
      final String? namesJson = await _storage.readAccountNames();
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

      if (hide != null && hide != _hideBalances) {
        _hideBalances = hide;
        changed = true;
      }

      final Map<String, String> names = _decodeNames(namesJson);
      if (names.length != _accountNames.length ||
          names.entries.any(
            (MapEntry<String, String> e) => _accountNames[e.key] != e.value,
          )) {
        _accountNames = names;
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

  /// Turns privacy mode on or off and persists the choice.
  void setHideBalances(bool hidden) {
    if (_hideBalances == hidden) {
      return;
    }
    _hideBalances = hidden;
    notifyListeners();
    unawaited(_storage.writeHideBalances(hidden));
  }

  /// Names account [index] of wallet [walletId]; an empty [name] restores the
  /// default.
  void renameAccount(
    int index,
    String name, {
    String walletId = primaryWalletId,
  }) {
    final String clean = name.trim();
    final String key = _nameKey(index, walletId);
    final Map<String, String> next = Map<String, String>.of(_accountNames);
    if (clean.isEmpty) {
      next.remove(key);
    } else {
      next[key] = clean.length > 30 ? clean.substring(0, 30) : clean;
    }
    _accountNames = next;
    notifyListeners();
    unawaited(_storage.writeAccountNames(jsonEncode(next)));
  }

  static Map<String, String> _decodeNames(String? json) {
    if (json == null || json.isEmpty) {
      return const <String, String>{};
    }
    try {
      final Object? decoded = jsonDecode(json);
      if (decoded is! Map) {
        return const <String, String>{};
      }
      return <String, String>{
        for (final MapEntry<Object?, Object?> e in decoded.entries)
          if (e.key is String && e.value is String)
            e.key! as String: e.value! as String,
      };
    } on FormatException {
      return const <String, String>{};
    }
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
