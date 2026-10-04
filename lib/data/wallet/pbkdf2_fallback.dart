import 'dart:async';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Hash functions the wallet derives keys with.
enum Pbkdf2Hash { sha256, sha512 }

/// Pure-Dart PBKDF2 (RFC 2898) built on `pointycastle`.
///
/// Used directly on native platforms and as the fallback on the web when the
/// browser's Web Crypto API is unavailable.
///
/// The output is byte-for-byte identical to the browser's
/// `crypto.subtle.deriveBits` for the same parameters, so a vault created on
/// one platform can be opened on another.
Uint8List pbkdf2Sync(
  Pbkdf2Hash hash,
  Uint8List password,
  Uint8List salt,
  int iterations,
  int keyLength,
) {
  final PBKDF2KeyDerivator derivator =
      PBKDF2KeyDerivator(HMac(_digest(hash), _blockSize(hash)))
        ..init(Pbkdf2Parameters(salt, iterations, keyLength));
  return derivator.process(password);
}

/// Like [pbkdf2Sync] but yields to the event loop every [yieldEvery] rounds.
///
/// A 600k-iteration run would otherwise block the isolate for seconds and
/// freeze the UI. [HMac] resets itself in `doFinal`, so a single instance can
/// be reused for the whole chain.
Future<Uint8List> pbkdf2Chunked(
  Pbkdf2Hash hash,
  Uint8List password,
  Uint8List salt,
  int iterations,
  int keyLength, {
  int yieldEvery = 2000,
}) async {
  final int digestSize = _digestSize(hash);
  final HMac hmac = HMac(_digest(hash), _blockSize(hash))
    ..init(KeyParameter(password));

  final int blockCount = (keyLength + digestSize - 1) ~/ digestSize;
  final Uint8List output = Uint8List(blockCount * digestSize);
  final Uint8List message = Uint8List(salt.length + 4)
    ..setRange(0, salt.length, salt);

  for (int block = 1; block <= blockCount; block++) {
    // INT_32_BE(block index), appended to the salt.
    message[salt.length] = (block >> 24) & 0xFF;
    message[salt.length + 1] = (block >> 16) & 0xFF;
    message[salt.length + 2] = (block >> 8) & 0xFF;
    message[salt.length + 3] = block & 0xFF;

    Uint8List u = hmac.process(message);
    final Uint8List accumulator = Uint8List.fromList(u);

    for (int round = 1; round < iterations; round++) {
      u = hmac.process(u);
      for (int i = 0; i < digestSize; i++) {
        accumulator[i] ^= u[i];
      }
      if (round % yieldEvery == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    output.setRange((block - 1) * digestSize, block * digestSize, accumulator);
  }

  return keyLength == output.length
      ? output
      : Uint8List.sublistView(output, 0, keyLength);
}

Digest _digest(Pbkdf2Hash hash) => switch (hash) {
      Pbkdf2Hash.sha256 => SHA256Digest(),
      Pbkdf2Hash.sha512 => SHA512Digest(),
    };

/// HMAC block size in bytes (the internal block length of the hash).
int _blockSize(Pbkdf2Hash hash) => hash == Pbkdf2Hash.sha512 ? 128 : 64;

/// Digest length in bytes.
int _digestSize(Pbkdf2Hash hash) => hash == Pbkdf2Hash.sha512 ? 64 : 32;
