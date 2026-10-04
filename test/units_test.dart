import 'package:crypto_wallet/core/utils/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Units.toDouble', () {
    test('converts satoshi to BTC', () {
      expect(Units.toDouble(BigInt.from(84200000), 8), closeTo(0.842, 1e-12));
    });

    test('converts wei to ETH', () {
      expect(
        Units.toDouble(BigInt.parse('1500000000000000000'), 18),
        closeTo(1.5, 1e-12),
      );
    });

    test('handles zero', () {
      expect(Units.toDouble(BigInt.zero, 8), 0);
    });
  });

  group('Units.format', () {
    test('groups thousands', () {
      expect(
        Units.format(BigInt.from(123456789000), 8),
        '1,234.56789',
      );
    });

    test('can disable grouping for text fields', () {
      expect(
        Units.format(BigInt.from(123456789000), 8, group: false),
        '1234.56789',
      );
    });

    test('trims trailing zeros but keeps the integer part', () {
      expect(Units.format(BigInt.from(100000000), 8), '1');
      expect(Units.format(BigInt.from(150000000), 8), '1.5');
      expect(Units.format(BigInt.zero, 8), '0');
    });

    test('supports negative values', () {
      expect(Units.format(BigInt.from(-150000000), 8), '-1.5');
    });

    test('appends the ticker', () {
      expect(
        Units.formatWithSymbol(BigInt.from(84200000), 8, 'BTC'),
        '0.842 BTC',
      );
    });
  });

  group('Units.parse', () {
    test('parses a decimal amount into raw units', () {
      expect(Units.parse('0.842', 8), BigInt.from(84200000));
      expect(Units.parse('1.5', 18), BigInt.parse('1500000000000000000'));
    });

    test('accepts a comma as the decimal separator', () {
      expect(Units.parse('0,5', 8), BigInt.from(50000000));
    });

    test('round-trips through format', () {
      final BigInt raw = BigInt.from(12345678900);
      final String text = Units.format(raw, 8, group: false);
      expect(Units.parse(text, 8), raw);
    });

    test('returns null for invalid input', () {
      expect(Units.parse('', 8), isNull);
      expect(Units.parse('abc', 8), isNull);
      expect(Units.parse('1.2.3', 8), isNull);
    });
  });
}
