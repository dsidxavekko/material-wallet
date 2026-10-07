import 'package:crypto_wallet/data/wallet/address_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Address poisoning is a UI-level defence: the app cannot tell a lookalike
/// apart from the real address on-chain, only by comparing what the user can
/// actually see against addresses they have already dealt with.
/// A different address that copies the first and last [AddressGuard.headChars] /
/// [AddressGuard.tailChars] characters of [address] — exactly what an attacker
/// registers to impersonate it.
String lookalike(String address) {
  // Differs only in the middle: same `0x` prefix, same first and last hex
  // characters — the shape a poisoning address is registered with.
  final String body = address.toLowerCase();
  return body.replaceRange(20, 22, body[20] == 'a' ? 'b' : 'a');
}

void main() {
  const String real = '0x71C7656EC7ab88b098defB751B7401B5f6d8976F';

  group('AddressGuard.impersonates', () {
    test('flags an address that copies the visible ends of a known one', () {
      final String spoof = lookalike(real);
      expect(spoof, isNot(real));
      expect(AddressGuard.impersonates(spoof, <String>[real]), real);
    });

    test('is case-insensitive, like every EVM address comparison', () {
      expect(
        AddressGuard.impersonates(lookalike(real).toLowerCase(), <String>[real]),
        real,
      );
    });

    test('compares only what the user can see, not the 0x prefix', () {
      // Every EVM address starts with `0x`, so counting it would leave only two
      // hex characters of the real prefix and match far too much.
      const String spoof = '0x71C7AAAAf7ab88b098defB751B7401B5f6d8976F';
      expect(AddressGuard.impersonates(spoof, <String>[real]), real);
      expect(
        AddressGuard.impersonates('0x71c7AAAAf7ab88b098defb751b7401b5f6d8976f',
            <String>[real]),
        real,
      );
    });

    test('ignores surrounding whitespace', () {
      expect(
        AddressGuard.impersonates('  $real  ', <String>[real]),
        isNull,
        reason: 'the same address must never be reported as a lookalike',
      );
    });

    test('never flags the address itself', () {
      expect(AddressGuard.impersonates(real, <String>[real]), isNull);
      expect(AddressGuard.impersonates(real.toLowerCase(), <String>[real]),
          isNull);
    });

    test('does not flag an address with a different start or end', () {
      expect(
        AddressGuard.impersonates(
          '0xdeadbeefC7ab88b098defB751B7401B5f6d8976F',
          <String>[real],
        ),
        isNull,
      );
      expect(
        AddressGuard.impersonates(
          '0x71C7656EC7ab88b098defB751B7401B5f6d11111',
          <String>[real],
        ),
        isNull,
      );
    });

    test('skips short labels that would match everything', () {
      // History parsers use placeholders like this for an unknown counterparty.
      // Comparing them would flag every address against "Unknown".
      expect(AddressGuard.impersonates(real, <String>['Unknown']), isNull);
      expect(AddressGuard.impersonates(real, <String>['Coinbase']), isNull);
      expect(AddressGuard.impersonates('Unknown', <String>[real]), isNull);
    });

    test('reports which known address is being imitated', () {
      const String exchange = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';
      expect(
        AddressGuard.impersonates(
          lookalike(exchange),
          <String>[real, exchange],
        ),
        exchange,
      );
    });

    test('returns null when nothing matches', () {
      expect(AddressGuard.impersonates(real, const <String>[]), isNull);
    });
  });
}
