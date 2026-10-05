import 'dart:typed_data';

import 'package:bip32/bip32.dart';
import 'package:convert/convert.dart';
import 'package:pointycastle/export.dart';

import '../../core/crypto/hashing.dart';
import '../../core/crypto/rlp.dart';

/// Thrown when a transfer cannot be signed.
class EvmSigningException implements Exception {
  const EvmSigningException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Signs legacy (type-0) EVM transactions on-device and returns the raw bytes
/// that `eth_sendRawTransaction` expects.
///
/// Everything runs in pure Dart with the seed the wallet already holds — no
/// third-party signer, no network. The payload follows EIP-155, so a signed
/// transaction is bound to one [chainId] and can never be replayed on another
/// chain.
///
/// Signing is deterministic (RFC 6979): the same key, chain and parameters
/// always produce the same signature, which makes the result reproducible in
/// tests and safe to retry.
class EvmSigner {
  const EvmSigner._();

  static const String evmPath = "m/44'/60'/0'/0/0";

  /// secp256k1 group order. Signatures must be normalised to the lower half
  /// (EIP-2) or every node rejects them.
  ///
  /// `ECCurve_secp256k1` already exposes the curve *as* domain parameters, so
  /// its own `n` is used rather than re-declaring the order here.
  static final BigInt _n = ECCurve_secp256k1().n;

  /// 32-byte signing key for [seed], taken from the standard EVM derivation
  /// path. Zeroed by the caller when the transfer finishes.
  static Uint8List privateKeyFromSeed(Uint8List seed) =>
      BIP32.fromSeed(seed).derivePath(evmPath).privateKey!;

  /// Builds, signs and serialises a native-currency transfer.
  ///
  /// * [nonce] — the sender's transaction count, from `eth_getTransactionCount`
  /// * [chainId] — protects against cross-chain replay (EIP-155)
  /// * [to] — recipient, `0x` + 40 hex characters
  ///
  /// Returns the RLP-encoded, signed transaction as hex, ready to broadcast.
  static String signTransfer({
    required Uint8List privateKey,
    required int nonce,
    required BigInt gasPrice,
    required BigInt gasLimit,
    required String to,
    required BigInt value,
    required int chainId,
  }) {
    final Uint8List toBytes = _addressToBytes(to);

    // The fields the sender commits to, replay-protected.
    final Uint8List fields = Rlp.encodeList(<Uint8List>[
      Rlp.encodeInt(BigInt.from(nonce)),
      Rlp.encodeInt(gasPrice),
      Rlp.encodeInt(gasLimit),
      Rlp.encodeBytes(toBytes),
      Rlp.encodeInt(value),
      Rlp.encodeBytes(Uint8List(0)), // no calldata on a plain transfer
      Rlp.encodeInt(BigInt.from(chainId)),
      Rlp.encodeBytes(Uint8List(0)), // empty r
      Rlp.encodeBytes(Uint8List(0)), // empty s
    ]);

    final Uint8List hash = Hashing.keccak256(fields);

    final ECDomainParameters params = ECCurve_secp256k1();

    // No digest: [hash] is already the keccak-256 of the payload and Ethereum
    // signs that digest directly. Passing one would hash it a second time.
    final ECDSASigner signer = ECDSASigner(null, HMac(SHA256Digest(), 64));
    signer.init(
      true,
      PrivateKeyParameter(
        ECPrivateKey(BigInt.parse(hex.encode(privateKey), radix: 16), params),
      ),
    );

    // EIP-2: nodes only accept the lower of the two equivalent signatures.
    final ECSignature raw = signer.generateSignature(hash) as ECSignature;
    final ECSignature signature = raw.isNormalized(params)
        ? raw
        : raw.normalize(params);

    final BigInt e = BigInt.parse(hex.encode(hash), radix: 16);
    final BigInt expected =
        BigInt.parse(hex.encode(_uncompressedPublicKey(privateKey)), radix: 16);

    // The recovery id's low bit is the parity of the signing point R. Only one
    // of the two parities recovers our own key, so try both and keep the match.
    final BigInt? yBit = _recoverParity(signature.r, signature.s, e, expected);
    if (yBit == null) {
      throw const EvmSigningException(
        'Signing failed: the recovered key does not match this wallet.',
      );
    }

    // EIP-155: v = recoveryId + chainId * 2 + 35.
    final BigInt v = BigInt.from(chainId) * BigInt.two + BigInt.from(35) + yBit;

    final Uint8List signed = Rlp.encodeList(<Uint8List>[
      Rlp.encodeInt(BigInt.from(nonce)),
      Rlp.encodeInt(gasPrice),
      Rlp.encodeInt(gasLimit),
      Rlp.encodeBytes(toBytes),
      Rlp.encodeInt(value),
      Rlp.encodeBytes(Uint8List(0)),
      // geth decodes legacy transactions as …, data, v, r, s — `v` comes
      // *before* the signature. Putting it last yields a transaction every
      // node rejects with "failed to decode signed transaction".
      Rlp.encodeInt(v),
      Rlp.encodeInt(signature.r),
      Rlp.encodeInt(signature.s),
    ]);

    return hex.encode(signed);
  }

  /// Returns the y-parity (`0` or `1`) whose recovered public key matches
  /// [expected], or `null` when neither does.
  ///
  /// Recovery uses `Q = r⁻¹ · (s·R − e·G)`, where `R` is the signing point and
  /// `e` the message hash. Two candidate `R` points exist — `r` has a second
  /// root on the curve — and only one of them is the real signing point, which
  /// is exactly what the low bit of the recovery id encodes.
  static BigInt? _recoverParity(
    BigInt r,
    BigInt s,
    BigInt e,
    BigInt expected,
  ) {
    final ECDomainParameters params = ECCurve_secp256k1();
    final ECCurve curve = params.curve;
    final ECPoint generator = params.G;
    final BigInt rInverse = r.modInverse(_n);

    for (final int yBit in <int>[0, 1]) {
      try {
        final ECPoint pointR = curve.decompressPoint(yBit, r);
        final ECPoint? sum =
            (pointR * s)! + (generator * ((_n - e % _n) % _n));
        final ECPoint? q = sum! * rInverse;
        if (q == null || q.isInfinity) {
          continue;
        }
        final BigInt candidate =
            BigInt.parse(hex.encode(q.getEncoded(false)), radix: 16);
        if (candidate == expected) {
          return BigInt.from(yBit);
        }
      } catch (_) {
        // A parity with no point on the curve cannot be the signing point.
        continue;
      }
    }
    return null;
  }

  /// 20 raw address bytes from a `0x…` hex address.
  static Uint8List _addressToBytes(String address) {
    final String clean = address.startsWith('0x') ? address.substring(2) : address;
    if (clean.length != 40) {
      throw const EvmSigningException('The recipient address is not a valid '
          'EVM address.');
    }
    return Uint8List.fromList(hex.decode(clean));
  }

  /// 65-byte uncompressed public key (`0x04 ‖ X ‖ Y`) for [privateKey].
  static Uint8List _uncompressedPublicKey(Uint8List privateKey) {
    final ECPoint point = (ECCurve_secp256k1().G *
            BigInt.parse(hex.encode(privateKey), radix: 16))!;
    return point.getEncoded(false);
  }
}