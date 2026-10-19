import 'formatters.dart';

/// Converts between a typed fiat figure and the coin amount that is signed.
///
/// The coin amount is the only thing ever signed: a fiat entry is turned into
/// raw units here, **rounded down**, so what leaves the account never exceeds
/// what the user typed, and the review sheet shows the exact coin figure.
class FiatAmount {
  const FiatAmount._();

  /// Coin precision a fiat entry resolves to. Eight places is a satoshi, and a
  /// hundred-millionth of an ether is far below any fiat cent.
  static const int _precision = 8;

  /// Raw units worth [fiatText] in [currency] at [unitPriceUsd] per whole coin,
  /// or `null` when the text is not a positive number or the price is unusable.
  static BigInt? toRaw({
    required String fiatText,
    required AppCurrency currency,
    required double unitPriceUsd,
    required int decimals,
  }) {
    final double? fiat = double.tryParse(fiatText.trim().replaceAll(',', '.'));
    if (fiat == null ||
        !fiat.isFinite ||
        fiat <= 0 ||
        !unitPriceUsd.isFinite ||
        unitPriceUsd <= 0) {
      return null;
    }
    final double coins = fiat / currency.usdRate / unitPriceUsd;
    final int places = decimals < _precision ? decimals : _precision;
    final BigInt scaled = BigInt.from((coins * _pow10(places)).floor());
    if (scaled <= BigInt.zero) {
      return null;
    }
    return scaled * BigInt.from(10).pow(decimals - places);
  }

  /// The fiat figure for [coins] (whole coins), floored to cents and written
  /// without grouping so it can go back into a text field.
  static String inputText({
    required double coins,
    required AppCurrency currency,
    required double unitPriceUsd,
  }) {
    final double fiat = coins * unitPriceUsd * currency.usdRate;
    return ((fiat * 100).floor() / 100).toStringAsFixed(2);
  }

  static double _pow10(int n) {
    double value = 1;
    for (int i = 0; i < n; i++) {
      value *= 10;
    }
    return value;
  }
}
