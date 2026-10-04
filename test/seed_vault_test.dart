import 'dart:convert';

import 'package:crypto_wallet/data/wallet/seed_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';
  const int fastRounds = 1000;

  group('SeedVault', () {
    test('round-trips the recovery phrase', () {
      final String payload =
          SeedVault.encrypt(mnemonic, pin, rounds: fastRounds);

      expect(SeedVault.decrypt(payload, pin), mnemonic);
    });

    test('never stores the phrase in the clear', () {
      final String payload =
          SeedVault.encrypt(mnemonic, pin, rounds: fastRounds);

      expect(payload.contains('abandon'), isFalse);
      final Map<String, Object?> json =
          jsonDecode(payload) as Map<String, Object?>;
      expect(json['salt'], isNotNull);
      expect(json['nonce'], isNotNull);
      expect(json['data'], isNotNull);
      expect(json['iterations'], fastRounds);
    });

    test('produces a different payload every time (random salt + nonce)', () {
      final String first =
          SeedVault.encrypt(mnemonic, pin, rounds: fastRounds);
      final String second =
          SeedVault.encrypt(mnemonic, pin, rounds: fastRounds);

      expect(first, isNot(second));
      expect(SeedVault.decrypt(first, pin), mnemonic);
      expect(SeedVault.decrypt(second, pin), mnemonic);
    });

    test('rejects a wrong PIN', () {
      final String payload =
          SeedVault.encrypt(mnemonic, pin, rounds: fastRounds);

      expect(
        () => SeedVault.decrypt(payload, '000000'),
        throwsA(isA<SeedVaultException>()),
      );
    });

    test('detects tampering with the ciphertext', () {
      final Map<String, Object?> json = jsonDecode(
        SeedVault.encrypt(mnemonic, pin, rounds: fastRounds),
      ) as Map<String, Object?>;

      final List<int> data = base64Decode(json['data']! as String);
      data[0] = data[0] ^ 0xFF; // flip a bit
      json['data'] = base64Encode(data);

      expect(
        () => SeedVault.decrypt(jsonEncode(json), pin),
        throwsA(isA<SeedVaultException>()),
      );
    });

    test('rejects a malformed payload', () {
      expect(
        () => SeedVault.decrypt('not-json', pin),
        throwsA(isA<SeedVaultException>()),
      );
    });
  });
}
