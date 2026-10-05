import 'dart:typed_data';

import 'package:crypto_wallet/data/wallet/address_deriver.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The reference phrase used by the BIP-39/BIP-84 test vectors.
  const String vectorMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';

  group('AddressDeriver — known test vectors', () {
    final Uint8List vectorSeed =
        AddressDeriver.seedFromMnemonic(vectorMnemonic);

    test('derives the BIP-84 Bitcoin address', () {
      expect(
        AddressDeriver.bitcoinAddressFromSeed(vectorSeed),
        'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu',
      );
    });

    test('derives the BIP-44 Ethereum address (EIP-55 checksummed)', () {
      expect(
        AddressDeriver.ethereumAddressFromSeed(vectorSeed),
        '0x9858EfFD232B4033E47d90003D41EC34EcaEda94',
      );
    });

    test('async seed derivation matches the sync one', () async {
      expect(
        await AddressDeriver.seedFromMnemonicAsync(vectorMnemonic),
        vectorSeed,
      );
    });

    test('different phrases produce different addresses', () {
      final Uint8List other = AddressDeriver.seedFromMnemonic(
        WalletIdentityController.generateMnemonic(),
      );

      expect(
        AddressDeriver.bitcoinAddressFromSeed(other),
        isNot(AddressDeriver.bitcoinAddressFromSeed(vectorSeed)),
      );
      expect(
        AddressDeriver.ethereumAddressFromSeed(other),
        isNot(AddressDeriver.ethereumAddressFromSeed(vectorSeed)),
      );
    });
  });

  group('WalletIdentityController mnemonic helpers', () {
    test('generates a valid 12-word phrase by default', () {
      final String mnemonic = WalletIdentityController.generateMnemonic();

      expect(mnemonic.split(' ').length, 12);
      expect(WalletIdentityController.isValidMnemonic(mnemonic), isTrue);
    });

    test('supports 24-word phrases', () {
      final String mnemonic =
          WalletIdentityController.generateMnemonic(strength: 256);

      expect(mnemonic.split(' ').length, 24);
      expect(WalletIdentityController.isValidMnemonic(mnemonic), isTrue);
    });

    test('normalises messy input before validating', () {
      const String messy =
          '  ABANDON   abandon\tabandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon about ';

      expect(WalletIdentityController.isValidMnemonic(messy), isTrue);
      expect(
        WalletIdentityController.normalize(messy).split(' ').length,
        12,
      );
    });

    test('rejects a phrase with a broken checksum', () {
      const String broken =
          'abandon abandon abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon';

      expect(WalletIdentityController.isValidMnemonic(broken), isFalse);
    });

    test('rejects unknown words', () {
      expect(
        WalletIdentityController.isValidMnemonic(
          'nova wallet abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon about',
        ),
        isFalse,
      );
    });
  });
}
