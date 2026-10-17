import 'package:crypto_wallet/data/wallet/wallet_account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';

  group('WalletAccount vault payload', () {
    test('round-trips the mnemonic and the passphrase', () {
      final WalletAccount account = WalletAccount(
        mnemonic: mnemonic,
        passphrase: 'TREZOR',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final WalletAccount restored = WalletAccount.fromVaultPayload(
        account.toVaultPayload(),
        DateTime.utc(2026, 1, 2),
      );

      expect(restored.mnemonic, mnemonic);
      expect(restored.passphrase, 'TREZOR');
      expect(restored.hasPassphrase, isTrue);
    });

    test('a wallet without a passphrase round-trips as such', () {
      final WalletAccount account = WalletAccount(
        mnemonic: mnemonic,
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final WalletAccount restored = WalletAccount.fromVaultPayload(
        account.toVaultPayload(),
        DateTime.utc(2026, 1, 1),
      );

      expect(restored.mnemonic, mnemonic);
      expect(restored.passphrase, isEmpty);
      expect(restored.hasPassphrase, isFalse);
    });

    test('a v1 payload (bare mnemonic) still restores', () {
      // Vaults written before passphrase support stored the phrase itself as
      // the whole decrypted payload — not a JSON envelope.
      final WalletAccount restored = WalletAccount.fromVaultPayload(
        mnemonic,
        DateTime.utc(2026, 1, 1),
      );

      expect(restored.mnemonic, mnemonic);
      expect(restored.passphrase, isEmpty);
    });

    test('a JSON-looking envelope without "m" degrades to a bare phrase', () {
      // The decoder must not invent a mnemonic out of foreign JSON.
      final WalletAccount restored = WalletAccount.fromVaultPayload(
        '{"unrelated": true}',
        DateTime.utc(2026, 1, 1),
      );

      expect(restored.mnemonic, '{"unrelated": true}');
      expect(restored.hasPassphrase, isFalse);
    });
  });
}
