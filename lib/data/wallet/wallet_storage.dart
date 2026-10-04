import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Removes the wallet. The selected network is intentionally preserved.
  Future<void> clear() async {
    await _secureStorage.delete(key: _vaultKey);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_createdAtKey);
  }
}
