import 'package:crypto_wallet/core/utils/formatters.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/features/home/widgets/account_balance_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AccountSnapshot snapshot(NetworkConfig network, {CoinPrice? price}) =>
      AccountSnapshot(
        network: network,
        address: 'bc1qexample',
        balance: BigInt.from(150000000),
        transactions: const <ChainTransaction>[],
        chart: const <double>[],
        fetchedAt: DateTime(2026, 1, 1),
        price: price,
      );

  Widget host(AccountSnapshot data, {VoidCallback? onRetry}) => MaterialApp(
        home: Scaffold(
          body: AccountBalanceCard(
            snapshot: data,
            currency: AppCurrency.usd,
            hidden: false,
            onToggleVisibility: () {},
            onCurrencyTap: () {},
            onRetryPrice: onRetry ?? () {},
          ),
        ),
      );

  testWidgets('mainnet without a price is not labelled as a testnet',
      (tester) async {
    await tester.pumpWidget(host(snapshot(NetworkCatalog.bitcoin)));

    expect(find.text('Price temporarily unavailable'), findsOneWidget);
    expect(find.text('Testnet — no market price'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('a real testnet keeps the testnet label and offers no retry',
      (tester) async {
    await tester.pumpWidget(host(snapshot(NetworkCatalog.bitcoinTestnet)));

    expect(find.text('Testnet — no market price'), findsOneWidget);
    expect(find.text('Price temporarily unavailable'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
  });

  testWidgets('tapping Retry on a mainnet invokes the callback',
      (tester) async {
    int retries = 0;
    await tester.pumpWidget(
      host(snapshot(NetworkCatalog.bitcoin), onRetry: () => retries++),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();

    expect(retries, 1);
  });

  testWidgets('a mainnet with a price shows the fiat row', (tester) async {
    await tester.pumpWidget(
      host(
        snapshot(
          NetworkCatalog.bitcoin,
          price: const CoinPrice(usd: 60000, change24h: 1.5),
        ),
      ),
    );

    expect(find.text('Price temporarily unavailable'), findsNothing);
    expect(find.text('Testnet — no market price'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    expect(find.textContaining(r'1 BTC ='), findsOneWidget);
  });
}
