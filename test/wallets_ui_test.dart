import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/networks/price_api.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/data/wallet/watch_address.dart';
import 'package:crypto_wallet/features/send/send_screen.dart';
import 'package:crypto_wallet/features/wallets/watch_wallet_screen.dart';
import 'package:crypto_wallet/features/wallets/wallets_screen.dart';
import 'package:crypto_wallet/state/contacts_controller.dart';
import 'package:crypto_wallet/state/settings_controller.dart';
import 'package:crypto_wallet/state/send_controller.dart';
import 'package:crypto_wallet/state/wallet_controller.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  const String evmWatch = '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045';

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Widget host(
    WalletIdentityController identity,
    SettingsController settings,
    WalletController? wallet,
    Widget home,
  ) =>
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<ContactsController>(
            create: (_) => ContactsController(),
          ),
          ChangeNotifierProvider<WalletIdentityController>.value(
            value: identity,
          ),
          if (wallet != null)
            ChangeNotifierProvider<WalletController>.value(value: wallet),
        ],
        child: MaterialApp(home: home),
      );

  testWidgets('pasting an address and pressing Follow opens a watch-only wallet',
      (tester) async {
    final WalletIdentityController identity =
        WalletIdentityController(storage: _FakeWalletStorage(), kdfRounds: 1000);
    await tester.runAsync(identity.load);

    await tester.pumpWidget(
      host(identity, SettingsController(), null, const WatchWalletScreen()),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Name (optional)'), 'Cold');
    await tester.enterText(find.widgetWithText(TextField, 'Address'), evmWatch);
    await tester.tap(find.text('Add address'));
    await tester.pump();
    expect(find.text('EVM networks'), findsOneWidget);

    await tester.tap(find.text('Follow'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(identity.activeWallet!.name, 'Cold');
    expect(identity.addressFor(NetworkCatalog.ethereum), evmWatch);
  });

  testWidgets('an address typed but not added still counts when Follow is pressed',
      (tester) async {
    final WalletIdentityController identity =
        WalletIdentityController(storage: _FakeWalletStorage(), kdfRounds: 1000);
    await tester.runAsync(identity.load);
    await tester.pumpWidget(
      host(identity, SettingsController(), null, const WatchWalletScreen()),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Address'), evmWatch);
    await tester.tap(find.text('Follow'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(identity.isWatchOnly, isTrue);
  });

  testWidgets('a bad address shows why and follows nothing', (tester) async {
    final WalletIdentityController identity =
        WalletIdentityController(storage: _FakeWalletStorage(), kdfRounds: 1000);
    await tester.runAsync(identity.load);
    await tester.pumpWidget(
      host(identity, SettingsController(), null, const WatchWalletScreen()),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Address'), 'hello');
    await tester.tap(find.text('Follow'));
    await tester.pump();

    expect(find.text('Not a Bitcoin, EVM, Solana or Aptos address'), findsOneWidget);
    expect(identity.status, WalletStatus.empty);
  });

  test('a payment link pasted as an address yields the bare address', () {
    expect(
      WatchAddresses.extract(
        'bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=1',
      ),
      'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
    );
    expect(WatchAddresses.extract('ethereum:$evmWatch@1'), evmWatch);
    expect(WatchAddresses.extract('  $evmWatch '), evmWatch);
  });

  testWidgets('a watch-only wallet gets an explanation instead of the send form',
      (tester) async {
    final WalletIdentityController identity =
        WalletIdentityController(storage: _FakeWalletStorage(), kdfRounds: 1000);
    await tester.runAsync(() async {
      await identity.load();
      await identity.addWatchWallet(
        name: 'Cold',
        addresses: <String, String>{'evm': evmWatch},
      );
    });
    final SettingsController settings = SettingsController();
    final MockClient client = MockClient((_) async => http.Response('{}', 404));
    final WalletController wallet = WalletController(
      identity: identity,
      settings: settings,
      chainApi: ChainApi(client: client),
      priceApi: PriceApi(client: client),
    );

    await tester.pumpWidget(host(identity, settings, wallet, const SendScreen()));
    await tester.pump();

    expect(find.text('Watch-only wallet'), findsOneWidget);
    expect(find.textContaining('cannot send'), findsOneWidget);
    wallet.dispose();
  });

  testWidgets('the wallets screen lists every wallet and switches on tap',
      (tester) async {
    final _FakeWalletStorage storage = _FakeWalletStorage();
    final WalletIdentityController identity =
        WalletIdentityController(storage: storage, kdfRounds: 1000);
    await tester.runAsync(() async {
      await identity.load();
      await identity.createWallet(mnemonic: mnemonic, pin: pin);
      await identity.addWatchWallet(
        name: 'Cold',
        addresses: <String, String>{'evm': evmWatch},
      );
    });

    await tester.pumpWidget(
      host(identity, SettingsController(), null, const WalletsScreen()),
    );

    expect(find.text('Wallet 1'), findsOneWidget);
    expect(find.text('Cold'), findsOneWidget);
    expect(find.text('Watch-only · EVM networks'), findsOneWidget);
    expect(identity.activeWallet!.name, 'Cold');

    await tester.tap(find.text('Wallet 1'));
    // The tap starts the seed derivation inside the fake-async zone, so its
    // yields are fired by advancing the fake clock.
    for (int i = 0; i < 50 && identity.activeWalletId != 'main'; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(identity.activeWalletId, 'main');
    expect(identity.canSign, isTrue);
  });

  test('the send controller refuses to sign for a watch-only wallet', () async {
    final WalletIdentityController identity =
        WalletIdentityController(storage: _FakeWalletStorage(), kdfRounds: 1000);
    await identity.load();
    await identity.addWatchWallet(
      name: 'Cold',
      addresses: <String, String>{'evm': evmWatch},
    );
    final MockClient client = MockClient((_) async => http.Response('{}', 404));
    final SendController controller = SendController(
      identity: identity,
      network: NetworkCatalog.ethereum,
      address: evmWatch,
      chainApi: ChainApi(client: client),
    );
    final bool sent = await controller.send(
      to: evmWatch,
      value: BigInt.one,
      maxPriorityFeePerGas: BigInt.one,
      maxFeePerGas: BigInt.two,
      gasLimit: BigInt.from(21000),
    );
    expect(sent, isFalse);
    expect(controller.error, contains('watch-only'));
    expect(controller.txHash, isNull);
  });
}
