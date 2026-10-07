import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto_wallet/core/crypto/hashing.dart';
import 'package:crypto_wallet/core/crypto/rlp.dart';
import 'package:crypto_wallet/data/wallet/address_validator.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/evm_signer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Known-answer tests for the primitives every signature depends on.
///
/// The existing EIP-155 vector pins the *result* of the whole signing path. If
/// keccak or RLP drifted, that vector fails too — but only as one opaque hex
/// blob, which is hard to diagnose. These pin each primitive against its own
/// published test vector, so a break names itself.
///
/// Every value here comes from an external specification, never from running
/// this code and copying its output.
void main() {
  Uint8List ascii(String value) => Uint8List.fromList(utf8.encode(value));

  String hexOf(Uint8List bytes) => hex.encode(bytes);

  group('keccak-256', () {
    // Keccak-256 is the original Keccak submission, not FIPS-202 SHA3-256.
    // Ethereum uses it everywhere; confusing the two silently changes every
    // address the wallet derives.
    test('matches the published Keccak-256 vectors', () {
      expect(
        hexOf(Hashing.keccak256(ascii(''))),
        'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470',
      );
      expect(
        hexOf(Hashing.keccak256(ascii('abc'))),
        '4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45',
      );
      expect(
        hexOf(Hashing.keccak256(ascii('The quick brown fox jumps over the lazy dog'))),
        '4d741b6f1eb29cb2a9b9911c82f56fa8d73b04959d3d9d222895df6c0b28aa15',
      );
    });

    test('differs from SHA3-256 (NIST)', () {
      // FIPS-202 SHA3-256 pads with 0x06, Keccak with 0x01 — so the same input
      // must not produce the same digest.
      expect(
        hexOf(Hashing.sha3_256(ascii('abc'))),
        '3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532',
      );
      expect(
        hexOf(Hashing.sha3_256(ascii('abc'))),
        isNot(hexOf(Hashing.keccak256(ascii('abc')))),
      );
    });
  });

  group('hash160', () {
    // The Bitcoin BIP-143 / P2WPKH construction. Both halves are pinned so a
    // break names the function that broke, not just "the Bitcoin address".
    test('is RIPEMD160(SHA256(data))', () {
      expect(
        hexOf(Hashing.sha256(ascii('abc'))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        hexOf(Hashing.ripemd160(ascii('abc'))),
        '8eb208f7e05d987a9b044a8e98c6b087f15a0bfc',
      );

      final Uint8List digest = Hashing.sha256(ascii('abc'));
      expect(
        hexOf(Hashing.hash160(ascii('abc'))),
        hexOf(Hashing.ripemd160(digest)),
      );
    });
  });

  group('RLP', () {
    // The examples from the Ethereum yellow paper / wiki RLP specification.
    test('encodes the canonical examples', () {
      // A single byte below 0x80 is its own encoding.
      expect(hexOf(Rlp.encodeBytes(ascii('a'))), '61');
      // The empty string is 0x80 — never 0xc0, which would be an empty list.
      expect(hexOf(Rlp.encodeBytes(Uint8List(0))), '80');
      expect(hexOf(Rlp.encodeBytes(ascii('dog'))), '83646f67');
      // Integers drop leading zero bytes.
      expect(hexOf(Rlp.encodeInt(BigInt.zero)), '80');
      expect(hexOf(Rlp.encodeInt(BigInt.from(15))), '0f');
      expect(hexOf(Rlp.encodeInt(BigInt.from(1024))), '820400');
      // A zero byte can never be shortened: 0x80 encodes 128, not zero.
      expect(hexOf(Rlp.encodeBytes(Uint8List.fromList(<int>[0x80]))), '8180');
      expect(
        hexOf(
          Rlp.encodeBytes(
            ascii('Lorem ipsum dolor sit amet, consectetur adipisicing elit'),
          ),
        ),
        // 56 bytes, so it is the first payload that needs the long form.
        'b8384c6f72656d20697073756d20646f6c6f722073697420616d65742c20636f6e73'
        '65637465747572206164697069736963696e6720656c6974',
      );
    });

    test('switches to the long form above 55 bytes', () {
      final Uint8List fiftyFive = Uint8List(55)..fillRange(0, 55, 0x61);
      expect(Rlp.encodeBytes(fiftyFive)[0], 0x80 + 55);

      final Uint8List fiftySix = Uint8List(56)..fillRange(0, 56, 0x61);
      // 56 bytes no longer fits in the prefix byte, so 0xb7 + length-of-length.
      expect(Rlp.encodeBytes(fiftySix)[0], 0xb8);
      expect(Rlp.encodeBytes(fiftySix)[1], 56);

      // 300 needs two length bytes (0x012c), so the prefix is 0xb7 + 2.
      final Uint8List threeHundred = Uint8List(300)..fillRange(0, 300, 0x61);
      expect(Rlp.encodeBytes(threeHundred)[0], 0xb9);
      expect(Rlp.encodeBytes(threeHundred).sublist(1, 3), <int>[0x01, 0x2c]);
    });

    test('encodes lists with their own prefix', () {
      expect(hexOf(Rlp.encodeList(const <Uint8List>[])), 'c0');
      expect(
        hexOf(Rlp.encodeList(<Uint8List>[
          Rlp.encodeBytes(ascii('cat')),
          Rlp.encodeBytes(ascii('dog')),
        ])),
        'c88363617483646f67',
      );
    });
  });

  group('ERC-20 selectors', () {
    // Selectors are the first 4 bytes of the keccak hash of the signature.
    // Deriving them here means a typo can never reach a broadcast.
    test('match keccak of their canonical signatures', () {
      void expectSelector(List<int> actual, String signature) {
        expect(
          hexOf(Hashing.keccak256(ascii(signature))).substring(0, 8),
          hex.encode(actual),
          reason: '$signature selector',
        );
      }

      const String someAddress = '0x1111111111111111111111111111111111111111';

      expectSelector(
        EvmSigner.erc20TransferData(
          to: someAddress,
          amount: BigInt.one,
        ).sublist(0, 4),
        'transfer(address,uint256)',
      );
      expectSelector(
        EvmSigner.erc20ApproveData(
          spender: someAddress,
          amount: BigInt.zero,
        ).sublist(0, 4),
        'approve(address,uint256)',
      );
      expectSelector(
        EvmSigner.erc20BalanceOfData(someAddress).sublist(0, 4),
        'balanceOf(address)',
      );
    });

    test('approve encodes the spender and a zero amount for a revoke', () {
      final Uint8List data = EvmSigner.erc20ApproveData(
        spender: '0x3535353535353535353535353535353535353535',
        amount: BigInt.zero,
      );

      expect(data, hasLength(68));
      expect(hexOf(data.sublist(0, 4)), '095ea7b3');
      expect(hexOf(data.sublist(4, 16)), '0' * 24);
      expect(
        hexOf(data.sublist(16, 36)),
        '3535353535353535353535353535353535353535',
      );
      expect(hexOf(data.sublist(36, 68)), '0' * 64, reason: 'revoke to zero');
    });

    test('balanceOf encodes only the owner address', () {
      final Uint8List data = EvmSigner.erc20BalanceOfData(
        '0x3535353535353535353535353535353535353535',
      );

      expect(data, hasLength(36));
      expect(hexOf(data.sublist(0, 4)), '70a08231');
      expect(
        hexOf(data.sublist(16, 36)),
        '3535353535353535353535353535353535353535',
      );
    });
  });

  group('EIP-55 checksum', () {
    // The eight canonical addresses from the EIP-55 reference test set, in
    // their checksummed form.
    const List<String> vectors = <String>[
      '0x52908400098527886E0F7030069857D2E4169EE7',
      '0x8617E340B3D01FA5F11F306F4090FD50E238070D',
      '0xde709f2102306220921060314715629080e2fb77',
      '0x27b1fdb04752bbc536007a920d24acb045561c26',
      '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
      '0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB',
      '0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb',
    ];

    test('accepts every canonical EIP-55 address', () {
      for (final String address in vectors) {
        expect(
          AddressValidator.validate(NetworkCatalog.ethereum, address).valid,
          isTrue,
          reason: address,
        );
      }
    });

    test('rejects an address whose case was flipped', () {
      // The checksum exists so a mistyped address is caught by the wallet
      // rather than by a node that silently burns the funds. Flipping case in
      // an all-lowercase address produces a different all-lowercase one, which
      // is legitimately valid — so only the mixed-case vectors are corrupted.
      for (final String address in vectors.where((String a) => _isMixedCase(a))) {
        final String flipped = _flipLastLetter(address);
        expect(
          AddressValidator.validate(NetworkCatalog.ethereum, flipped).valid,
          isFalse,
          reason: flipped,
        );
      }
    });

    test('accepts the all-lowercase and all-uppercase forms', () {
      // Both are valid EVM addresses; the checksum only has meaning in mixed
      // case, so rejecting them would lock out real users.
      const String lower = '0xde709f2102306220921060314715629080e2fb77';
      const String upper = '0xDE709F2102306220921060314715629080E2FB77';
      expect(
        AddressValidator.validate(NetworkCatalog.ethereum, lower).valid,
        isTrue,
      );
      expect(
        AddressValidator.validate(NetworkCatalog.ethereum, upper).valid,
        isTrue,
      );
    });
  });
}

/// `true` when an address has both cases, so EIP-55 gives it a meaning.
bool _isMixedCase(String address) =>
    address != address.toLowerCase() && address != address.toUpperCase();

/// Swaps the case of the final character, leaving a valid 40-char hex address.
String _flipLastLetter(String address) {
  final String last = address[address.length - 1];
  if (RegExp(r'[0-9]').hasMatch(last)) {
    // Digits have no case, so fall back to the character before it. Any
    // position breaks the checksum equally.
    return address.replaceRange(address.length - 2, address.length - 1, 'f');
  }
  final String flipped =
      last == last.toUpperCase() ? last.toLowerCase() : last.toUpperCase();
  return address.replaceRange(address.length - 1, address.length, flipped);
}
