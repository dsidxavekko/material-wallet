import 'dart:typed_data';

import 'package:pointycastle/digests/keccak.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha3.dart';

/// Thin wrappers around the hash functions needed to derive crypto addresses.
class Hashing {
  const Hashing._();

  static Uint8List sha256(Uint8List data) => SHA256Digest().process(data);

  static Uint8List ripemd160(Uint8List data) => RIPEMD160Digest().process(data);

  static Uint8List keccak256(Uint8List data) => KeccakDigest(256).process(data);

  /// FIPS-202 SHA3-256 (used by Aptos, not to be confused with [keccak256]).
  static Uint8List sha3_256(Uint8List data) => SHA3Digest(256).process(data);

  /// `RIPEMD160(SHA256(data))` — the *hash160* used by Bitcoin addresses.
  static Uint8List hash160(Uint8List data) => ripemd160(sha256(data));
}
