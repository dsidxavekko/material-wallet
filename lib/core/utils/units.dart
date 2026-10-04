import 'dart:math' as math;

/// Helpers for the integer amounts returned by blockchain APIs.
///
/// On-chain values are always integers in the smallest unit (wei, satoshi),
/// so they are handled as [BigInt] and only converted for display.
class Units {
  const Units._();

  static final BigInt _ten = BigInt.from(10);

  /// Converts a raw integer amount into a `double` in whole coins.
  static double toDouble(BigInt raw, int decimals) {
    if (raw == BigInt.zero) {
      return 0;
    }
    return raw.toDouble() / math.pow(10, decimals);
  }

  /// Formats a raw amount as a human readable string.
  ///
  /// Set [group] to `false` for strings that will be fed back into a text
  /// field, so no thousands separators are inserted.
  static String format(
    BigInt raw,
    int decimals, {
    int maxDecimals = 8,
    bool group = true,
  }) {
    final bool negative = raw.isNegative;
    final BigInt absolute = raw.abs();
    final BigInt divisor = _ten.pow(decimals);
    final BigInt whole = absolute ~/ divisor;
    final BigInt remainder = absolute % divisor;

    String fraction = remainder.toString().padLeft(decimals, '0');
    if (fraction.length > maxDecimals) {
      fraction = fraction.substring(0, maxDecimals);
    }
    fraction = fraction.replaceAll(RegExp(r'0+$'), '');

    final String wholeText =
        group ? groupDigits(whole.toString()) : whole.toString();
    final String text =
        fraction.isEmpty ? wholeText : '$wholeText.$fraction';
    return negative ? '-$text' : text;
  }

  /// Formats raw units together with a ticker, e.g. `0.052 BTC`.
  static String formatWithSymbol(
    BigInt raw,
    int decimals,
    String symbol, {
    int maxDecimals = 8,
  }) =>
      '${format(raw, decimals, maxDecimals: maxDecimals)} $symbol';

  /// Inserts thousands separators into a plain integer string.
  static String groupDigits(String digits) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// Parses a user-typed decimal amount into raw integer units.
  static BigInt? parse(String input, int decimals) {
    final String cleaned = input.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) {
      return null;
    }
    final RegExp valid = RegExp(r'^\d*\.?\d*$');
    if (!valid.hasMatch(cleaned)) {
      return null;
    }
    final List<String> parts = cleaned.split('.');
    final String whole = parts[0].isEmpty ? '0' : parts[0];
    final String fraction =
        parts.length > 1 ? parts[1].padRight(decimals, '0').substring(0, decimals) : ''.padRight(decimals, '0');
    try {
      return BigInt.parse('$whole$fraction');
    } catch (_) {
      return null;
    }
  }
}
