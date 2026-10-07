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

/// Decodes the top-level fields of an RLP list that starts at [offset] in a
/// hex-encoded transaction, returning each field's encoded bytes.
List<Uint8List> _rlpFields(String raw, int offset) {
  final Uint8List b = Uint8List.fromList(hex.decode(raw));
  int i = offset;
  final int prefix = b[i];
  int listLen;
  if (prefix <= 0xf7) {
    listLen = prefix - 0xc0;
    i += 1;
  } else {
    final int n = prefix - 0xf7;
    listLen = 0;
    for (int k = 1; k <= n; k++) {
      listLen = listLen * 256 + b[i + k];
    }
    i += 1 + n;
  }

  final int end = i + listLen;
  final List<Uint8List> out = <Uint8List>[];
  while (i < end) {
    final int start = i;
    final int p = b[i];
    if (p <= 0x7f) {
      i += 1;
    } else if (p <= 0xb7) {
      i += 1 + (p - 0x80);
    } else if (p <= 0xbf) {
      final int n = p - 0xb7;
      int l = 0;
      for (int k = 1; k <= n; k++) {
        l = l * 256 + b[start + k];
      }
      i += 1 + n + l;
    } else if (p <= 0xf7) {
      i += 1 + (p - 0xc0);
    } else {
      final int n = p - 0xf7;
      int l = 0;
      for (int k = 1; k <= n; k++) {
        l = l * 256 + b[start + k];
      }
      i += 1 + n + l;
    }
    out.add(b.sublist(start, i));
  }
  return out;
}

/// Decodes one top-level field of a type-2 (EIP-1559) transaction as a BigInt.
BigInt _type2Field(String raw, int index) => _itemInt(_rlpFields(raw, 1)[index]);

/// BigInt value of one encoded RLP scalar item.
BigInt _itemInt(Uint8List item) {
  final int prefix = item[0];
  final Uint8List payload = prefix <= 0x7f ? item : item.sublist(1);
  if (payload.isEmpty) {
    return BigInt.zero;
  }
  return BigInt.parse(hex.encode(payload), radix: 16);
}

/// `true` when the encoded item is the empty RLP list (`0xc0`).
bool _isEmptyList(Uint8List item) => item.length == 1 && item[0] == 0xc0;

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

    group('signEip1559Transfer', () {
      // Field order for a signed type-2 tx: chainId, nonce, tip, cap, gasLimit,
      // to, value, data, accessList, yParity, r, s.
      String sign({int chainId = 1}) => EvmSigner.signEip1559Transfer(
            privateKey: privateKey,
            nonce: 9,
            maxPriorityFeePerGas: BigInt.from(2000000000),
            maxFeePerGas: BigInt.parse('40000000000'),
            gasLimit: BigInt.from(21000),
            to: '0x3535353535353535353535353535353535353535',
            value: BigInt.parse('1000000000000000000'),
            chainId: chainId,
          );

      test('starts with the 0x02 type byte and keeps the EIP-1559 field order',
          () {
        final String raw = sign();
        expect(raw.startsWith('02'), isTrue, reason: 'type-2 envelope');

        final List<Uint8List> fields = _rlpFields(raw, 1);
        expect(fields, hasLength(12));
        expect(_type2Field(raw, 0), BigInt.one); // chainId
        expect(_type2Field(raw, 1), BigInt.from(9)); // nonce
        expect(_type2Field(raw, 2), BigInt.from(2000000000)); // priority tip
        expect(_type2Field(raw, 3), BigInt.parse('40000000000')); // fee cap
        expect(_type2Field(raw, 4), BigInt.from(21000)); // gas limit
        expect(
          _type2Field(raw, 6),
          BigInt.parse('1000000000000000000'),
        ); // value
        expect(_isEmptyList(fields[8]), isTrue); // empty access list
      });

      test('carries the bare recovery parity, not the EIP-155 v', () {
        final BigInt parity = _type2Field(sign(), 9);
        expect(parity, anyOf(BigInt.zero, BigInt.one));
      });

      test('is deterministic (RFC 6979)', () {
        expect(sign(), sign());
      });

      test('binds the signature to one chain (chain id is signed)', () {
        expect(sign(chainId: 1), isNot(sign(chainId: 11155111)));
      });

      test('always produces a low-s signature (EIP-2)', () {
        final BigInt n = ECCurve_secp256k1().n;
        for (int k = 1; k <= 25; k++) {
          final String raw = EvmSigner.signEip1559Transfer(
            privateKey: Uint8List.fromList(
                List<int>.generate(32, (int i) => (i * 7 + k * 13) % 251)),
            nonce: k,
            maxPriorityFeePerGas: BigInt.from(1000000000 + k),
            maxFeePerGas: BigInt.from(30000000000 + k),
            gasLimit: BigInt.from(21000),
            to: '0x3535353535353535353535353535353535353535',
            value: BigInt.from(k),
            chainId: 1,
          );
          expect(_type2Field(raw, 11), lessThanOrEqualTo(n >> 1),
              reason: 'high-s at k=$k');
        }
      });

      test('rejects a malformed recipient address', () {
        expect(
          () => EvmSigner.signEip1559Transfer(
            privateKey: privateKey,
            nonce: 0,
            maxPriorityFeePerGas: BigInt.one,
            maxFeePerGas: BigInt.one,
            gasLimit: BigInt.from(21000),
            to: '0xnothex',
            value: BigInt.one,
            chainId: 1,
          ),
          throwsA(isA<EvmSigningException>()),
        );
      });

      test('calldata changes the signed payload', () {
        final Uint8List data = EvmSigner.erc20TransferData(
          to: '0x3535353535353535353535353535353535353535',
          amount: BigInt.from(1000),
        );
        final String withData = EvmSigner.signEip1559Transfer(
          privateKey: privateKey,
          nonce: 9,
          maxPriorityFeePerGas: BigInt.from(2000000000),
          maxFeePerGas: BigInt.parse('40000000000'),
          gasLimit: BigInt.from(60000),
          to: '0x1111111111111111111111111111111111111111',
          value: BigInt.zero,
          chainId: 1,
          data: data,
        );
        expect(withData, isNot(sign()));
      });
    });

    group('erc20TransferData', () {
      test('encodes the transfer selector, padded address and amount', () {
        final Uint8List data = EvmSigner.erc20TransferData(
          to: '0x3535353535353535353535353535353535353535',
          amount: BigInt.from(1000),
        );

        expect(data, hasLength(68)); // 4 selector + 32 + 32
        expect(
          hex.encode(data.sublist(0, 4)),
          'a9059cbb',
          reason: 'transfer(address,uint256) selector',
        );
        expect(hex.encode(data.sublist(4, 16)), '0' * 24); // address padding
        expect(
          hex.encode(data.sublist(16, 36)),
          '3535353535353535353535353535353535353535',
        );
        expect(
          hex.encode(data.sublist(36, 68)),
          '${'0' * 60}03e8', // 32-byte word for 1000
        );
      });
    });
  });
}