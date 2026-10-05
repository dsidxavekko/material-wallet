import 'dart:typed_data';

import 'package:crypto_wallet/core/crypto/base58.dart';
import 'package:crypto_wallet/core/crypto/bech32.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/address_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Base58', () {
    test('round-trips arbitrary bytes', () {
      final Uint8List bytes = Uint8List.fromList(<int>[0, 0, 1, 2, 3, 254, 255]);
      final String encoded = Base58.encode(bytes);
      expect(Base58.decode(encoded), bytes);
    });

    test('rejects characters outside the alphabet', () {
      expect(Base58.decode('0OIl'), isNull);
    });

    test('decodeCheck accepts a valid legacy Bitcoin address', () {
      final Uint8List? payload =
          Base58.decodeCheck('1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2');
      expect(payload, isNotNull);
      expect(payload!.length, 21);
      expect(payload[0], 0x00); // P2PKH version byte
    });

    test('decodeCheck rejects a corrupted checksum', () {
      expect(
        Base58.decodeCheck('1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN3'),
        isNull,
      );
    });
  });

  group('Bech32', () {
    test('decodes the canonical BIP-173 P2WPKH vector', () {
      final Bech32Data? decoded =
          Bech32.decode('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
      expect(decoded, isNotNull);
      expect(decoded!.hrp, 'bc');
      expect(decoded.encoding, Bech32Encoding.bech32);

      final SegwitAddress? segwit = Bech32.decodeSegwit(decoded);
      expect(segwit, isNotNull);
      expect(segwit!.version, 0);
      expect(segwit.program.length, 20);
    });

    test('encodes and decodes a bech32m Taproot address', () {
      final Uint8List program =
          Uint8List.fromList(List<int>.generate(32, (int i) => i));
      final String address = Bech32.encodeSegwit(
        hrp: 'bc',
        witnessVersion: 1,
        program: program,
      );

      final Bech32Data? decoded = Bech32.decode(address);
      expect(decoded, isNotNull);
      expect(decoded!.encoding, Bech32Encoding.bech32m);

      final SegwitAddress? segwit = Bech32.decodeSegwit(decoded);
      expect(segwit, isNotNull);
      expect(segwit!.version, 1);
      expect(segwit.program, program);
    });

    test('rejects a bad checksum and mixed case', () {
      expect(
        Bech32.decode('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5'),
        isNull,
      );
      expect(
        Bech32.decode('bc1Qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4'),
        isNull,
      );
    });
  });

  group('AddressValidator', () {
    test('Bitcoin accepts native SegWit and legacy, rejects wrong network', () {
      expect(
        AddressValidator.validate(
          NetworkCatalog.bitcoin,
          'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
        ).valid,
        isTrue,
      );
      expect(
        AddressValidator.validate(
          NetworkCatalog.bitcoin,
          '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2',
        ).valid,
        isTrue,
      );
      expect(
        AddressValidator.validate(
          NetworkCatalog.bitcoin,
          '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy',
        ).valid,
        isTrue,
      );

      // A structurally valid testnet address must be refused on mainnet.
      final String testnet = Bech32.encodeSegwit(
        hrp: 'tb',
        witnessVersion: 0,
        program: Uint8List(20),
      );
      final AddressValidation crossNetwork = AddressValidator.validate(
        NetworkCatalog.bitcoin,
        testnet,
      );
      expect(crossNetwork.valid, isFalse);
      expect(crossNetwork.reason, isNotNull);

      // And the testnet network accepts it.
      expect(
        AddressValidator.validate(NetworkCatalog.bitcoinTestnet, testnet).valid,
        isTrue,
      );
    });

    test('EVM enforces length and the EIP-55 checksum', () {
      const String checksummed = '0x52908400098527886E0F7030069857D2E4169EE7';
      expect(
        AddressValidator.validate(NetworkCatalog.ethereum, checksummed).valid,
        isTrue,
      );
      // All-lowercase is accepted without a checksum.
      expect(
        AddressValidator.validate(
          NetworkCatalog.ethereum,
          '0x52908400098527886e0f7030069857d2e4169ee7',
        ).valid,
        isTrue,
      );
      // Flipping the case of one letter breaks EIP-55.
      expect(
        AddressValidator.validate(
          NetworkCatalog.ethereum,
          '0x52908400098527886E0F7030069857D2E4169Ee7',
        ).valid,
        isFalse,
      );
      expect(
        AddressValidator.validate(
          NetworkCatalog.ethereum,
          '0x52908400098527886E0F7030069857D2E4169EE',
        ).valid,
        isFalse,
      );
      expect(
        AddressValidator.validate(NetworkCatalog.ethereum, '52908').valid,
        isFalse,
      );
    });

    test('Solana accepts 32-byte base58 and rejects the rest', () {
      expect(
        AddressValidator.validate(
          NetworkCatalog.solana,
          'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
        ).valid,
        isTrue,
      );
      expect(
        AddressValidator.validate(
          NetworkCatalog.solana,
          '11111111111111111111111111111111',
        ).valid,
        isTrue,
      );
      expect(
        AddressValidator.validate(NetworkCatalog.solana, 'abc').valid,
        isFalse,
      );
      expect(
        AddressValidator.validate(NetworkCatalog.solana, '0OIl').valid,
        isFalse,
      );
    });

    test('Aptos accepts short and full 32-byte hex', () {
      expect(
        AddressValidator.validate(NetworkCatalog.aptos, '0x1').valid,
        isTrue,
      );
      expect(
        AddressValidator.validate(
          NetworkCatalog.aptos,
          '0x1${'0' * 63}',
        ).valid,
        isTrue,
      );
      expect(
        AddressValidator.validate(
          NetworkCatalog.aptos,
          '0x1${'0' * 64}',
        ).valid,
        isFalse,
      );
      expect(
        AddressValidator.validate(NetworkCatalog.aptos, 'zz').valid,
        isFalse,
      );
    });

    test('an empty address is reported as missing', () {
      final AddressValidation result =
          AddressValidator.validate(NetworkCatalog.bitcoin, '   ');
      expect(result.valid, isFalse);
      expect(result.reason, isNotNull);
    });
  });
}
