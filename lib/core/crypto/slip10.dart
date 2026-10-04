import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// [SLIP-0010](https://github.com/satoshilabs/slips/blob/master/slip-0010.md)
/// hierarchical key derivation for ed25519.
///
/// Unlike BIP-32, ed25519 only supports *hardened* children, so every path
/// component is hardened automatically. Solana wallets use `m/44'/501'/0'/0'`.
class Slip10 {
  const Slip10._();

  /// Phantom/Solflare-compatible Solana path: `m/44'/501'/0'/0'`.
  static const List<int> solanaPath = <int>[44, 501, 0, 0];

  /// Petra/Aptos-CLI-compatible path: `m/44'/637'/0'/0'/0'`.
  static const List<int> aptosPath = <int>[44, 637, 0, 0, 0];

  static final Uint8List _curveKey =
      Uint8List.fromList(utf8.encode('ed25519 seed'));

  /// 32-byte ed25519 private seed for [path], derived from a BIP-39 [seed].
  static Uint8List deriveEd25519Seed(Uint8List seed, List<int> path) {
    Uint8List digest = _hmacSha512(_curveKey, seed);
    Uint8List key = Uint8List.fromList(digest.sublist(0, 32));
    Uint8List chainCode = Uint8List.fromList(digest.sublist(32));

    // 0x00 || key || ser32(hardened index)
    final Uint8List message = Uint8List(37);
    for (final int index in path) {
      message[0] = 0;
      message.setRange(1, 33, key);
      final int hardened = 0x80000000 | index;
      message[33] = (hardened >> 24) & 0xFF;
      message[34] = (hardened >> 16) & 0xFF;
      message[35] = (hardened >> 8) & 0xFF;
      message[36] = hardened & 0xFF;

      digest = _hmacSha512(chainCode, message);
      key = Uint8List.fromList(digest.sublist(0, 32));
      chainCode = Uint8List.fromList(digest.sublist(32));
    }

    return key;
  }

  static Uint8List _hmacSha512(Uint8List key, Uint8List data) {
    final HMac mac = HMac(SHA512Digest(), 128)..init(KeyParameter(key));
    return mac.process(data);
  }
}
