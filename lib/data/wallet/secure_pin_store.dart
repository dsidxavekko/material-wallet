import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown when the fingerprint-bound key can no longer be used because the
/// device's fingerprints changed (or the key is gone). Nothing is stored any
/// more; the user has to unlock with the password and turn fingerprint unlock
/// on again.
class BoundSecretInvalidated implements Exception {
  const BoundSecretInvalidated();

  @override
  String toString() => 'Fingerprint unlock was reset because the fingerprints '
      'on this device changed.';
}

/// Keeps the wallet password behind the fingerprint — enforced by the secure
/// hardware, not by the app.
///
/// On Android the password is encrypted with an AES-GCM key held in the
/// Keystore that is created with user authentication required and no validity
/// window: **every** decryption needs a fresh strong-biometric authentication
/// handed to the key through a `CryptoObject`. A read therefore *is* the proof
/// that a finger was presented — there is no separate "did the prompt pass?"
/// flag to flip, and neither malware inside the app process nor a root shell
/// reading app storage can obtain the password without the finger. Enrolling a
/// new fingerprint invalidates the key.
///
/// (Before this, the password sat in `flutter_secure_storage`, whose Keystore
/// key is not tied to authentication: the fingerprint prompt was a UI gate only.)
///
/// Every call is best-effort: where the channel does not exist — the web
/// build, other platforms, tests — the store reports "not supported" and no-ops.
class SecurePinStore {
  const SecurePinStore();

  static const MethodChannel _channel = MethodChannel('material_wallet/bound_secret');

  /// Non-secret marker that a bound secret exists, so the lock screen knows to
  /// offer the fingerprint without showing a prompt just to find out.
  static const String _flagKey = 'nova.wallet.biometric.bound';

  /// Where the unbound copy used to live; removed on sight.
  static const String _legacyKey = 'nova.wallet.biometric.pin';

  /// `true` when the device has strong biometric hardware with an enrolled
  /// fingerprint and this platform can bind a key to it.
  Future<bool> get isSupported async {
    try {
      return await _channel.invokeMethod<String>('status') == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Whether a fingerprint-bound password is stored. Never prompts.
  Future<bool> get hasPin async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_flagKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Encrypts [pin] under a new fingerprint-bound key. Shows the fingerprint
  /// prompt; returns `true` only when the secret was actually stored.
  Future<bool> write(String pin, {String reason = 'Enable fingerprint unlock'}) async {
    try {
      await _channel.invokeMethod<void>('write', <String, Object?>{
        'secret': pin,
        'title': 'Material Wallet',
        'subtitle': reason,
        'cancel': 'Cancel',
      });
    } catch (_) {
      await _clearNative();
      return false;
    }
    await _setFlag(true);
    return true;
  }

  /// Releases the password after a fingerprint. `null` when the prompt was
  /// cancelled or failed; throws [BoundSecretInvalidated] when the key is dead.
  Future<String?> read({String reason = 'Unlock Material Wallet'}) async {
    try {
      return await _channel.invokeMethod<String>('read', <String, Object?>{
        'title': 'Material Wallet',
        'subtitle': reason,
        'cancel': 'Cancel',
      });
    } on PlatformException catch (error) {
      if (error.code == 'invalidated') {
        await clear();
        throw const BoundSecretInvalidated();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Forgets the stored password (and any unbound copy an older version kept).
  Future<void> clear() async {
    await _clearNative();
    await _setFlag(false);
    await dropLegacy();
  }

  /// Deletes the pre-hardware-binding copy of the password, if there is one.
  Future<void> dropLegacy() async {
    try {
      await const FlutterSecureStorage().delete(key: _legacyKey);
    } catch (_) {
      // Nothing to clean up, or no secure storage here.
    }
  }

  Future<void> _clearNative() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (_) {
      // No channel on this platform.
    }
  }

  Future<void> _setFlag(bool value) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool(_flagKey, true);
      } else {
        await prefs.remove(_flagKey);
      }
    } catch (_) {
      // The flag is a convenience; without it the toggle just reads "off".
    }
  }
}
