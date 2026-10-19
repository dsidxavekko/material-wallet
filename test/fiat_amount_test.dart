import 'package:crypto_wallet/core/utils/fiat_amount.dart';
import 'package:crypto_wallet/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(AppCurrency.resetUsdRates);

  test('USD amount to coins at a given price, rounded down', () {
    // $100 at $60 000/BTC = 0.00166666… BTC → 166 666 sat, never 166 667.
    expect(
      FiatAmount.toRaw(
        fiatText: '100',
        currency: AppCurrency.usd,
        unitPriceUsd: 60000,
        decimals: 8,
      ),
      BigInt.from(166666),
    );
  });

  test('converts through the display currency rate', () {
    AppCurrency.updateUsdRates(uah: 40);
    // 4000 UAH = $100 → 0.05 ETH at $2000.
    expect(
      FiatAmount.toRaw(
        fiatText: '4000',
        currency: AppCurrency.uah,
        unitPriceUsd: 2000,
        decimals: 18,
      ),
      BigInt.parse('50000000000000000'),
    );
  });

  test('accepts a comma decimal and rejects junk, zero and bad prices', () {
    BigInt? raw(String text, {double price = 100}) => FiatAmount.toRaw(
          fiatText: text,
          currency: AppCurrency.usd,
          unitPriceUsd: price,
          decimals: 6,
        );

    expect(raw('1,5'), BigInt.from(15000));
    expect(raw('abc'), isNull);
    expect(raw(''), isNull);
    expect(raw('0'), isNull);
    expect(raw('-5'), isNull);
    expect(raw('5', price: 0), isNull);
    expect(raw('5', price: double.nan), isNull);
  });

  test('a token with fewer decimals than the precision is not over-scaled', () {
    // $1 of a $1 token with 6 decimals = exactly 1 000 000 units.
    expect(
      FiatAmount.toRaw(
        fiatText: '1',
        currency: AppCurrency.usd,
        unitPriceUsd: 1,
        decimals: 6,
      ),
      BigInt.from(1000000),
    );
  });

  test('the fiat text of a coin amount is floored to cents', () {
    expect(
      FiatAmount.inputText(
        coins: 0.0016666666,
        currency: AppCurrency.usd,
        unitPriceUsd: 60000,
      ),
      '99.99',
    );
  });

  test('round trip never exceeds the original coin amount', () {
    const double coins = 0.123456;
    final String text = FiatAmount.inputText(
      coins: coins,
      currency: AppCurrency.usd,
      unitPriceUsd: 3217.55,
    );
    final BigInt raw = FiatAmount.toRaw(
      fiatText: text,
      currency: AppCurrency.usd,
      unitPriceUsd: 3217.55,
      decimals: 18,
    )!;
    expect(raw <= BigInt.from((coins * 1e18).round()), isTrue);
  });
}
