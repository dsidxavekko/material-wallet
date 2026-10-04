import 'dart:typed_data';

import 'pbkdf2_fallback.dart';

/// Derives a key with PBKDF2 on native platforms.
///
/// Native platforms have no Web Crypto, so the pure-Dart implementation is
/// used. It yields to the event loop periodically so long derivations keep the
/// UI responsive instead of freezing it.
Future<Uint8List> pbkdf2({
  required Pbkdf2Hash hash,
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int keyLength,
}) =>
    pbkdf2Chunked(hash, password, salt, iterations, keyLength);
