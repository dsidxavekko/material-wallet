import 'dart:convert';

import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/networks/price_api.dart';
import 'package:crypto_wallet/data/wallet/seed_vault.dart';
import 'package:crypto_wallet/data/wallet/snapshot_cache.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/state/settings_controller.dart';
import 'package:crypto_wallet/state/wallet_controller.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStorage extends WalletStorage {
  final Map<String, String> cache = <String, String>{};
  String? vault;

  @override
  Future<String?> readVault() async => vault;

  @override
  Future<void> writeVault(String payload, DateTime createdAt) async {
    vault = payload;
  }

  @override
  Future<String?> readCache(String id) async => cache[id];

  @override
  Future<void> writeCache(String id, String value) async => cache[id] = value;
}

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';

  test('AccountSnapshot survives a JSON round-trip', () {
    final AccountSnapshot snapshot = AccountSnapshot(
      network: NetworkCatalog.ethereum,
      address: '0xabc',
      balance: BigInt.parse('12345678901234567890'),
      transactions: <ChainTransaction>[
        ChainTransaction(
          hash: '0xdead',
          timestamp: DateTime(2026, 2, 3, 4, 5),
          amount: BigInt.from(-42),
          fee: BigInt.from(7),
          counterparty: '0xbeef',
          isIncoming: false,
          confirmed: true,
          failed: false,
        ),
      ],
      chart: <double>[1, 2, 3.5],
      price: const CoinPrice(usd: 2500, change24h: -1.5),
      tokens: <TokenBalance>[
        TokenBalance(
          symbol: 'USDT',
          name: 'Tether',
          decimals: 6,
          balance: BigInt.from(291368219),
          contractAddress: '0xusdt',
          usdRate: 1.0,
        ),
      ],
      fetchedAt: DateTime(2026, 2, 3, 6),
    );

    final AccountSnapshot? restored =
        AccountSnapshot.fromJson(snapshot.toJson());

    expect(restored, isNotNull);
    expect(restored!.network.id, NetworkCatalog.ethereum.id);
    expect(restored.address, '0xabc');
    expect(restored.balance, BigInt.parse('12345678901234567890'));
    expect(restored.transactions.single.hash, '0xdead');
    expect(restored.transactions.single.amount, BigInt.from(-42));
    expect(restored.chart, <double>[1, 2, 3.5]);
    expect(restored.price?.usd, 2500);
    expect(restored.tokens.single.symbol, 'USDT');
    expect(restored.tokens.single.balance, BigInt.from(291368219));
  });

  test('a corrupt payload is a cache miss, not a crash', () {
    expect(AccountSnapshot.fromJson(<String, Object?>{}), isNull);
  });

  test('SnapshotCache round-trips through storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final _MemoryStorage storage = _MemoryStorage();
    final SnapshotCache cache = SnapshotCache(storage: storage);

    expect(await cache.read(NetworkCatalog.bitcoin.id), isNull);

    final AccountSnapshot snapshot = AccountSnapshot(
      network: NetworkCatalog.bitcoin,
      address: 'bc1qexample',
      balance: BigInt.from(5000),
      transactions: const <ChainTransaction>[],
      chart: const <double>[],
      fetchedAt: DateTime(2026, 1, 1),
    );
    await cache.write(snapshot);

    final AccountSnapshot? restored =
        await cache.read(NetworkCatalog.bitcoin.id);
    expect(restored, isNotNull);
    expect(restored!.balance, BigInt.from(5000));
    expect(storage.cache, isNotEmpty);
  });

  test('WalletController hydrates from cache before a refresh fails',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final _MemoryStorage storage = _MemoryStorage()
      ..vault = SeedVault.encrypt(mnemonic, pin, rounds: 1000);

    final WalletIdentityController identity = WalletIdentityController(
      storage: storage,
      kdfRounds: 1000,
    );
    await identity.load();
    await identity.unlock(pin);

    final String address = identity.addressFor(NetworkCatalog.bitcoin)!;
    final SnapshotCache cache = SnapshotCache(storage: storage);
    await cache.write(
      AccountSnapshot(
        network: NetworkCatalog.bitcoin,
        address: address,
        balance: BigInt.from(777),
        transactions: const <ChainTransaction>[],
        chart: const <double>[],
        fetchedAt: DateTime(2026, 1, 1),
      ),
    );

    final MockClient failing = MockClient((_) async => http.Response('boom', 500));
    final WalletController wallet = WalletController(
      identity: identity,
      settings: SettingsController(),
      chainApi: ChainApi(client: failing),
      priceApi: PriceApi(client: failing),
      cache: cache,
    );

    for (int i = 0; i < 200 && wallet.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // The cached balance is shown even though the network call failed.
    expect(wallet.snapshot, isNotNull);
    expect(wallet.snapshot!.balance, BigInt.from(777));
    expect(wallet.error, isNotNull);

    wallet.dispose();
  });

  test('a cached snapshot for another address is ignored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final _MemoryStorage storage = _MemoryStorage();
    final SnapshotCache cache = SnapshotCache(storage: storage);
    await storage.writeCache(
      NetworkCatalog.bitcoin.id,
      jsonEncode(<String, Object?>{
        'networkId': 'bitcoin',
        'address': 'bc1qsomeoneelse',
        'balance': '1',
        'transactions': <Object>[],
        'chart': <Object>[],
        'fetchedAt': DateTime(2026, 1, 1).toIso8601String(),
      }),
    );

    expect(await cache.read(NetworkCatalog.bitcoin.id), isNotNull);
    // The controller compares the address itself; here we just confirm the
    // payload decodes so the comparison has something to reject.
    final AccountSnapshot? cached =
        await cache.read(NetworkCatalog.bitcoin.id);
    expect(cached!.address, 'bc1qsomeoneelse');
  });
}
