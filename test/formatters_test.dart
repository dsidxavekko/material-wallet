import 'package:crypto_wallet/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppFormat.fiat', () {
    test('formats USD with a dollar symbol and two decimals', () {
      expect(AppFormat.fiat(1234.5, AppCurrency.usd), r'$1,234.50');
    });

    test('converts the value into the target currency', () {
      expect(AppFormat.fiat(100, AppCurrency.uah), contains('₴'));
      expect(AppFormat.fiat(100, AppCurrency.uah), isNot(contains(r'$')));
    });
  });

  group('AppFormat.percent', () {
    test('prefixes positive values with a plus sign', () {
      expect(AppFormat.percent(2.5), '+2.50%');
    });

    test('rounds and keeps the sign for negative values', () {
      expect(AppFormat.percent(-1.239), '-1.24%');
    });

    test('shows no sign for zero', () {
      expect(AppFormat.percent(0), '0.00%');
    });
  });

  group('AppFormat.cryptoAmount', () {
    test('groups thousands and trims trailing zeros', () {
      expect(AppFormat.cryptoAmount(1234.5, 'BTC'), '1,234.5 BTC');
    });
  });

  group('AppFormat.shortAddress', () {
    test('keeps short strings untouched', () {
      expect(AppFormat.shortAddress('0x1234'), '0x1234');
    });

    test('abbreviates long addresses', () {
      expect(AppFormat.shortAddress('0x1234567890abcdef'), '0x1234…cdef');
    });
  });

  group('AppFormat.relativeTime', () {
    final DateTime now = DateTime(2026, 5, 20, 12);

    test('describes recent times', () {
      expect(
        AppFormat.relativeTime(now.subtract(const Duration(seconds: 10)),
            now: now),
        'Just now',
      );
      expect(
        AppFormat.relativeTime(now.subtract(const Duration(minutes: 5)),
            now: now),
        '5 min ago',
      );
      expect(
        AppFormat.relativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3 h ago',
      );
    });

    test('labels yesterday and older dates', () {
      expect(
        AppFormat.relativeTime(now.subtract(const Duration(days: 1)), now: now),
        'Yesterday',
      );
      expect(
        AppFormat.relativeTime(now.subtract(const Duration(days: 3)), now: now),
        '3 days ago',
      );
    });

    test('dayLabel returns Today for the current day', () {
      expect(AppFormat.dayLabel(now, now: now), 'Today');
    });
  });
}
