import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unlock_throttle.dart';

/// Local device storage for the wallet and small preferences.
///
/// The **AES-GCM payload** produced by `SeedVault` is persisted in the platform
/// keystore (`flutter_secure_storage`: Android Keystore / iOS Keychain), never
/// in the clear and never in `shared_preferences`. The recovery phrase itself
/// is never written in the clear.
///
/// Non-sensitive preferences (active network, display currency, creation
/// timestamp) stay in `shared_preferences`, which is not encrypted but holds
/// nothing secret.
class WalletStorage {
  const WalletStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const String _vaultKey = 'nova.wallet.vault';
  static const String _createdAtKey = 'nova.wallet.createdAt';
  static const String _networkKey = 'nova.wallet.network';
  static const String _currencyKey = 'nova.wallet.currency';
  static const String _throttleKey = 'nova.wallet.unlockThrottle';
  static const String _autoLockKey = 'nova.wallet.autoLockSeconds';
  static const String _themeKey = 'nova.wallet.themeMode';
  static const String _contactsKey = 'nova.wallet.contacts';
  static const String _cachePrefix = 'nova.wallet.cache.';
  static const String _notificationsKey = 'nova.wallet.notificationsEnabled';
  static const String _watchedTxsKey = 'nova.wallet.watchedTxs';
  static const String _accountIndexKey = 'nova.wallet.accountIndex';
  static const String _accountCountKey = 'nova.wallet.accountCount';
  static const String _hideBalancesKey = 'nova.wallet.hideBalances';
  static const String _accountNamesKey = 'nova.wallet.accountNames';
  static const String _txNotesKey = 'nova.wallet.txNotes';

  /// The encrypted recovery phrase, or `null` when no wallet exists.
  Future<String?> readVault() async {
    final String? vault = await _secureStorage.read(key: _vaultKey);
    return (vault == null || vault.isEmpty) ? null : vault;
  }

  Future<DateTime?> readCreatedAt() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_createdAtKey) ?? '');
  }

  Future<void> writeVault(String payload, DateTime createdAt) async {
    await _secureStorage.write(key: _vaultKey, value: payload);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_createdAtKey, createdAt.toIso8601String());
  }

  /// Remembers which network the user was last on.
  Future<String?> readNetworkId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_networkKey);
  }

  Future<void> writeNetworkId(String id) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_networkKey, id);
  }

  /// Remembers the fiat currency prices are displayed in.
  Future<String?> readCurrencyCode() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currencyKey);
  }

  Future<void> writeCurrencyCode(String code) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currencyKey, code);
  }

  /// Reads the persisted PIN-attempt backoff.
  ///
  /// A corrupt or missing value yields [UnlockThrottle.none] rather than
  /// locking the user out, so a failed write can never brick the wallet.
  Future<UnlockThrottle> readThrottle() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_throttleKey);
    if (raw == null || raw.isEmpty) {
      return UnlockThrottle.none;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      return UnlockThrottle.fromJson(
        decoded is Map ? decoded.cast<String, Object?>() : null,
      );
    } on FormatException {
      return UnlockThrottle.none;
    }
  }

  Future<void> writeThrottle(UnlockThrottle throttle) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (throttle.failedAttempts == 0 && throttle.lockedUntil == null) {
      await prefs.remove(_throttleKey);
      return;
    }
    await prefs.setString(_throttleKey, jsonEncode(throttle.toJson()));
  }

  /// Seconds a backgrounded app may stay unlocked before it locks itself.
  ///
  /// Returns `null` when the user has never chosen a value, and `-1` for the
  /// explicit "Never" choice (which must survive as a real preference rather
  /// than fall back to the default).
  Future<int?> readAutoLockSeconds() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_autoLockKey)) {
      return null;
    }
    return prefs.getInt(_autoLockKey);
  }

  /// Persists [seconds]; `null` is stored as `-1` meaning "Never".
  Future<void> writeAutoLockSeconds(int? seconds) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoLockKey, seconds ?? -1);
  }

  /// The persisted [ThemeMode] name (`system` / `light` / `dark`).
  Future<String?> readThemeMode() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeKey);
  }

  Future<void> writeThemeMode(String name) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, name);
  }

  /// Whether the user turned transfer-confirmation notifications on, or `null`
  /// when they have never chosen (defaults to off).
  Future<bool?> readNotificationsEnabled() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsKey);
  }

  Future<void> writeNotificationsEnabled(bool enabled) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsKey, enabled);
  }

  /// Hashes of outgoing transfers the app is still waiting to see confirm, so a
  /// confirmation that arrives after a restart still fires once.
  Future<List<String>> readWatchedTxs() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_watchedTxsKey) ?? const <String>[];
  }

  Future<void> writeWatchedTxs(List<String> hashes) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_watchedTxsKey, hashes);
  }

  /// The BIP-44 account index the wallet is currently using. Non-secret: which
  /// of the derived accounts is active carries no key material. Defaults to 0.
  Future<int> readAccountIndex() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int raw = prefs.getInt(_accountIndexKey) ?? 0;
    return raw < 0 ? 0 : raw;
  }

  Future<void> writeAccountIndex(int index) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accountIndexKey, index);
  }

  /// How many accounts the user has created (at least 1). Only accounts below
  /// this count are offered by the picker.
  Future<int> readAccountCount() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int raw = prefs.getInt(_accountCountKey) ?? 1;
    return raw < 1 ? 1 : raw;
  }

  Future<void> writeAccountCount(int count) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accountCountKey, count);
  }

  /// Whether privacy mode (amounts shown as dots) is on; `null` if never set.
  Future<bool?> readHideBalances() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hideBalancesKey);
  }

  Future<void> writeHideBalances(bool hidden) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideBalancesKey, hidden);
  }

  /// User-chosen account names as a JSON object `{"<index>": "name"}`.
  Future<String?> readAccountNames() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accountNamesKey);
  }

  Future<void> writeAccountNames(String json) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountNamesKey, json);
  }

  /// Local transaction notes as a JSON object `{"<hash>": "text"}`.
  Future<String?> readTxNotes() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_txNotesKey);
  }

  Future<void> writeTxNotes(String json) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_txNotesKey, json);
  }

  /// Reads the cached snapshot JSON for [id] (a network id), if any.
  Future<String?> readCache(String id) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_cachePrefix$id');
  }

  Future<void> writeCache(String id, String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_cachePrefix$id', value);
  }

  /// The address book as a JSON array. Kept across [clear] on purpose.
  Future<String?> readContacts() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_contactsKey);
  }

  Future<void> writeContacts(String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contactsKey, value);
  }

  /// Removes the wallet. The selected network is intentionally preserved.
  Future<void> clear() async {
    await _secureStorage.delete(key: _vaultKey);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_createdAtKey);
    await prefs.remove(_throttleKey);
    await prefs.remove(_watchedTxsKey);
    await prefs.remove(_accountIndexKey);
    await prefs.remove(_accountCountKey);
    // Account names and notes describe this wallet's accounts and history;
    // they go with it.
    await prefs.remove(_accountNamesKey);
    await prefs.remove(_txNotesKey);
    for (final String key in prefs.getKeys().toList()) {
      if (key.startsWith(_cachePrefix)) {
        await prefs.remove(key);
      }
    }
  }
}
