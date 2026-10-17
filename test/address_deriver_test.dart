import 'dart:typed_data';

import 'package:convert/convert.dart';
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

  group('AddressDeriver — BIP-39 passphrase', () {
    test('matches the reference vector (passphrase "TREZOR")', () {
      // The first vector of the BIP-39 reference test set: the passphrase is
      // appended to the salt, and this exact seed is what the spec expects.
      expect(
        hex.encode(
          AddressDeriver.seedFromMnemonic(vectorMnemonic, passphrase: 'TREZOR'),
        ),
        'c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e5349553'
        '1f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04',
      );
    });

    test('async derivation matches the sync one', () async {
      expect(
        await AddressDeriver.seedFromMnemonicAsync(
          vectorMnemonic,
          passphrase: 'TREZOR',
        ),
        AddressDeriver.seedFromMnemonic(vectorMnemonic, passphrase: 'TREZOR'),
      );
    });

    test('a passphrase changes every derived address', () {
      final Uint8List plain = AddressDeriver.seedFromMnemonic(vectorMnemonic);
      final Uint8List protected =
          AddressDeriver.seedFromMnemonic(vectorMnemonic, passphrase: 'TREZOR');

      expect(
        AddressDeriver.ethereumAddressFromSeed(protected),
        isNot(AddressDeriver.ethereumAddressFromSeed(plain)),
      );
      expect(
        AddressDeriver.bitcoinAddressFromSeed(protected),
        isNot(AddressDeriver.bitcoinAddressFromSeed(plain)),
      );
      expect(
        AddressDeriver.solanaAddressFromSeed(protected),
        isNot(AddressDeriver.solanaAddressFromSeed(plain)),
      );
      expect(
        AddressDeriver.aptosAddressFromSeed(protected),
        isNot(AddressDeriver.aptosAddressFromSeed(plain)),
      );
    });

    test('an empty passphrase is the default derivation', () {
      final Uint8List plain = AddressDeriver.seedFromMnemonic(vectorMnemonic);
      final Uint8List empty =
          AddressDeriver.seedFromMnemonic(vectorMnemonic, passphrase: '');

      expect(plain, empty);
    });
  });

  group('AddressDeriver — account index', () {
    final Uint8List seed = AddressDeriver.seedFromMnemonic(vectorMnemonic);

    test('index 0 is the default account', () {
      expect(
        AddressDeriver.ethereumAddressFromSeed(seed, account: 0),
        AddressDeriver.ethereumAddressFromSeed(seed),
      );
      expect(
        AddressDeriver.bitcoinAddressFromSeed(seed, account: 0),
        AddressDeriver.bitcoinAddressFromSeed(seed),
      );
    });

    test('every chain gives a fresh address per index', () {
      for (final int account in <int>[1, 2]) {
        expect(
          AddressDeriver.ethereumAddressFromSeed(seed, account: account),
          isNot(AddressDeriver.ethereumAddressFromSeed(seed, account: 0)),
        );
        expect(
          AddressDeriver.bitcoinAddressFromSeed(seed, account: account),
          isNot(AddressDeriver.bitcoinAddressFromSeed(seed, account: 0)),
        );
        expect(
          AddressDeriver.solanaAddressFromSeed(seed, account: account),
          isNot(AddressDeriver.solanaAddressFromSeed(seed, account: 0)),
        );
        expect(
          AddressDeriver.aptosAddressFromSeed(seed, account: account),
          isNot(AddressDeriver.aptosAddressFromSeed(seed, account: 0)),
        );
      }
    });

    test('the signing key pair follows the account index', () {
      final ({Uint8List privateKey, Uint8List publicKey}) first =
          AddressDeriver.bitcoinKeyPairFromSeed(seed);
      final ({Uint8List privateKey, Uint8List publicKey}) second =
          AddressDeriver.bitcoinKeyPairFromSeed(seed, account: 1);

      expect(first.privateKey, isNot(second.privateKey));
      expect(first.publicKey, isNot(second.publicKey));
      // Account 0 must stay exactly what the pinned vectors cover.
      expect(first.publicKey.length, 33);
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
