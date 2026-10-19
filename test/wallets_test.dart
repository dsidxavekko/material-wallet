import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/seed_vault.dart';
import 'package:crypto_wallet/data/wallet/wallet_account.dart';
import 'package:crypto_wallet/data/wallet/wallet_book.dart';
import 'package:crypto_wallet/data/wallet/wallet_entry.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/data/wallet/watch_address.dart';
import 'package:crypto_wallet/state/settings_controller.dart';
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
  const String mnemonicA =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String mnemonicB =
      'legal winner thank year wave sausage worth useful legal winner thank '
      'yellow';
  const String pin = '482139';
  const String evmWatch = '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045';
  const String btcWatch = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  WalletIdentityController build(_FakeWalletStorage storage) =>
      WalletIdentityController(storage: storage, kdfRounds: 1000);

  Future<WalletIdentityController> unlockedWallet(
    _FakeWalletStorage storage,
  ) async {
    final WalletIdentityController identity = build(storage);
    await identity.load();
    await identity.createWallet(mnemonic: mnemonicA, pin: pin);
    return identity;
  }

  group('several recovery phrases', () {
    test('a second phrase gets its own addresses and becomes active', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = await unlockedWallet(storage);
      final String first = identity.addressFor(NetworkCatalog.ethereum)!;

      await identity.addSeedWallet(
        mnemonic: mnemonicB,
        password: pin,
        name: 'Savings',
      );

      expect(identity.wallets.map((WalletEntry w) => w.name),
          <String>['Wallet 1', 'Savings']);
      expect(identity.activeWallet!.name, 'Savings');
      expect(identity.addressFor(NetworkCatalog.ethereum), isNot(first));
      expect(identity.canSign, isTrue);

      await identity.selectWallet(primaryWalletId);
      expect(identity.addressFor(NetworkCatalog.ethereum), first);
    });

    test('one password opens every phrase after a lock', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = await unlockedWallet(storage);
      await identity.addSeedWallet(mnemonic: mnemonicB, password: pin);
      final String second = identity.addressFor(NetworkCatalog.ethereum)!;

      identity.lock();
      expect(identity.addressFor(NetworkCatalog.ethereum), isNull);

      final WalletIdentityController reopened = build(storage);
      await reopened.load();
      await reopened.unlock(pin);
      expect(reopened.wallets, hasLength(2));
      // The wallet that was open when the app closed is the one that reopens.
      expect(reopened.addressFor(NetworkCatalog.ethereum), second);
    });

    test('a wrong password adds nothing and leaves the vault alone', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = await unlockedWallet(storage);
      final String? before = storage.vault;

      await expectLater(
        identity.addSeedWallet(mnemonic: mnemonicB, password: 'not-the-password'),
        throwsA(isA<SeedVaultException>()),
      );
      expect(storage.vault, before);
      expect(identity.wallets, hasLength(1));
    });

    test('the same phrase and passphrase is refused as a duplicate', () async {
      final WalletIdentityController identity =
          await unlockedWallet(_FakeWalletStorage());
      await expectLater(
        identity.addSeedWallet(mnemonic: mnemonicA, password: pin),
        throwsA(isA<SeedVaultException>()),
      );
      // …but the same phrase with a passphrase is a different wallet.
      await identity.addSeedWallet(
        mnemonic: mnemonicA,
        password: pin,
        passphrase: 'TREZOR',
      );
      expect(identity.wallets, hasLength(2));
    });

    test('accounts are counted per wallet', () async {
      final WalletIdentityController identity =
          await unlockedWallet(_FakeWalletStorage());
      await identity.addAccount();
      await identity.addAccount();
      expect(identity.accountCount, 3);

      await identity.addSeedWallet(mnemonic: mnemonicB, password: pin);
      expect(identity.accountCount, 1);
      expect(identity.accountIndex, 0);

      await identity.selectWallet(primaryWalletId);
      expect(identity.accountCount, 3);
      expect(identity.accountIndex, 2);
    });

    test('changing the password re-encrypts every phrase', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = await unlockedWallet(storage);
      await identity.addSeedWallet(mnemonic: mnemonicB, password: pin);

      await identity.changePin(currentPin: pin, newPin: 'a brand new password');
      identity.lock();

      final WalletIdentityController reopened = build(storage);
      await reopened.load();
      await reopened.unlock('a brand new password');
      expect(reopened.wallets, hasLength(2));
    });

    test('a phrase can be removed, the last one cannot', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = await unlockedWallet(storage);
      await identity.addSeedWallet(mnemonic: mnemonicB, password: pin);
      final String secondId = identity.activeWalletId;

      await expectLater(
        identity.removeSeedWallet(secondId, 'wrong password'),
        throwsA(isA<SeedVaultException>()),
      );
      expect(identity.wallets, hasLength(2));

      await identity.removeSeedWallet(secondId, pin);
      expect(identity.wallets.single.id, primaryWalletId);
      expect(identity.activeWalletId, primaryWalletId);
      expect(identity.canSign, isTrue);

      await expectLater(
        identity.removeSeedWallet(primaryWalletId, pin),
        throwsA(isA<SeedVaultException>()),
      );
    });

    test('removing the first phrase promotes the next one', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = await unlockedWallet(storage);
      await identity.addSeedWallet(mnemonic: mnemonicB, password: pin);
      final String secondAddress = identity.addressFor(NetworkCatalog.ethereum)!;

      await identity.removeSeedWallet(primaryWalletId, pin);
      identity.lock();

      final WalletIdentityController reopened = build(storage);
      await reopened.load();
      await reopened.unlock(pin);
      expect(reopened.wallets, hasLength(1));
      expect(reopened.addressFor(NetworkCatalog.ethereum), secondAddress);
    });

    test('a vault written before multiple wallets still opens', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage()
        ..vault = SeedVault.encrypt(mnemonicA, pin, rounds: 1000);
      final WalletIdentityController identity = build(storage);
      await identity.load();
      await identity.unlock(pin);

      expect(identity.wallets.single.id, primaryWalletId);
      expect(identity.canSign, isTrue);
    });

    test('a vault of one wallet serialises as it always did', () {
      final WalletAccount account = WalletAccount(
        mnemonic: mnemonicA,
        passphrase: 'x',
        createdAt: DateTime(2026),
      );
      expect(account.toVaultPayload(), '{"m":"$mnemonicA","p":"x"}');
    });

    test('the vault payload round-trips several wallets', () {
      final WalletAccount vault = WalletAccount.fromSeeds(<WalletAccount>[
        WalletAccount(mnemonic: mnemonicA, createdAt: DateTime(2026)),
        WalletAccount(
          mnemonic: mnemonicB,
          passphrase: 'pw',
          createdAt: DateTime(2026),
          id: 'w2',
        ),
      ]);
      final WalletAccount back =
          WalletAccount.fromVaultPayload(vault.toVaultPayload(), DateTime(2026));
      expect(back.seeds.map((WalletAccount s) => s.id), <String>['main', 'w2']);
      expect(back.seedWithId('w2')!.passphrase, 'pw');
      expect(back.seedWithId('main')!.mnemonic, mnemonicA);
    });
  });

  group('watch-only wallets', () {
    test('open without any password when nothing else is on the device',
        () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = build(storage);
      await identity.load();
      expect(identity.status, WalletStatus.empty);

      await identity.addWatchWallet(
        name: 'Cold storage',
        addresses: <String, String>{'evm': evmWatch, 'btc': btcWatch},
      );

      expect(identity.status, WalletStatus.unlocked);
      expect(identity.isWatchOnly, isTrue);
      expect(identity.canSign, isFalse);
      expect(identity.seed, isNull);
      expect(identity.hasVault, isFalse);
      expect(identity.addressFor(NetworkCatalog.ethereum), evmWatch);
      expect(identity.addressFor(NetworkCatalog.polygon), evmWatch);
      expect(identity.addressFor(NetworkCatalog.bitcoin), btcWatch);
      // A family the wallet was not given has no address — never a made-up one.
      expect(identity.addressFor(NetworkCatalog.solana), isNull);
      expect(identity.addressFor(NetworkCatalog.bitcoinTestnet), isNull);

      identity.lock();
      expect(identity.status, WalletStatus.unlocked,
          reason: 'there is no password to come back with');
    });

    test('survive a restart', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController first = build(storage);
      await first.load();
      await first.addWatchWallet(
        name: 'Cold storage',
        addresses: <String, String>{'evm': evmWatch},
      );

      final WalletIdentityController second = build(storage);
      await second.load();
      expect(second.status, WalletStatus.unlocked);
      expect(second.activeWallet!.name, 'Cold storage');
      expect(second.addressFor(NetworkCatalog.ethereum), evmWatch);
    });

    test('sit next to a seed wallet and are never able to sign', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = await unlockedWallet(storage);
      final String own = identity.addressFor(NetworkCatalog.ethereum)!;

      final WalletEntry watch = await identity.addWatchWallet(
        name: 'Friend',
        addresses: <String, String>{'evm': evmWatch},
      );
      expect(identity.activeWalletId, watch.id);
      expect(identity.canSign, isFalse);
      expect(identity.seed, isNull);
      expect(identity.account, isNull);
      expect(identity.addressFor(NetworkCatalog.ethereum), evmWatch);

      await identity.selectWallet(primaryWalletId);
      expect(identity.canSign, isTrue);
      expect(identity.addressFor(NetworkCatalog.ethereum), own);
    });

    test('with a vault they wait behind the lock screen', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = await unlockedWallet(storage);
      await identity.addWatchWallet(
        name: 'Friend',
        addresses: <String, String>{'evm': evmWatch},
      );
      identity.lock();
      expect(identity.status, WalletStatus.locked);
      expect(identity.addressFor(NetworkCatalog.ethereum), isNull);

      await identity.unlock(pin);
      expect(identity.activeWallet!.name, 'Friend');
      expect(identity.addressFor(NetworkCatalog.ethereum), evmWatch);
    });

    test('can be removed and renamed without a password', () async {
      final WalletIdentityController identity =
          await unlockedWallet(_FakeWalletStorage());
      final WalletEntry watch = await identity.addWatchWallet(
        name: 'Friend',
        addresses: <String, String>{'evm': evmWatch},
      );
      await identity.renameWallet(watch.id, 'Mum');
      expect(identity.activeWallet!.name, 'Mum');

      await identity.removeWatchWallet(watch.id);
      expect(identity.wallets.map((WalletEntry w) => w.id), <String>['main']);
      expect(identity.activeWalletId, 'main');
      expect(identity.canSign, isTrue);
    });

    test('erasing the seed wallets keeps the watch-only ones open', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = await unlockedWallet(storage);
      await identity.addWatchWallet(
        name: 'Friend',
        addresses: <String, String>{'evm': evmWatch},
      );

      await identity.removeWallet();

      expect(storage.vault, isNull);
      expect(identity.status, WalletStatus.unlocked);
      expect(identity.hasVault, isFalse);
      expect(identity.activeWallet!.name, 'Friend');
      expect(identity.addressFor(NetworkCatalog.ethereum), evmWatch);
    });

    test('removing the last wallet returns to onboarding', () async {
      final WalletIdentityController identity = build(_FakeWalletStorage());
      await identity.load();
      final WalletEntry watch = await identity.addWatchWallet(
        name: 'Friend',
        addresses: <String, String>{'evm': evmWatch},
      );
      await identity.removeWatchWallet(watch.id);
      expect(identity.status, WalletStatus.empty);
    });

    test('adding a phrase to a watch-only device creates the vault', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = build(storage);
      await identity.load();
      await identity.addWatchWallet(
        name: 'Friend',
        addresses: <String, String>{'evm': evmWatch},
      );

      await identity.addSeedWallet(
        mnemonic: mnemonicA,
        password: pin,
        name: 'Mine',
      );

      expect(storage.vault, isNotNull);
      expect(identity.hasVault, isTrue);
      expect(identity.activeWallet!.name, 'Mine');
      expect(identity.wallets.map((WalletEntry w) => w.name),
          <String>['Mine', 'Friend']);
      expect(identity.canSign, isTrue);
    });

    test('their name and addresses can be changed afterwards', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = build(storage);
      await identity.load();
      final WalletEntry watch = await identity.addWatchWallet(
        name: 'Friend',
        addresses: <String, String>{'evm': evmWatch},
      );

      await identity.updateWatchWallet(
        id: watch.id,
        name: 'Cold storage',
        addresses: <String, String>{'evm': evmWatch, 'btc': btcWatch},
      );
      expect(identity.activeWallet!.name, 'Cold storage');
      expect(identity.addressFor(NetworkCatalog.bitcoin), btcWatch);

      final WalletIdentityController reopened = build(storage);
      await reopened.load();
      expect(reopened.activeWallet!.name, 'Cold storage');
      expect(reopened.addressFor(NetworkCatalog.bitcoin), btcWatch);

      await expectLater(
        identity.updateWatchWallet(
          id: watch.id,
          name: 'x',
          addresses: const <String, String>{},
        ),
        throwsA(isA<SeedVaultException>()),
      );
    });

    test('refuse an empty address list', () async {
      final WalletIdentityController identity = build(_FakeWalletStorage());
      await identity.load();
      await expectLater(
        identity.addWatchWallet(name: 'x', addresses: const <String, String>{}),
        throwsA(isA<SeedVaultException>()),
      );
    });
  });

  group('recognising an address', () {
    test('sorts addresses into chain families', () {
      expect(WatchAddresses.detect(evmWatch)!.family, 'evm');
      expect(WatchAddresses.detect(btcWatch)!.family, 'btc');
      expect(
        WatchAddresses.detect('tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx')!
            .family,
        'btc-test',
      );
      expect(
        WatchAddresses.detect('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa')!.family,
        'btc',
      );
      expect(
        WatchAddresses.detect('11111111111111111111111111111111')!.family,
        'sol',
      );
      expect(WatchAddresses.detect('0x1')!.family, 'apt');
    });

    test('rejects garbage and a bad EIP-55 checksum', () {
      expect(WatchAddresses.detect('hello'), isNull);
      expect(WatchAddresses.detect(''), isNull);
      // One letter's case flipped: the mixed-case checksum no longer matches.
      expect(
        WatchAddresses.detect('0xd8DA6BF26964aF9D7eEd9e03E53415D37aA96045'),
        isNull,
      );
      expect(
        WatchAddresses.explain('0xd8DA6BF26964aF9D7eEd9e03E53415D37aA96045'),
        'The address checksum does not match',
      );
    });

    test('every network maps to the family its address is stored under', () {
      expect(WatchAddresses.familyOf(NetworkCatalog.bitcoin), 'btc');
      expect(WatchAddresses.familyOf(NetworkCatalog.bitcoinTestnet), 'btc-test');
      expect(WatchAddresses.familyOf(NetworkCatalog.sepolia), 'evm');
      expect(WatchAddresses.familyOf(NetworkCatalog.solanaDevnet), 'sol');
      expect(WatchAddresses.familyOf(NetworkCatalog.aptos), 'apt');
    });
  });

  group('the wallet book', () {
    test('round-trips names, the active wallet and watch wallets', () {
      const WalletBook book = WalletBook(
        activeId: 'w3',
        names: <String, String>{'main': 'Daily'},
        watch: <WalletEntry>[
          WalletEntry(
            id: 'w3',
            name: 'Friend',
            kind: WalletKind.watchOnly,
            watched: <String, String>{'evm': evmWatch},
          ),
        ],
      );
      final WalletBook back = WalletBook.fromJson(book.toJson());
      expect(back.activeId, 'w3');
      expect(back.names['main'], 'Daily');
      expect(back.watch.single.watched['evm'], evmWatch);
    });

    test('a corrupt book reads as empty', () {
      expect(WalletBook.fromJson('not json').watch, isEmpty);
      expect(WalletBook.fromJson(null).activeId, primaryWalletId);
      expect(WalletBook.fromJson('[1,2]').watch, isEmpty);
    });
  });

  group('account names per wallet', () {
    test('another wallet never inherits the first wallet\'s names', () async {
      final SettingsController settings = SettingsController();
      await settings.load();
      settings.renameAccount(0, 'Daily');
      settings.renameAccount(0, 'Vault', walletId: 'w2');

      expect(settings.accountName(0), 'Daily');
      expect(settings.accountName(0, walletId: 'w2'), 'Vault');
      expect(settings.accountName(1, walletId: 'w2'), 'Account 2');
    });
  });
}
