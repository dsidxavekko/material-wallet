import 'dart:convert';

import 'package:crypto_wallet/data/background/background_checker.dart';
import 'package:crypto_wallet/data/background/background_targets.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/snapshot_cache.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/state/background_targets_sync.dart';
import 'package:crypto_wallet/state/settings_controller.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeChain extends ChainApi {
  final Map<String, ActivityPage> pages = <String, ActivityPage>{};
  final Set<String> failing = <String>{};
  int reads = 0;

  @override
  Future<ActivityPage> fetchActivityPage(
    NetworkConfig network,
    String address, {
    ActivityCursor? after,
  }) async {
    reads++;
    if (failing.contains(network.id)) {
      throw const ChainApiException('node down');
    }
    return pages['${network.id}|$address'] ?? const ActivityPage();
  }

  @override
  void dispose() {}
}

class _Sent {
  _Sent(this.id, this.title, this.body);
  final int id;
  final String title;
  final String body;
}

ChainTransaction _tx(
  String hash, {
  required bool incoming,
  bool confirmed = true,
  int sats = 150000000,
  bool failed = false,
}) =>
    ChainTransaction(
      hash: hash,
      timestamp: DateTime(2026),
      amount: incoming ? BigInt.from(sats) : -BigInt.from(sats),
      fee: BigInt.zero,
      counterparty: 'bc1qother',
      isIncoming: incoming,
      confirmed: confirmed,
      failed: failed,
    );

void main() {
  const String addr = 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu';

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> seedTargets(
    WalletStorage storage, {
    List<BackgroundTarget>? targets,
  }) =>
      storage.writeBackgroundTargets(
        BackgroundTarget.encode(
          targets ??
              const <BackgroundTarget>[
                BackgroundTarget(
                  walletId: 'main',
                  walletName: 'Wallet 1',
                  networkId: 'bitcoin',
                  address: addr,
                ),
              ],
        ),
      );

  BackgroundChecker checker(
    _FakeChain chain,
    List<_Sent> sent,
    WalletStorage storage,
  ) =>
      BackgroundChecker(
        chainApi: chain,
        storage: storage,
        sink: ({
          required int id,
          required String title,
          required String body,
          required bool incoming,
        }) async =>
            sent.add(_Sent(id, title, body)),
      );

  group('incoming funds', () {
    test('the first pass learns the history and tells nobody', () async {
      const WalletStorage storage = WalletStorage();
      await seedTargets(storage);
      final _FakeChain chain = _FakeChain()
        ..pages['bitcoin|$addr'] = ActivityPage(
          native: <ChainTransaction>[_tx('old1', incoming: true)],
        );
      final List<_Sent> sent = <_Sent>[];

      expect(await checker(chain, sent, storage).run(), 0);
      expect(sent, isEmpty);
    });

    test('a transfer that arrives afterwards is announced exactly once', () async {
      const WalletStorage storage = WalletStorage();
      await seedTargets(storage);
      final _FakeChain chain = _FakeChain()
        ..pages['bitcoin|$addr'] = ActivityPage(
          native: <ChainTransaction>[_tx('old1', incoming: true)],
        );
      final List<_Sent> sent = <_Sent>[];
      await checker(chain, sent, storage).run(); // learns old1

      chain.pages['bitcoin|$addr'] = ActivityPage(
        native: <ChainTransaction>[
          _tx('new1', incoming: true, confirmed: false),
          _tx('old1', incoming: true),
        ],
      );
      expect(await checker(chain, sent, storage).run(), 1);
      expect(sent.single.title, 'Funds received');
      expect(sent.single.body, contains('1.5 BTC'));
      expect(sent.single.body, contains('Bitcoin'));

      // The same page again, now confirmed: nothing new to say.
      chain.pages['bitcoin|$addr'] = ActivityPage(
        native: <ChainTransaction>[
          _tx('new1', incoming: true),
          _tx('old1', incoming: true),
        ],
      );
      expect(await checker(chain, sent, storage).run(), 0);
      expect(sent, hasLength(1));
    });

    test('privacy mode keeps the amount out of the notification', () async {
      const WalletStorage storage = WalletStorage();
      await seedTargets(storage);
      await storage.writeHideBalances(true);
      final _FakeChain chain = _FakeChain();
      final List<_Sent> sent = <_Sent>[];
      await checker(chain, sent, storage).run();

      chain.pages['bitcoin|$addr'] = ActivityPage(
        native: <ChainTransaction>[_tx('new1', incoming: true)],
      );
      await checker(chain, sent, storage).run();
      expect(sent.single.body, isNot(contains('BTC')));
      expect(sent.single.body, contains('Bitcoin'));
    });

    test('a failed and a zero-value row are never announced', () async {
      const WalletStorage storage = WalletStorage();
      await seedTargets(storage);
      final _FakeChain chain = _FakeChain();
      final List<_Sent> sent = <_Sent>[];
      await checker(chain, sent, storage).run();

      chain.pages['bitcoin|$addr'] = ActivityPage(
        native: <ChainTransaction>[
          _tx('failed', incoming: true, failed: true),
          _tx('zero', incoming: true, sats: 0),
        ],
      );
      expect(await checker(chain, sent, storage).run(), 0);
    });

    test('an unreachable node changes nothing and is retried next time',
        () async {
      const WalletStorage storage = WalletStorage();
      await seedTargets(storage);
      final _FakeChain chain = _FakeChain();
      final List<_Sent> sent = <_Sent>[];
      await checker(chain, sent, storage).run(); // learns an empty history

      chain.failing.add('bitcoin');
      expect(await checker(chain, sent, storage).run(), 0);

      chain
        ..failing.clear()
        ..pages['bitcoin|$addr'] = ActivityPage(
          native: <ChainTransaction>[_tx('new1', incoming: true)],
        );
      expect(await checker(chain, sent, storage).run(), 1);
    });

    test('nothing to watch means no network traffic', () async {
      const WalletStorage storage = WalletStorage();
      final _FakeChain chain = _FakeChain();
      expect(await checker(chain, <_Sent>[], storage).run(), 0);
      expect(chain.reads, 0);
    });

    test('an address shared by two wallets is read once', () async {
      const WalletStorage storage = WalletStorage();
      await seedTargets(
        storage,
        targets: const <BackgroundTarget>[
          BackgroundTarget(
            walletId: 'main',
            walletName: 'A',
            networkId: 'bitcoin',
            address: addr,
          ),
          BackgroundTarget(
            walletId: 'w2',
            walletName: 'B',
            networkId: 'bitcoin',
            address: addr,
          ),
        ],
      );
      final _FakeChain chain = _FakeChain();
      await checker(chain, <_Sent>[], storage).run();
      expect(chain.reads, 1);
    });

    test('with several wallets the notification names the wallet', () async {
      const WalletStorage storage = WalletStorage();
      await seedTargets(
        storage,
        targets: const <BackgroundTarget>[
          BackgroundTarget(
            walletId: 'main',
            walletName: 'Savings',
            networkId: 'bitcoin',
            address: addr,
          ),
          BackgroundTarget(
            walletId: 'w2',
            walletName: 'Daily',
            networkId: 'ethereum',
            address: '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045',
          ),
        ],
      );
      final _FakeChain chain = _FakeChain();
      final List<_Sent> sent = <_Sent>[];
      await checker(chain, sent, storage).run();

      chain.pages['bitcoin|$addr'] = ActivityPage(
        native: <ChainTransaction>[_tx('new1', incoming: true)],
      );
      await checker(chain, sent, storage).run();
      expect(sent.single.body, contains('Savings'));
    });
  });

  group('tokens', () {
    const String eth = '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045';

    TokenTransfer transfer(String hash, String symbol) => TokenTransfer(
          hash: hash,
          timestamp: DateTime(2026),
          from: '0x1111111111111111111111111111111111111111',
          to: eth,
          value: BigInt.from(5000000),
          decimals: 6,
          symbol: symbol,
          contract: '0xcontract$symbol',
        );

    Future<WalletStorage> setup(_FakeChain chain, {List<String>? held}) async {
      const WalletStorage storage = WalletStorage();
      await seedTargets(
        storage,
        targets: const <BackgroundTarget>[
          BackgroundTarget(
            walletId: 'main',
            walletName: 'A',
            networkId: 'ethereum',
            address: eth,
          ),
        ],
      );
      await const SnapshotCache().write(
        AccountSnapshot(
          network: NetworkCatalog.ethereum,
          address: eth,
          balance: BigInt.zero,
          transactions: const <ChainTransaction>[],
          chart: const <double>[],
          tokens: <TokenBalance>[
            for (final String symbol in held ?? const <String>['USDC'])
              TokenBalance(
                symbol: symbol,
                name: symbol,
                decimals: 6,
                balance: BigInt.from(1000000),
                contractAddress: '0xcontract$symbol',
              ),
          ],
          fetchedAt: DateTime(2026),
        ),
      );
      return storage;
    }

    test('a token the user already holds is announced', () async {
      final _FakeChain chain = _FakeChain();
      final WalletStorage storage = await setup(chain);
      final List<_Sent> sent = <_Sent>[];
      await checker(chain, sent, storage).run();

      chain.pages['ethereum|$eth'] =
          ActivityPage(transfers: <TokenTransfer>[transfer('0xabc', 'USDC')]);
      expect(await checker(chain, sent, storage).run(), 1);
      expect(sent.single.body, contains('USDC'));
    });

    test('an unsolicited airdrop of an unknown token stays quiet', () async {
      final _FakeChain chain = _FakeChain();
      final WalletStorage storage = await setup(chain);
      final List<_Sent> sent = <_Sent>[];
      await checker(chain, sent, storage).run();

      chain.pages['ethereum|$eth'] =
          ActivityPage(transfers: <TokenTransfer>[transfer('0xspam', 'FREE')]);
      expect(await checker(chain, sent, storage).run(), 0);
    });

    test('a token the user hid stays quiet too', () async {
      final _FakeChain chain = _FakeChain();
      final WalletStorage storage = await setup(chain);
      await storage.writeHiddenTokens(jsonEncode(<String>['ethereum:0xcontractusdc']));
      final List<_Sent> sent = <_Sent>[];
      await checker(chain, sent, storage).run();

      chain.pages['ethereum|$eth'] =
          ActivityPage(transfers: <TokenTransfer>[transfer('0xabc', 'USDC')]);
      expect(await checker(chain, sent, storage).run(), 0);
    });
  });

  group('confirmed transfers', () {
    test('a watched outgoing transfer is announced once and forgotten', () async {
      const WalletStorage storage = WalletStorage();
      await seedTargets(storage);
      await storage.writeWatchedTxs(<String>['out1']);
      final _FakeChain chain = _FakeChain()
        ..pages['bitcoin|$addr'] = ActivityPage(
          native: <ChainTransaction>[
            _tx('out1', incoming: false, confirmed: false),
          ],
        );
      final List<_Sent> sent = <_Sent>[];

      // Still pending: keep waiting, say nothing.
      await checker(chain, sent, storage).run();
      expect(sent, isEmpty);
      expect(await storage.readWatchedTxs(), <String>['out1']);

      chain.pages['bitcoin|$addr'] = ActivityPage(
        native: <ChainTransaction>[_tx('out1', incoming: false)],
      );
      await checker(chain, sent, storage).run();
      expect(sent.single.title, 'Transfer confirmed');
      expect(await storage.readWatchedTxs(), isEmpty);

      await checker(chain, sent, storage).run();
      expect(sent, hasLength(1));
    });

    test('an outgoing transfer nobody was waiting on is history', () async {
      const WalletStorage storage = WalletStorage();
      await seedTargets(storage);
      final _FakeChain chain = _FakeChain()
        ..pages['bitcoin|$addr'] = ActivityPage(
          native: <ChainTransaction>[_tx('out1', incoming: false)],
        );
      final List<_Sent> sent = <_Sent>[];
      await checker(chain, sent, storage).run();
      expect(sent, isEmpty);
    });
  });

  group('keeping the target list in step with the wallet', () {
    const String evmWatch = '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045';
    const String mnemonic =
        'abandon abandon abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon about';

    test('stores the open wallet\'s addresses and prunes removed wallets',
        () async {
      const WalletStorage storage = WalletStorage();
      final WalletIdentityController identity =
          WalletIdentityController(storage: _MemoryVault(), kdfRounds: 1000);
      await identity.load();
      await identity.createWallet(mnemonic: mnemonic, pin: '12345678');
      final BackgroundTargetsSync sync = BackgroundTargetsSync(identity: identity);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      List<BackgroundTarget> targets =
          BackgroundTarget.decode(await storage.readBackgroundTargets());
      expect(targets.map((BackgroundTarget t) => t.networkId).toSet(),
          containsAll(<String>['bitcoin', 'ethereum', 'solana', 'aptos']));
      expect(targets.every((BackgroundTarget t) => t.walletId == 'main'), isTrue);

      // A watch-only wallet contributes its own addresses straight away.
      final watch = await identity.addWatchWallet(
        name: 'Friend',
        addresses: <String, String>{'evm': evmWatch},
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      targets = BackgroundTarget.decode(await storage.readBackgroundTargets());
      expect(
        targets
            .where((BackgroundTarget t) => t.walletId == watch.id)
            .map((BackgroundTarget t) => t.address)
            .toSet(),
        <String>{evmWatch},
      );
      // …while the seed wallet's remembered addresses are kept.
      expect(targets.any((BackgroundTarget t) => t.walletId == 'main'), isTrue);

      await identity.removeWatchWallet(watch.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      targets = BackgroundTarget.decode(await storage.readBackgroundTargets());
      expect(targets.any((BackgroundTarget t) => t.walletId == watch.id), isFalse);

      sync.dispose();
    });

    test('nothing is watched once every wallet is gone', () async {
      const WalletStorage storage = WalletStorage();
      final WalletIdentityController identity =
          WalletIdentityController(storage: _MemoryVault(), kdfRounds: 1000);
      await identity.load();
      await identity.createWallet(mnemonic: mnemonic, pin: '12345678');
      final BackgroundTargetsSync sync = BackgroundTargetsSync(identity: identity);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(BackgroundTarget.decode(await storage.readBackgroundTargets()),
          isNotEmpty);

      await identity.removeWallet();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(BackgroundTarget.decode(await storage.readBackgroundTargets()),
          isEmpty);
      sync.dispose();
    });
  });

  test('the setting persists', () async {
    final SettingsController settings = SettingsController();
    await settings.load();
    expect(settings.backgroundChecks, isFalse);
    settings.setBackgroundChecks(true);
    await Future<void>.delayed(Duration.zero);

    final SettingsController reloaded = SettingsController();
    await reloaded.load();
    expect(reloaded.backgroundChecks, isTrue);
  });

  test('a stored target list that is garbage reads as empty', () {
    expect(BackgroundTarget.decode('nope'), isEmpty);
    expect(BackgroundTarget.decode('[1,{"w":"x"}]'), isEmpty);
    expect(BackgroundTarget.decode(null), isEmpty);
  });
}

class _MemoryVault extends WalletStorage {
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
