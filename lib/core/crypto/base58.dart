import 'dart:typed_data';

/// Base58 encoding with the Bitcoin alphabet.
///
/// Solana shows addresses as the base58 form of the 32-byte ed25519 public key.
class Base58 {
  const Base58._();

  static const String _alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  /// Encodes [bytes]; leading zero bytes become leading `1` characters.
  static String encode(Uint8List bytes) {
    int zeros = 0;
    while (zeros < bytes.length && bytes[zeros] == 0) {
      zeros++;
    }

    // Base-256 → base-58, least significant digit first.
    final List<int> digits = <int>[];
    for (int i = zeros; i < bytes.length; i++) {
      int carry = bytes[i];
      for (int j = 0; j < digits.length; j++) {
        carry += digits[j] << 8;
        digits[j] = carry % 58;
        carry ~/= 58;
      }
      while (carry > 0) {
        digits.add(carry % 58);
        carry ~/= 58;
      }
    }

    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < zeros; i++) {
      buffer.write('1');
    }
    for (int i = digits.length - 1; i >= 0; i--) {
      buffer.write(_alphabet[digits[i]]);
    }
    return buffer.toString();
  }
}
