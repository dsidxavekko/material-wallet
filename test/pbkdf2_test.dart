import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto_wallet/data/wallet/address_deriver.dart';
import 'package:crypto_wallet/data/wallet/pbkdf2_fallback.dart';
import 'package:crypto_wallet/data/wallet/seed_vault.dart';
import 'package:flutter_test/flutter_test.dart';

String hexOf(Uint8List bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';

  final Uint8List password = Uint8List.fromList(utf8.encode('password'));
  final Uint8List salt = Uint8List.fromList(utf8.encode('salt'));

  group('PBKDF2', () {
    test('matches the RFC test vectors', () {
      expect(
        hexOf(pbkdf2Sync(Pbkdf2Hash.sha256, password, salt, 4096, 32)),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
      expect(
        hexOf(pbkdf2Sync(Pbkdf2Hash.sha512, password, salt, 4096, 64)),
        'd197b1b33db0143e018b12f3d1d1479e6cdebdcc97c5c0f87f6902e072f457b5'
        '143f30602641b3d55cd335988cb36b84376060ecd532e039b742a239434af2d5',
      );
    });

    test('chunked derivation matches the synchronous implementation', () async {
      for (final Pbkdf2Hash hash in Pbkdf2Hash.values) {
        final Uint8List sync = pbkdf2Sync(hash, password, salt, 1000, 64);
        final Uint8List chunked = await pbkdf2Chunked(
          hash,
          password,
          salt,
          1000,
          64,
          yieldEvery: 100,
        );
        expect(chunked, sync);
      }
    });
  });

  group('SeedVault async API', () {
    test('round-trips and stays compatible with the sync format', () async {
      final String payload =
          await SeedVault.encryptAsync(mnemonic, pin, rounds: 1000);

      expect(await SeedVault.decryptAsync(payload, pin), mnemonic);
      // A payload created asynchronously is readable synchronously.
      expect(SeedVault.decrypt(payload, pin), mnemonic);
    });

    test('rejects a wrong PIN', () async {
      final String payload =
          await SeedVault.encryptAsync(mnemonic, pin, rounds: 1000);

      expect(
        () => SeedVault.decryptAsync(payload, '000000'),
        throwsA(isA<SeedVaultException>()),
      );
    });
  });

  group('BIP-39 seed', () {
    test('matches an independent reference vector', () {
      expect(
        hexOf(AddressDeriver.seedFromMnemonic(mnemonic)),
        '5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1'
        '9a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4',
      );
    });

    test('async derivation equals the synchronous one', () async {
      expect(
        await AddressDeriver.seedFromMnemonicAsync(mnemonic),
        AddressDeriver.seedFromMnemonic(mnemonic),
      );
    });
  });
}
