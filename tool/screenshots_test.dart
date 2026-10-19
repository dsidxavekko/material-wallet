import 'dart:io';

import 'package:crypto_wallet/app.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/networks/price_api.dart';
import 'package:crypto_wallet/data/wallet/seed_vault.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Generates the README screenshots into `../screenshots/`.
///
/// Run with:
/// `flutter test tool/screenshots_test.dart --update-goldens`
///
/// Everything on screen is fake: a deterministic seed phrase, an in-memory
/// storage and canned network responses. No device, no real funds.
void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';

  setUpAll(() async {
    // Golden text renders as solid blocks without the real font files. The
    // SDK ships the Material font set in its cache.
    final String root = Platform.environment['FLUTTER_ROOT']!;
    final String fonts = '$root/bin/cache/artifacts/material_fonts';
    Future<void> load(String family, List<String> files) async {
      final FontLoader loader = FontLoader(family);
      for (final String file in files) {
        final Uint8List bytes = File('$fonts/$file').readAsBytesSync();
        loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
      }
      await loader.load();
    }

    await load('Roboto', <String>[
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
    ]);
    await load('MaterialIcons', <String>['MaterialIcons-Regular.otf']);
  });

  late _FakeWalletStorage storage;

  /// Boots the app on a phone-sized virtual display and yields to the async
  /// vault read.
  Future<void> bootApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(780, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialWalletApp(
        storage: storage,
        chainApi: _FakeChainApi(),
        priceApi: _FakePriceApi(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  void seedEmpty() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = _FakeWalletStorage();
  }

  void seedEncryptedWallet() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'nova.wallet.createdAt': DateTime(2026, 1, 1).toIso8601String(),
    });
    storage = _FakeWalletStorage(
      vault: SeedVault.encrypt(mnemonic, pin, rounds: 1000),
    );
  }

  /// Unlocks an encrypted wallet so the tab shell is visible.
  Future<void> unlock(WidgetTester tester) async {
    seedEncryptedWallet();
    await bootApp(tester);

    await tester.enterText(find.byType(TextField), pin);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> snap(WidgetTester tester, String name) async {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../screenshots/$name.png'),
    );
  }

  testWidgets('onboarding', (tester) async {
    seedEmpty();
    await bootApp(tester);
    await snap(tester, '01-onboarding');
  });

  testWidgets('lock screen', (tester) async {
    seedEncryptedWallet();
    await bootApp(tester);
    await snap(tester, '02-lock');
  });

  testWidgets('wallet tab', (tester) async {
    await unlock(tester);
    await snap(tester, '03-wallet');
  });

  testWidgets('send screen', (tester) async {
    await unlock(tester);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await snap(tester, '04-send');
  });

  testWidgets('activity tab', (tester) async {
    await unlock(tester);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await snap(tester, '05-activity');
  });

  testWidgets('settings tab', (tester) async {
    await unlock(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await snap(tester, '06-settings');
  });
}

/// In-memory stand-in for the platform keystore that holds the encrypted seed.
class _FakeWalletStorage extends WalletStorage {
  _FakeWalletStorage({this.vault});

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

/// Canned chain data so screens show a realistic balance and history without
/// touching the network.
class _FakeChainApi extends ChainApi {
  static final DateTime _now = DateTime(2026, 10, 17, 12, 30);

  @override
  Future<BigInt> fetchBalance(NetworkConfig network, String address) async {
    return BigInt.from(1372500); // 0.01372500 BTC
  }

  @override
  Future<List<ChainTransaction>> fetchTransactions(
    NetworkConfig network,
    String address,
  ) async {
    return <ChainTransaction>[
      ChainTransaction(
        hash:
            'f3a1b2c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f80',
        timestamp: _now.subtract(const Duration(minutes: 26)),
        amount: BigInt.from(500000),
        fee: BigInt.from(2100),
        counterparty:
            'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
        isIncoming: true,
        confirmed: true,
      ),
      ChainTransaction(
        hash:
            '9c8b7a6f5e4d3c2b1a098f7e6d5c4b3a29180f7e6d5c4b3a29180f7e6d5c4b3a2',
        timestamp: _now.subtract(const Duration(days: 1, hours: 3)),
        amount: BigInt.from(-210000),
        fee: BigInt.from(1850),
        counterparty:
            'bc1q9d4ywgfnd8h43da5tpcxcn6ajv590cg6d3tg6axemvljvt2k76zs50tv4q',
        isIncoming: false,
        confirmed: true,
      ),
      ChainTransaction(
        hash:
            '77aa11bb22cc33dd44ee55ff6600778899aabbccddeeff001122334455667788',
        timestamp: _now.subtract(const Duration(minutes: 4)),
        amount: BigInt.from(-86000),
        fee: BigInt.from(1600),
        counterparty:
            'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
        isIncoming: false,
        confirmed: false,
      ),
    ];
  }

  @override
  Future<ActivityPage> fetchActivityPage(
    NetworkConfig network,
    String address, {
    ActivityCursor? after,
  }) async {
    return ActivityPage(native: await fetchTransactions(network, address));
  }

  @override
  Future<List<TokenBalance>> fetchTokenBalances(
    NetworkConfig network,
    String address,
  ) async {
    return const <TokenBalance>[];
  }

  @override
  Future<BigInt?> fetchFeeEstimate(NetworkConfig network) async {
    return BigInt.from(1875);
  }
}

/// Fixed spot price and chart series so the fiat value renders deterministically.
class _FakePriceApi extends PriceApi {
  @override
  Future<CoinPrice?> fetchPrice(String coinGeckoId) async {
    return const CoinPrice(usd: 61240.50, change24h: 2.41);
  }

  @override
  Future<List<double>> fetchChart(String coinGeckoId) async {
    return const <double>[
      59850, 59920, 60100, 60040, 60180, 60350, 60210, 60550, 60480, 60700,
      60620, 60810, 60750, 60920, 61050, 60980, 61100, 61030, 61150, 61240,
      61180, 61210, 61260, 61240,
    ];
  }
}
