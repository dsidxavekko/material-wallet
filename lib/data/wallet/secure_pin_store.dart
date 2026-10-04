import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the wallet PIN in the platform keystore (Android Keystore / iOS
/// Keychain / browser storage).
///
/// The PIN is replayed after a successful biometric check so the user can
/// unlock with a fingerprint instead of typing it. Every call is best-effort:
/// on platforms without secure storage, or in tests, it silently no-ops.
class SecurePinStore {
  const SecurePinStore({this._storage = const FlutterSecureStorage()});

  final FlutterSecureStorage _storage;

  static const String _key = 'nova.wallet.biometric.pin';

  Future<void> write(String pin) async {
    try {
      await _storage.write(key: _key, value: pin);
    } catch (_) {
      // Ignore — biometric unlock simply stays unavailable.
    }
  }

  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing to clean up.
    }
  }

  Future<bool> get hasPin async => (await read()) != null;
}
