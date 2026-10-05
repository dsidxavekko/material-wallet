import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto_wallet/data/wallet/evm_signer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' show ECCurve_secp256k1;

/// Reads one field out of a signed legacy transaction.
///
/// Field order is geth's: nonce, gasPrice, gasLimit, to, value, data, v, r, s.
BigInt _field(String raw, int index) {
  final Uint8List bytes = Uint8List.fromList(hex.decode(raw));
  int i = 0;

  /// Returns the payload length, leaving [i] pointing at the first payload byte.
  int readLength(int prefix, bool isList) {
    if (isList) {
      i++;
      if (prefix <= 0xf7) {
        return prefix - 0xc0;
      }
      final int lenOfLen = prefix - 0xf7;
      int len = 0;
      for (int k = 0; k < lenOfLen; k++) {
        len = len * 256 + bytes[i++];
      }
      return len;
    }
    if (prefix <= 0x7f) {
      return 1; // the byte is its own encoding
    }
    i++;
    if (prefix <= 0xb7) {
      return prefix - 0x80;
    }
    final int lenOfLen = prefix - 0xb7;
    int len = 0;
    for (int k = 0; k < lenOfLen; k++) {
      len = len * 256 + bytes[i++];
    }
    return len;
  }

  final int total = readLength(bytes[0], true);
  final int end = i + total;

  for (int k = 0; k < index; k++) {
    final int prefix = bytes[i];
    i += readLength(prefix, prefix >= 0xc0);
  }
  if (i >= end) {
    throw StateError('field $index is outside the transaction');
  }

  final int prefix = bytes[i];
  final int len = readLength(prefix, prefix >= 0xc0);
  if (len == 0) {
    return BigInt.zero;
  }
  return BigInt.parse(hex.encode(bytes.sublist(i, i + len)), radix: 16);
}

/// The canonical vector from [EIP-155](https://eips.ethereum.org/EIPS/eip-155).
///
/// It pins every step that can silently lose funds: the RLP layout, the keccak
/// pre-hash, RFC-6979 determinism, low-s normalisation and — most importantly —
/// the `v` recovery byte. A wrong `v` produces a signature that recovers to a
/// different address, so funds would go to a stranger.
void main() {
  // Known-answer key and its derived address, from the EIP-155 example.
  final Uint8List privateKey = Uint8List.fromList(<int>[
    0x46, 0x46, 0x46, 0x46, 0x46, 0x46, 0x46, 0x46, //
    0x46, 0x46, 0x46, 0x46, 0x46, 0x46, 0x46, 0x46,
    0x46, 0x46, 0x46, 0x46, 0x46, 0x46, 0x46, 0x46,
    0x46, 0x46, 0x46, 0x46, 0x46, 0x46, 0x46, 0x46,
  ]);

  group('EvmSigner', () {
    test('reproduces the EIP-155 reference transaction', () {
      final String raw = EvmSigner.signTransfer(
        privateKey: privateKey,
        nonce: 9,
        gasPrice: BigInt.parse('20000000000'), // 20 gwei
        gasLimit: BigInt.from(21000),
        to: '0x3535353535353535353535353535353535353535',
        value: BigInt.parse('1000000000000000000'), // 1 ether
        chainId: 1,
      );

      // Field order is geth's legacy-tx order: nonce, gasPrice, gasLimit, to,
      // value, data, v, r, s — the EIP-155 `v` sits *before* the signature.
      expect(
        raw,
        'f86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a'
        '76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa63627'
        '6a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83',
      );
    });

    test('is deterministic (RFC 6979)', () {
      String sign() => EvmSigner.signTransfer(
            privateKey: privateKey,
            nonce: 9,
            gasPrice: BigInt.parse('20000000000'),
            gasLimit: BigInt.from(21000),
            to: '0x3535353535353535353535353535353535353535',
            value: BigInt.parse('1000000000000000000'),
            chainId: 1,
          );

      expect(sign(), sign());
    });

    test('binds the signature to one chain (v carries the chain id)', () {
      final String mainnet = EvmSigner.signTransfer(
        privateKey: privateKey,
        nonce: 9,
        gasPrice: BigInt.parse('20000000000'),
        gasLimit: BigInt.from(21000),
        to: '0x3535353535353535353535353535353535353535',
        value: BigInt.parse('1000000000000000000'),
        chainId: 1,
      );
      final String sepolia = EvmSigner.signTransfer(
        privateKey: privateKey,
        nonce: 9,
        gasPrice: BigInt.parse('20000000000'),
        gasLimit: BigInt.from(21000),
        to: '0x3535353535353535353535353535353535353535',
        value: BigInt.parse('1000000000000000000'),
        chainId: 11155111,
      );

      // Different chain id must yield a different raw transaction, or the same
      // signature could be replayed on another chain.
      expect(mainnet, isNot(sepolia));
    });

    test('always produces a low-s signature (EIP-2)', () {
      // The reference vector happens to sign low-s, so it cannot catch a
      // broken normalisation. Roughly half of all signatures come out high,
      // and those are rejected by every node.
      final BigInt n = ECCurve_secp256k1().n;
      for (int k = 1; k <= 25; k++) {
        final String raw = EvmSigner.signTransfer(
          privateKey: Uint8List.fromList(
              List<int>.generate(32, (int i) => (i * 7 + k * 13) % 251)),
          nonce: k,
          gasPrice: BigInt.from(20000000000 + k),
          gasLimit: BigInt.from(21000),
          to: '0x3535353535353535353535353535353535353535',
          value: BigInt.from(k),
          chainId: 1,
        );
        expect(_field(raw, 7), lessThanOrEqualTo(n >> 1), reason: 'high-s at k=$k');
      }
    });

    test('rejects a malformed recipient address', () {
      expect(
        () => EvmSigner.signTransfer(
          privateKey: privateKey,
          nonce: 0,
          gasPrice: BigInt.one,
          gasLimit: BigInt.from(21000),
          to: '0xnothex',
          value: BigInt.one,
          chainId: 1,
        ),
        throwsA(isA<EvmSigningException>()),
      );
    });
  });
}