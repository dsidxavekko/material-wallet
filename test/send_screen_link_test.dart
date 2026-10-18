import 'dart:convert';

import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/price_api.dart';
import 'package:crypto_wallet/data/wallet/seed_vault.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/features/send/send_screen.dart';
import 'package:crypto_wallet/state/contacts_controller.dart';
import 'package:crypto_wallet/state/settings_controller.dart';
import 'package:crypto_wallet/state/wallet_controller.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget tests for the scan / paste path of the send screen: a payment link
/// must prefill the recipient and the amount (A4).
void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';

  http.Response json(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );

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
        return http.Response('{}', 404);
      });

  testWidgets('pasting a bitcoin payment link fills the amount (A4)',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'nova.wallet.createdAt': DateTime(2026, 1, 1).toIso8601String(),
    });
    final WalletStorage storage = _FakeWalletStorage(
      SeedVault.encrypt(mnemonic, pin, rounds: 1000),
    );
    final WalletIdentityController identity = WalletIdentityController(
      storage: storage,
    );
    // runAsync: unlock runs PBKDF2 through `pbkdf2Chunked`, which yields to
    // the event loop (`Future.delayed`) every 2000 rounds — those timers only
    // fire inside runAsync's real zone, never in fake-async pumps.
    await tester.runAsync(() async {
      await identity.load();
      await identity.unlock(pin);
    });

    final SettingsController settings = SettingsController();
    final WalletController wallet = WalletController(
      identity: identity,
      settings: settings,
      chainApi: ChainApi(client: mockClient()),
      priceApi: PriceApi(client: mockClient()),
    );

    // The clipboard holds a BIP-21 link so the paste button drives the same
    // code path as a scanned QR code.
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (message) async {
      if (message.method == 'Clipboard.getData') {
        // The channel encodes the return value itself; return plain JSON.
        return <String, String>{
          'text': 'bitcoin:bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu'
              '?amount=0.5',
        };
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(
      MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<ContactsController>(
            create: (_) => ContactsController(),
          ),
          ChangeNotifierProvider<WalletIdentityController>.value(
            value: identity,
          ),
          ChangeNotifierProvider<WalletController>.value(value: wallet),
        ],
        child: const MaterialApp(home: SendScreen()),
      ),
    );
    // Let the balance load so the screen renders the send form.
    for (int i = 0; i < 50 && wallet.loading; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.content_paste_rounded));
    // Bound the pumps: pumpAndSettle would hang on any indeterminate spinner
    // while the network fee quote keeps loading.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu'),
      findsOneWidget,
    );
    final TextField amount = tester.widget<TextField>(
      find.widgetWithText(TextField, '0.5'),
    );
    expect(amount.controller!.text, '0.5');

    wallet.dispose();
  });
}

class _FakeWalletStorage extends WalletStorage {
  _FakeWalletStorage(this.vault);

  final String? vault;

  @override
  Future<String?> readVault() async => vault;

  @override
  Future<void> writeVault(String payload, DateTime createdAt) async {}

  @override
  Future<void> clear() async {}
}
