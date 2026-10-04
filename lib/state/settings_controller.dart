import 'dart:async';

import 'package:flutter/material.dart';

import '../core/utils/formatters.dart';
import '../data/networks/network_config.dart';
import '../data/wallet/wallet_storage.dart';

/// User preferences: theme, display currency, active network and switches.
class SettingsController extends ChangeNotifier {
  SettingsController({this._storage = const WalletStorage()});

  final WalletStorage _storage;

  ThemeMode _themeMode = ThemeMode.system;
  AppCurrency _currency = AppCurrency.usd;
  NetworkConfig _network = NetworkCatalog.bitcoin;

  ThemeMode get themeMode => _themeMode;
  AppCurrency get currency => _currency;

  /// The blockchain currently being viewed.
  NetworkConfig get network => _network;

  /// Restores the persisted network and currency choices at app start.
  Future<void> load() async {
    final String? id = await _storage.readNetworkId();
    final String? code = await _storage.readCurrencyCode();
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

    if (changed) {
      notifyListeners();
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();
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
}
