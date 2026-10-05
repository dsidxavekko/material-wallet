import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pointycastle/export.dart';

import 'pbkdf2.dart';

/// Thrown when a vault payload cannot be decrypted (wrong PIN or tampering).
class SeedVaultException implements Exception {
  const SeedVaultException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Encrypts the BIP-39 recovery phrase with a user supplied PIN.
///
/// * **Key derivation** — PBKDF2-HMAC-SHA256, [iterations] rounds, 16-byte salt
/// * **Encryption** — AES-256-GCM, 12-byte nonce, 128-bit authentication tag
///
/// Because GCM is authenticated, a wrong PIN cannot silently "succeed": the tag
/// check fails and [decrypt] throws [SeedVaultException].
///
/// The output is a small self-describing JSON blob, so the parameters can be
/// raised later without breaking existing vaults.
///
/// The app uses the asynchronous [encryptAsync] / [decryptAsync]: they run the
/// 600k-round derivation through the browser's Web Crypto API on the web,
/// where the pure-Dart PBKDF2 would otherwise freeze the tab for a long time.
class SeedVault {
  const SeedVault._();

  static const int version = 1;

  /// PBKDF2-HMAC-SHA256 rounds for newly created vaults (OWASP 2023 guidance).
  /// Existing vaults keep working: their iteration count is stored in the
  /// payload and read back on decrypt, so this only affects new wallets.
  static const int iterations = 600000;

  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _keyLength = 32;
  static const int _tagBits = 128;

  /// Upper bound on [iterations] read from a payload, so a tampered vault can
  /// not force a denial-of-service (very long) derivation at unlock time.
  static const int _maxRounds = 10000000;

  /// Encrypts [mnemonic] under [pin]; returns a JSON string ready to store.
  ///
  /// Synchronous counterpart of [encryptAsync], used by tests to build vaults
  /// without spinning up a Future. Production code should use [encryptAsync].
  @visibleForTesting
  static String encrypt(
    String mnemonic,
    String pin, {
    int rounds = iterations,
  }) {
    final Uint8List salt = _randomBytes(_saltLength);
    final Uint8List nonce = _randomBytes(_nonceLength);
    final Uint8List key = deriveKey(pin, salt, rounds);
    return _seal(mnemonic, key, salt, nonce, rounds);
  }

  /// Decrypts a payload produced by [encrypt].
  ///
  /// Throws [SeedVaultException] when the PIN is wrong or the payload was
  /// modified. Synchronous counterpart of [decryptAsync], for tests.
  @visibleForTesting
  static String decrypt(String payload, String pin) {
    final _VaultPayload parsed = _parse(payload);
    return _open(parsed, deriveKey(pin, parsed.salt, parsed.rounds));
  }

  // --- asynchronous API (used by the app) ----------------------------------

  /// Like [encrypt], but derives the key off the UI thread.
  ///
  /// Uses Web Crypto on the web and a cooperative pure-Dart derivation
  /// elsewhere, so the UI stays responsive while a 100k-round key is built.
  static Future<String> encryptAsync(
    String mnemonic,
    String pin, {
    int rounds = iterations,
  }) async {
    final Uint8List salt = _randomBytes(_saltLength);
    final Uint8List nonce = _randomBytes(_nonceLength);
    final Uint8List key = await deriveKeyAsync(pin, salt, rounds);
    return _seal(mnemonic, key, salt, nonce, rounds);
  }

  /// Like [decrypt], but derives the key off the UI thread.
  static Future<String> decryptAsync(String payload, String pin) async {
    final _VaultPayload parsed = _parse(payload);
    final Uint8List key = await deriveKeyAsync(pin, parsed.salt, parsed.rounds);
    return _open(parsed, key);
  }

  // --- key derivation -------------------------------------------------------

  /// Synchronous PBKDF2-HMAC-SHA256 derivation. Exposed for tests.
  @visibleForTesting
  static Uint8List deriveKey(String pin, Uint8List salt, int rounds) =>
      pbkdf2Sync(
        Pbkdf2Hash.sha256,
        Uint8List.fromList(utf8.encode(pin)),
        salt,
        rounds,
        _keyLength,
      );

  /// Platform-optimised [deriveKey] (Web Crypto on the web).
  static Future<Uint8List> deriveKeyAsync(
    String pin,
    Uint8List salt,
    int rounds,
  ) =>
      pbkdf2(
        hash: Pbkdf2Hash.sha256,
        password: Uint8List.fromList(utf8.encode(pin)),
        salt: salt,
        iterations: rounds,
        keyLength: _keyLength,
      );

  // --- internals ------------------------------------------------------------

  static String _seal(
    String mnemonic,
    Uint8List key,
    Uint8List salt,
    Uint8List nonce,
    int rounds,
  ) {
    final GCMBlockCipher cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)),
      );

    // GCMBlockCipher appends the authentication tag to the ciphertext.
    final Uint8List sealed =
        cipher.process(Uint8List.fromList(utf8.encode(mnemonic)));

    return jsonEncode(<String, Object>{
      'v': version,
      'iterations': rounds,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'data': base64Encode(sealed),
    });
  }

  static String _open(_VaultPayload payload, Uint8List key) {
    try {
      final GCMBlockCipher cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(key),
            _tagBits,
            payload.nonce,
            Uint8List(0),
          ),
        );
      return utf8.decode(cipher.process(payload.sealed));
    } catch (_) {
      throw const SeedVaultException('Wrong PIN — could not unlock the wallet.');
    }
  }

  static _VaultPayload _parse(String payload) {
    final Map<String, Object?> json;
    try {
      json = jsonDecode(payload) as Map<String, Object?>;
    } catch (_) {
      throw const SeedVaultException('Recovery phrase is corrupted.');
    }

    try {
      final int rounds = (json['iterations'] as num?)?.toInt() ?? iterations;
      if (rounds < 1 || rounds > _maxRounds) {
        throw const SeedVaultException('Recovery phrase is corrupted.');
      }
      return _VaultPayload(
        salt: base64Decode(json['salt']! as String),
        nonce: base64Decode(json['nonce']! as String),
        sealed: base64Decode(json['data']! as String),
        rounds: rounds,
      );
    } on SeedVaultException {
      rethrow;
    } catch (_) {
      throw const SeedVaultException('Recovery phrase is corrupted.');
    }
  }

  static Uint8List _randomBytes(int length) {
    final Random random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

/// Fields of an encrypted vault payload.
class _VaultPayload {
  const _VaultPayload({
    required this.salt,
    required this.nonce,
    required this.sealed,
    required this.rounds,
  });

  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List sealed;
  final int rounds;
}

