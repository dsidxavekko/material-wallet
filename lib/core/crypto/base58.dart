import 'dart:typed_data';

import 'hashing.dart';

/// Base58 encoding with the Bitcoin alphabet.
///
/// Solana shows addresses as the base58 form of the 32-byte ed25519 public key;
/// Bitcoin legacy addresses are base58check. The decoder is used to validate a
/// recipient before sending.
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

  /// Decodes [input], or returns `null` when it contains a character outside
  /// the Base58 alphabet.
  static Uint8List? decode(String input) {
    if (input.isEmpty) {
      return null;
    }

    int zeros = 0;
    while (zeros < input.length && input[zeros] == '1') {
      zeros++;
    }

    // Base-58 → base-256, least significant byte first.
    final List<int> little = <int>[];
    for (int i = zeros; i < input.length; i++) {
      final int value = _alphabet.indexOf(input[i]);
      if (value == -1) {
        return null;
      }
      int carry = value;
      for (int j = 0; j < little.length; j++) {
        carry += little[j] * 58;
        little[j] = carry & 0xff;
        carry >>= 8;
      }
      while (carry > 0) {
        little.add(carry & 0xff);
        carry >>= 8;
      }
    }

    final Uint8List result = Uint8List(zeros + little.length);
    for (int i = 0; i < little.length; i++) {
      result[zeros + little.length - 1 - i] = little[i];
    }
    return result;
  }

  /// Decodes a Base58Check string and verifies its 4-byte double-SHA256
  /// checksum, returning the payload (address version + hash) or `null`.
  static Uint8List? decodeCheck(String input) {
    final Uint8List? bytes = decode(input);
    if (bytes == null || bytes.length < 5) {
      return null;
    }
    final int payloadLength = bytes.length - 4;
    final Uint8List payload = bytes.sublist(0, payloadLength);
    final Uint8List checksum = bytes.sublist(payloadLength);
    final Uint8List hash = Hashing.sha256(Hashing.sha256(payload));
    for (int i = 0; i < 4; i++) {
      if (hash[i] != checksum[i]) {
        return null;
      }
    }
    return payload;
  }
}
