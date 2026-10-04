import 'package:local_auth/local_auth.dart';

/// Thin wrapper around the platform biometric prompt.
///
/// Every method fails soft (returns `false`) so the wallet keeps working on
/// platforms without biometrics — including the web build — and in tests.
class BiometricAuth {
  BiometricAuth({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// `true` when the device has biometric hardware with at least one enrolled
  /// fingerprint or face.
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) {
        return false;
      }
      final List<BiometricType> enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Prompts for a fingerprint/face. Returns `true` when the user passed.
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: false,
      );
    } catch (_) {
      return false;
    }
  }
}
