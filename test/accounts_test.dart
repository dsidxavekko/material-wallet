import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/seed_vault.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the platform keystore that holds the vault.
class _FakeWalletStorage extends WalletStorage {
  String? vault;

  @override
  Future<String?> readVault() async => vault;

  @override
  Future<void> writeVault(String payload, DateTime createdAt) async {
    vault = payload;
  }

  @override
  Future<void> clear() async {
    vault = null;
  }
}

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';

  Future<WalletIdentityController> unlockedWallet(
    _FakeWalletStorage storage, {
    String passphrase = '',
  }) async {
    final WalletIdentityController identity = WalletIdentityController(
      storage: storage,
      kdfRounds: 1000,
    );
    await identity.load();
    await identity.createWallet(
      mnemonic: mnemonic,
      pin: pin,
      passphrase: passphrase,
    );
    return identity;
  }

  group('BIP-39 passphrase', () {
    test('changes the derived addresses of the same phrase', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final WalletIdentityController plain =
          await unlockedWallet(_FakeWalletStorage());
      final String plainAddress =
          plain.addressFor(NetworkCatalog.ethereum)!;

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final WalletIdentityController protected =
          await unlockedWallet(_FakeWalletStorage(), passphrase: 'TREZOR');
      final String protectedAddress =
          protected.addressFor(NetworkCatalog.ethereum)!;

      expect(protectedAddress, isNot(plainAddress));
      expect(protected.account!.hasPassphrase, isTrue);
    });

    test('survives a lock and unlock', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity =
          await unlockedWallet(storage, passphrase: 'TREZOR');
      final String address = identity.addressFor(NetworkCatalog.ethereum)!;

      identity.lock();
      await identity.unlock(pin);

      expect(identity.account!.hasPassphrase, isTrue);
      expect(identity.addressFor(NetworkCatalog.ethereum), address);
    });

    test('survives a PIN change', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity =
          await unlockedWallet(storage, passphrase: 'TREZOR');
      final String address = identity.addressFor(NetworkCatalog.ethereum)!;

      await identity.changePin(currentPin: pin, newPin: '135790');
      identity.lock();
      await identity.unlock('135790');

      expect(identity.account!.hasPassphrase, isTrue);
      expect(identity.addressFor(NetworkCatalog.ethereum), address);
    });

    test('an old (v1) vault restores without a passphrase', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final _FakeWalletStorage storage = _FakeWalletStorage()
        ..vault = SeedVault.encrypt(mnemonic, pin, rounds: 1000);

      final WalletIdentityController identity = WalletIdentityController(
        storage: storage,
        kdfRounds: 1000,
      );
      await identity.load();
      await identity.unlock(pin);

      expect(identity.account!.mnemonic, mnemonic);
      expect(identity.account!.hasPassphrase, isFalse);
    });
  });

  group('derived accounts', () {
    test('a fresh wallet starts on account 0', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final WalletIdentityController identity =
          await unlockedWallet(_FakeWalletStorage());

      expect(identity.accountIndex, 0);
      expect(identity.accountCount, 1);
    });

    test('addAccount switches to a brand-new address set', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final WalletIdentityController identity =
          await unlockedWallet(_FakeWalletStorage());
      final String account0 = identity.addressFor(NetworkCatalog.ethereum)!;

      await identity.addAccount();

      expect(identity.accountIndex, 1);
      expect(identity.accountCount, 2);
      expect(identity.addressFor(NetworkCatalog.ethereum), isNot(account0));
      // Switching back re-derives the original address, not a new one.
      await identity.selectAccount(0);
      expect(identity.addressFor(NetworkCatalog.ethereum), account0);
    });

    test('an out-of-range account is ignored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final WalletIdentityController identity =
          await unlockedWallet(_FakeWalletStorage());

      await identity.selectAccount(1);

      expect(identity.accountIndex, 0);
    });

    test('the selected account is remembered across a restart', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = await unlockedWallet(storage);
      await identity.addAccount();

      final WalletIdentityController restarted = WalletIdentityController(
        storage: storage,
        kdfRounds: 1000,
      );
      await restarted.load();

      expect(restarted.accountIndex, 1);
      expect(restarted.accountCount, 2);
      await restarted.unlock(pin);
      expect(restarted.addressFor(NetworkCatalog.ethereum), isNotNull);
    });

    test('a stale stored index falls back to account 0', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'nova.wallet.accountIndex': 7,
        'nova.wallet.accountCount': 2,
      });
      final _FakeWalletStorage storage = _FakeWalletStorage()
        ..vault = SeedVault.encrypt(mnemonic, pin, rounds: 1000);
      final WalletIdentityController identity = WalletIdentityController(
        storage: storage,
        kdfRounds: 1000,
      );

      await identity.load();

      expect(identity.accountIndex, 0);
    });
  });
}
