import 'package:intl/intl.dart';

/// Fiat currencies the wallet can display.
///
/// [usdRate] is how much one US dollar is worth in that currency. Values are
/// static demo values — a real wallet would fetch live FX rates.
enum AppCurrency {
  usd('USD', r'$', 1),
  eur('EUR', '€', 0.92),
  uah('UAH', '₴', 41.5);

  const AppCurrency(this.code, this.symbol, this.usdRate);

  final String code;
  final String symbol;
  final double usdRate;

  String get label => '$code ($symbol)';
}

/// Centralised number/date formatting helpers so screens never build strings
/// by hand.
class AppFormat {
  const AppFormat._();

  /// Formats a USD value in the user's selected [currency].
  static String fiat(
    double usdValue,
    AppCurrency currency, {
    int decimalDigits = 2,
  }) {
    return NumberFormat.currency(
      symbol: currency.symbol,
      decimalDigits: decimalDigits,
    ).format(usdValue * currency.usdRate);
  }

  /// Signed percentage such as `+2.41%` / `-0.87%`.
  static String percent(double value, {int decimals = 2}) {
    final String sign = value > 0 ? '+' : (value < 0 ? '-' : '');
    return '$sign${value.abs().toStringAsFixed(decimals)}%';
  }

  /// `0x71C7…9f2A` style shortening for long addresses / hashes.
  static String shortAddress(String address, {int head = 6, int tail = 4}) {
    if (address.length <= head + tail + 1) {
      return address;
    }
    return '${address.substring(0, head)}…${address.substring(address.length - tail)}';
  }

  /// Human friendly relative time, e.g. `Just now`, `12 min ago`, `Yesterday`.
  static String relativeTime(DateTime time, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final Duration diff = reference.difference(time);
    if (diff.inSeconds < 60) {
      return 'Just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} h ago';
    }
    if (diff.inDays == 1) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    }
    return DateFormat.yMMMd().format(time);
  }

  /// Short date used as a group header inside the activity list.
  static String dayLabel(DateTime time, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final DateTime day = DateTime(time.year, time.month, time.day);
    final DateTime today = DateTime(reference.year, reference.month, reference.day);
    final int delta = today.difference(day).inDays;
    if (delta == 0) {
      return 'Today';
    }
    if (delta == 1) {
      return 'Yesterday';
    }
    return DateFormat.yMMMMd().format(time);
  }
}
