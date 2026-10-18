import 'dart:convert';
import 'dart:io';

import 'package:crypto_wallet/core/utils/formatters.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/networks/price_api.dart';
import 'package:crypto_wallet/data/notifications/notification_service.dart';
import 'package:crypto_wallet/data/wallet/seed_vault.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/features/settings/settings_screen.dart';
import 'package:crypto_wallet/state/confirmation_watcher.dart';
import 'package:crypto_wallet/state/settings_controller.dart';
import 'package:crypto_wallet/state/wallet_controller.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the platform keystore so the vault can be stored
/// without a real secure-storage plugin in unit tests.
class _FakeVaultStorage extends WalletStorage {
  _FakeVaultStorage(this.vault);

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

/// Counts system notifications instead of posting them.
class _RecordingNotifications extends NotificationService {
  int shown = 0;

  @override
  bool get enabled => true;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    shown++;
  }
}

/// Watched-transfer storage that keeps everything in memory.
class _NoopWatchStorage extends WalletStorage {
  final List<String> watched = <String>[];

  @override
  Future<List<String>> readWatchedTxs() async => List<String>.from(watched);

  @override
  Future<void> writeWatchedTxs(List<String> hashes) async {
    watched
      ..clear()
      ..addAll(hashes);
  }
}

/// Chain that reports one outgoing transfer: pending while [pendingLoads]
/// balance reads remain, confirmed after that.
class _PendingChainApi extends ChainApi {
  _PendingChainApi({required this.pendingLoads});

  int pendingLoads;
  int transactionReads = 0;

  @override
  Future<BigInt> fetchBalance(NetworkConfig network, String address) async {
    if (pendingLoads > 0) {
      pendingLoads--;
    }
    return BigInt.parse('2000000000000000000');
  }

  @override
  Future<List<ChainTransaction>> fetchTransactions(
    NetworkConfig network,
    String address,
  ) async {
    transactionReads++;
    return <ChainTransaction>[
      ChainTransaction(
        hash: '0xpending',
        timestamp: DateTime(2026),
        amount: -BigInt.from(1000),
        fee: BigInt.one,
        counterparty: '0xdef',
        isIncoming: false,
        confirmed: pendingLoads == 0,
        nonce: 3,
      ),
    ];
  }

  @override
  Future<List<TokenBalance>> fetchTokenBalances(
    NetworkConfig network,
    String address,
  ) async =>
      const <TokenBalance>[];

  @override
  void dispose() {}
}

/// Price API that answers "no price" without touching the network.
class _FakePriceApi extends PriceApi {
  @override
  Future<CoinPrice?> fetchPrice(String coinGeckoId) async => null;

  @override
  Future<List<double>> fetchChart(String coinGeckoId) async =>
      const <double>[];

  @override
  void dispose() {}
}

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';
  const int fastRounds = 1000;

  http.Response json(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );

  /// Responds to every endpoint the wallet talks to.
  MockClient mockClient() => MockClient((request) async {
        final String url = request.url.toString();
        if (url.contains('/txs')) {
          return json(<Object>[]);
        }
        if (url.contains('mempool.space')) {
          return json(<String, Object>{
            'chain_stats': <String, Object>{
              'funded_txo_sum': 150000000,
              'spent_txo_sum': 0,
            },
            'mempool_stats': <String, Object>{
              'funded_txo_sum': 0,
              'spent_txo_sum': 0,
            },
          });
        }
        if (url.contains('/transactions')) {
          return json(<String, Object>{'items': <Object>[]});
        }
        if (url.contains('/addresses/')) {
          return json(<String, Object>{'coin_balance': '2500000000000000000'});
        }
        if (url.contains('simple/price')) {
          return json(<String, Object>{
            'bitcoin': <String, Object>{'usd': 60000.0, 'usd_24h_change': 1.5},
          });
        }
        if (url.contains('market_chart')) {
          return json(<String, Object>{
            'prices': <Object>[
              <Object>[1, 100.0],
              <Object>[2, 110.0],
            ],
          });
        }
        return http.Response('{}', 404);
      });

  WalletController buildWallet(
    WalletIdentityController identity,
    SettingsController settings,
    MockClient client,
  ) =>
      WalletController(
        identity: identity,
        settings: settings,
        chainApi: ChainApi(client: client),
        priceApi: PriceApi(client: client),
      );

  /// Waits until the controller finished its async load.
  Future<void> settle(WalletController wallet) async {
    await Future<void>.delayed(Duration.zero);
    for (int i = 0; i < 200 && wallet.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<WalletIdentityController> storedWallet() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'nova.wallet.createdAt': DateTime(2026, 1, 1).toIso8601String(),
    });
    final WalletStorage storage = _FakeVaultStorage(
      SeedVault.encrypt(mnemonic, pin, rounds: fastRounds),
    );
    final WalletIdentityController identity = WalletIdentityController(
      storage: storage,
    );
    await identity.load();
    return identity;
  }

  test('stays locked and has no address until the PIN is entered', () async {
    final WalletIdentityController identity = await storedWallet();
    final SettingsController settings = SettingsController();
    final WalletController wallet =
        buildWallet(identity, settings, mockClient());

    expect(identity.status, WalletStatus.locked);
    expect(wallet.address, isNull);
    expect(wallet.snapshot, isNull);

    wallet.dispose();
  });

  test('loads balance, price and chart after unlocking', () async {
    final WalletIdentityController identity = await storedWallet();
    await identity.unlock(pin);

    final SettingsController settings = SettingsController();
    final WalletController wallet =
        buildWallet(identity, settings, mockClient());
    await settle(wallet);

    expect(wallet.error, isNull);
    final snapshot = wallet.snapshot;
    expect(snapshot, isNotNull);
    expect(snapshot!.network.id, NetworkCatalog.bitcoin.id);
    expect(snapshot.nativeLabel, '1.5');
    expect(snapshot.price?.usd, 60000);
    expect(snapshot.fiatBalance, closeTo(90000, 1e-6));
    expect(snapshot.chart, hasLength(2));

    wallet.dispose();
  });

  test('reloads when the network changes', () async {
    final WalletIdentityController identity = await storedWallet();
    await identity.unlock(pin);

    final SettingsController settings = SettingsController();
    final WalletController wallet =
        buildWallet(identity, settings, mockClient());
    await settle(wallet);

    settings.setNetwork(NetworkCatalog.ethereum);
    await settle(wallet);

    expect(wallet.snapshot?.network.id, NetworkCatalog.ethereum.id);
    expect(wallet.snapshot?.nativeBalance, closeTo(2.5, 1e-9));

    wallet.dispose();
  });

  test('surfaces API failures instead of showing stale data', () async {
    final WalletIdentityController identity = await storedWallet();
    await identity.unlock(pin);

    final SettingsController settings = SettingsController();
    final MockClient failing =
        MockClient((_) async => http.Response('boom', 500));
    final WalletController wallet = buildWallet(identity, settings, failing);
    await settle(wallet);

    expect(wallet.error, isNotNull);
    expect(wallet.snapshot, isNull);

    wallet.dispose();
  });

  test('keeps the last known price when a reload is rate-limited', () async {
    final WalletIdentityController identity = await storedWallet();
    await identity.unlock(pin);

    final SettingsController settings = SettingsController();
    bool failPrice = false;
    final MockClient client = MockClient((request) async {
      final String url = request.url.toString();
      if (url.contains('simple/price')) {
        return failPrice
            ? http.Response('rate limited', 429)
            : json(<String, Object>{
                'bitcoin': <String, Object>{
                  'usd': 60000.0,
                  'usd_24h_change': 1.5,
                },
              });
      }
      if (url.contains('market_chart')) {
        return json(<String, Object>{
          'prices': <Object>[
            <Object>[1, 100.0],
          ],
        });
      }
      if (url.contains('/txs')) {
        return json(<Object>[]);
      }
      if (url.contains('mempool.space')) {
        return json(<String, Object>{
          'chain_stats': <String, Object>{
            'funded_txo_sum': 150000000,
            'spent_txo_sum': 0,
          },
          'mempool_stats': <String, Object>{
            'funded_txo_sum': 0,
            'spent_txo_sum': 0,
          },
        });
      }
      return http.Response('{}', 404);
    });

    final WalletController wallet = buildWallet(identity, settings, client);
    await settle(wallet);
    expect(wallet.snapshot?.price?.usd, 60000);

    // CoinGecko starts rate-limiting the free tier (HTTP 429). A refresh and a
    // currency switch must not blank the price we already have — otherwise the
    // hero card would wrongly fall back to "no market price".
    failPrice = true;
    await wallet.refresh();
    await settle(wallet);
    expect(wallet.snapshot?.price?.usd, 60000);

    settings.setCurrency(AppCurrency.eur);
    await settle(wallet);
    expect(wallet.snapshot?.price?.usd, 60000);

    wallet.dispose();
  });

  test('refresh forces a fresh request even within the cache TTL', () async {
    final WalletIdentityController identity = await storedWallet();
    await identity.unlock(pin);

    final SettingsController settings = SettingsController();
    int priceRequests = 0;
    final MockClient client = MockClient((request) async {
      final String url = request.url.toString();
      if (url.contains('simple/price')) {
        priceRequests++;
        return json(<String, Object>{
          'bitcoin': <String, Object>{'usd': 60000.0, 'usd_24h_change': 1.5},
        });
      }
      if (url.contains('market_chart')) {
        return json(<String, Object>{
          'prices': <Object>[
            <Object>[1, 100.0],
          ],
        });
      }
      if (url.contains('/txs')) {
        return json(<Object>[]);
      }
      if (url.contains('mempool.space')) {
        return json(<String, Object>{
          'chain_stats': <String, Object>{
            'funded_txo_sum': 150000000,
            'spent_txo_sum': 0,
          },
          'mempool_stats': <String, Object>{
            'funded_txo_sum': 0,
            'spent_txo_sum': 0,
          },
        });
      }
      return http.Response('{}', 404);
    });

    final WalletController wallet = buildWallet(identity, settings, client);
    await settle(wallet);
    expect(priceRequests, 1);

    // The default TTL (60 s) would suppress a second request; retry must bypass
    // the cache and hit the network again.
    await wallet.refresh();
    await settle(wallet);
    expect(priceRequests, 2);
    expect(wallet.snapshot?.price?.usd, 60000);

    wallet.dispose();
  });

  test('portfolioFiat includes priced ERC-20 tokens: 5 ETH + 1000 USDC = 1005',
      () async {
    final WalletIdentityController identity = await storedWallet();
    await identity.unlock(pin);

    final SettingsController settings = SettingsController();
    settings.setNetwork(NetworkCatalog.ethereum);

    final MockClient client = MockClient((request) async {
      final String url = request.url.toString();
      if (url.contains('/transactions')) {
        return json(<String, Object>{'items': <Object>[]});
      }
      if (url.contains('/tokens')) {
        return json(<String, Object>{
          'items': <Object>[
            <String, Object>{
              'value': '1000000000', // 1000 USDC (6 decimals)
              'token': <String, Object?>{
                'symbol': 'USDC',
                'name': 'USD Coin',
                'decimals': '6',
                'address_hash': '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
                'exchange_rate': '1.0',
              },
            },
            <String, Object>{
              'value': '500000000000000000000', // unpriced token — ignored
              'token': <String, Object?>{
                'symbol': 'MEME',
                'name': 'Unpriced Token',
                'decimals': '18',
                'address_hash': '0x1111111111111111111111111111111111111111',
                'exchange_rate': null,
              },
            },
          ],
        });
      }
      if (url.contains('/addresses/')) {
        // 0.002 ETH at $2500 = $5
        return json(<String, Object>{'coin_balance': '2000000000000000'});
      }
      if (url.contains('simple/price')) {
        return json(<String, Object>{
          'ethereum': <String, Object>{'usd': 2500.0, 'usd_24h_change': 0.5},
        });
      }
      if (url.contains('market_chart')) {
        return json(<String, Object>{'prices': <Object>[]});
      }
      return http.Response('{}', 404);
    });

    final WalletController wallet = buildWallet(identity, settings, client);
    await settle(wallet);
    // `_load` finishes before the unawaited `_refreshPortfolio()` recompute;
    // yield a beat so portfolioFiat is settled too.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(wallet.snapshot?.fiatBalance, closeTo(5.0, 1e-6));
    expect(wallet.portfolioFiat, closeTo(1005.0, 1e-6));

    wallet.dispose();
  });

  test('appVersion and appBuildNumber match pubspec.yaml', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? match =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(match?.group(1), '$appVersion+$appBuildNumber');
  });

  group('pending polling (A6)', () {
    test('re-loads while a transfer is pending and stops once it confirms',
        () async {
      final WalletIdentityController identity = await storedWallet();
      await identity.unlock(pin);

      final SettingsController settings = SettingsController();
      final _PendingChainApi api = _PendingChainApi(pendingLoads: 3);
      final WalletController wallet = WalletController(
        identity: identity,
        settings: settings,
        chainApi: api,
        priceApi: _FakePriceApi(),
        // Short cadence so the test runs in milliseconds, not 20 s.
        pendingPollInterval: const Duration(milliseconds: 10),
      );
      await settle(wallet);
      final int readsAfterFirstLoad = api.transactionReads;

      // The transfer is still pending: the controller must re-read on its own,
      // without a pull-to-refresh.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        api.transactionReads,
        greaterThan(readsAfterFirstLoad),
        reason: 'a pending outgoing transfer must be polled',
      );

      // Once the chain reports it confirmed, polling stops: no further reads.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final int readsAfterConfirm = api.transactionReads;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(api.transactionReads, readsAfterConfirm);
      expect(wallet.snapshot?.transactions.single.confirmed, isTrue);

      wallet.dispose();
    });

    test('notifies exactly once when the polled transfer confirms', () async {
      final WalletIdentityController identity = await storedWallet();
      await identity.unlock(pin);

      final SettingsController settings = SettingsController()
        ..setNotificationsEnabled(true);
      final _PendingChainApi api = _PendingChainApi(pendingLoads: 2);
      final WalletController wallet = WalletController(
        identity: identity,
        settings: settings,
        chainApi: api,
        priceApi: _FakePriceApi(),
        pendingPollInterval: const Duration(milliseconds: 10),
      );
      final _RecordingNotifications notifications =
          _RecordingNotifications();
      final ConfirmationWatcher watcher = ConfirmationWatcher(
        wallet: wallet,
        settings: settings,
        notifications: notifications,
        storage: _NoopWatchStorage(),
      );
      await settle(wallet);

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(notifications.shown, 1,
          reason: 'the transfer must be announced exactly once');

      watcher.dispose();
      wallet.dispose();
    });

    test('does not poll when nothing is pending', () async {
      final WalletIdentityController identity = await storedWallet();
      await identity.unlock(pin);

      final SettingsController settings = SettingsController()
        ..setNetwork(NetworkCatalog.ethereum);
      int historyReads = 0;
      final MockClient confirmedOnly = MockClient((request) async {
        final String url = request.url.toString();
        if (url.contains('/transactions')) {
          historyReads++;
          return json(<String, Object>{
            'items': <Object>[
              <String, Object>{
                'hash': '0xdone',
                'timestamp': '2026-01-02T10:00:00.000000Z',
                'from': <String, Object>{'hash': '0xdef'},
                'to': <String, Object>{'hash': '0x9858'},
                'value': '1',
                'fee': <String, Object>{'value': '1'},
                'status': 'ok',
                'block': 1,
                'nonce': 1,
              },
            ],
          });
        }
        if (url.contains('/addresses/')) {
          return json(<String, Object>{'coin_balance': '1'});
        }
        return http.Response('{}', 404);
      });
      final WalletController wallet = WalletController(
        identity: identity,
        settings: settings,
        chainApi: ChainApi(client: confirmedOnly),
        priceApi: PriceApi(client: confirmedOnly),
        pendingPollInterval: const Duration(milliseconds: 10),
      );
      await settle(wallet);
      expect(historyReads, 1);

      // Nothing is pending, so the poller must stay silent.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(historyReads, 1);

      wallet.dispose();
    });
  });
}
