import 'dart:convert';
import 'dart:typed_data';

import 'package:bip32/bip32.dart';
import 'package:convert/convert.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

import '../../core/crypto/base58.dart';
import '../../core/crypto/bech32.dart';
import '../../core/crypto/hashing.dart';
import '../../core/crypto/slip10.dart';
import 'pbkdf2.dart';

/// Derives **real** cryptocurrency addresses from a BIP-39 recovery phrase.
///
/// * **Bitcoin** — BIP-84 path `m/84'/0'/0'/0/0`, native SegWit P2WPKH (`bc1q…`)
/// * **Ethereum / EVM** — BIP-44 path `m/44'/60'/0'/0/0`, EIP-55 checksum (`0x…`)
///
/// Everything runs on-device in pure Dart — no network and no third-party
/// signer involved.
class AddressDeriver {
  const AddressDeriver._();

  static const String bitcoinPath = "m/84'/0'/0'/0/0";
  static const String evmPath = "m/44'/60'/0'/0/0";

  /// BIP-39 key-stretching parameters: PBKDF2-HMAC-SHA512, 2048 rounds, 64-byte
  /// output with the fixed salt `"mnemonic"` (empty passphrase).
  static const int _seedRounds = 2048;
  static const int _seedLength = 64;

  /// 64-byte BIP-39 seed.
  ///
  /// PBKDF2 with 2048 rounds is intentionally slow, so callers should compute
  /// this once and reuse it for every address instead of per-derivation.
  static Uint8List seedFromMnemonic(String mnemonic) => pbkdf2Sync(
        Pbkdf2Hash.sha512,
        Uint8List.fromList(utf8.encode(_normalize(mnemonic))),
        Uint8List.fromList(utf8.encode('mnemonic')),
        _seedRounds,
        _seedLength,
      );

  /// Platform-optimised [seedFromMnemonic] (Web Crypto on the web).
  static Future<Uint8List> seedFromMnemonicAsync(String mnemonic) => pbkdf2(
        hash: Pbkdf2Hash.sha512,
        password: Uint8List.fromList(utf8.encode(_normalize(mnemonic))),
        salt: Uint8List.fromList(utf8.encode('mnemonic')),
        iterations: _seedRounds,
        keyLength: _seedLength,
      );

  /// `bc1q…` (mainnet) or `tb1q…` (testnet) receive address.
  ///
  /// [hrp] is the bech32 human-readable part: `bc` for mainnet, `tb` for
  /// testnet, `bcrt` for regtest.
  static String bitcoinAddressFromSeed(Uint8List seed, {String hrp = 'bc'}) {
    final Uint8List publicKey =
        BIP32.fromSeed(seed).derivePath(bitcoinPath).publicKey;
    final Uint8List program = Hashing.hash160(publicKey);
    return Bech32.encodeSegwit(
      hrp: hrp,
      witnessVersion: 0,
      program: program,
    );
  }

  /// EIP-55 checksummed `0x…` receive address derived from a precomputed [seed].
  ///
  /// The same address is valid on every EVM chain (Ethereum, BNB Chain,
  /// Polygon, Avalanche C-Chain, …).
  static String ethereumAddressFromSeed(Uint8List seed) {
    final Uint8List privateKey =
        BIP32.fromSeed(seed).derivePath(evmPath).privateKey!;
    final Uint8List uncompressed = _uncompressedPublicKey(privateKey);
    final Uint8List hash = Hashing.keccak256(uncompressed.sublist(1));
    final String address = hex.encode(hash.sublist(hash.length - 20));
    return _toChecksumAddress(address);
  }

  /// Base58 Solana address (`HAgk…`) derived from a precomputed [seed].
  ///
  /// Solana uses ed25519 via SLIP-0010 (`m/44'/501'/0'/0'`) instead of the
  /// secp256k1 curves the other networks rely on.
  static String solanaAddressFromSeed(Uint8List seed) {
    final Uint8List privateSeed =
        Slip10.deriveEd25519Seed(seed, Slip10.solanaPath);
    final ed.PrivateKey privateKey = ed.newKeyFromSeed(privateSeed);
    final Uint8List publicKey =
        Uint8List.fromList(ed.public(privateKey).bytes);
    return Base58.encode(publicKey);
  }

  /// `0x…` Aptos account address derived from a precomputed [seed].
  ///
  /// Aptos also uses ed25519 (SLIP-0010, `m/44'/637'/0'/0'/0'`) but shows a
  /// 32-byte hex *authentication key*: `SHA3-256(publicKey ‖ 0x00)`, where the
  /// trailing `0x00` identifies the single-signer ed25519 scheme.
  static String aptosAddressFromSeed(Uint8List seed) {
    final Uint8List privateSeed =
        Slip10.deriveEd25519Seed(seed, Slip10.aptosPath);
    final ed.PrivateKey privateKey = ed.newKeyFromSeed(privateSeed);
    final Uint8List publicKey =
        Uint8List.fromList(ed.public(privateKey).bytes);
    final Uint8List authenticationKey = Hashing.sha3_256(
      Uint8List.fromList(<int>[...publicKey, 0]),
    );
    return '0x${hex.encode(authenticationKey)}';
  }

  /// Convenience helper that computes the seed on the fly.
  static String bitcoinAddress(String mnemonic, {String hrp = 'bc'}) =>
      bitcoinAddressFromSeed(seedFromMnemonic(mnemonic), hrp: hrp);

  /// Convenience helper that computes the seed on the fly.
  static String ethereumAddress(String mnemonic) =>
      ethereumAddressFromSeed(seedFromMnemonic(mnemonic));

  /// Lower-cases and collapses whitespace so pasted phrases validate reliably.
  static String _normalize(String mnemonic) => mnemonic
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .join(' ');

  /// 65-byte uncompressed public key (`0x04 || X || Y`) for [privateKey].
  ///
  /// `bip32` only exposes the compressed 33-byte form, but Ethereum hashes the
  /// full X‖Y coordinates, so the point is recomputed here.
  static Uint8List _uncompressedPublicKey(Uint8List privateKey) {
    final ECCurve_secp256k1 curve = ECCurve_secp256k1();
    final BigInt scalar = BigInt.parse(hex.encode(privateKey), radix: 16);
    final ECPoint point = (curve.G * scalar)!;
    return point.getEncoded(false);
  }

  /// Applies the [EIP-55](https://eips.ethereum.org/EIPS/eip-55) mixed-case
  /// checksum to a lowercase hex address.
  static String _toChecksumAddress(String address) {
    final String lower = address.toLowerCase();
    final String hash = hex.encode(
      Hashing.keccak256(Uint8List.fromList(utf8.encode(lower))),
    );

    final StringBuffer buffer = StringBuffer('0x');
    for (int i = 0; i < lower.length; i++) {
      final String character = lower[i];
      final bool isLetter = int.tryParse(character) == null;
      if (isLetter && int.parse(hash[i], radix: 16) >= 8) {
        buffer.write(character.toUpperCase());
      } else {
        buffer.write(character);
      }
    }
    return buffer.toString();
  }
}
