/// Platform-selected PBKDF2 implementation.
///
/// * **Web** — the browser's Web Crypto API (`crypto.subtle`), which is native
///   code: a 600k-iteration key is derived in milliseconds and never blocks
///   the UI thread. Falls back to pure Dart on insecure origins.
/// * **Native** — pure-Dart `pointycastle`, yielding to the event loop.
///
/// Both paths produce identical bytes, so vaults move freely between them.
library;

// Both implementations expose the same entry point:
//
//   Future<Uint8List> pbkdf2({
//     required Pbkdf2Hash hash,
//     required Uint8List password,
//     required Uint8List salt,
//     required int iterations,
//     required int keyLength,
//   })
export 'pbkdf2_fallback.dart' show Pbkdf2Hash, pbkdf2Sync;
export 'pbkdf2_native.dart' if (dart.library.js_interop) 'pbkdf2_web.dart';
