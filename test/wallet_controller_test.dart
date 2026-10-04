import 'dart:convert';

import 'package:crypto_wallet/core/utils/formatters.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/networks/price_api.dart';
import 'package:crypto_wallet/data/wallet/seed_vault.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
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

  test('retryPrice forces a fresh request even within the cache TTL', () async {
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
    await wallet.retryPrice();
    await settle(wallet);
    expect(priceRequests, 2);
    expect(wallet.snapshot?.price?.usd, 60000);

    wallet.dispose();
  });
}
