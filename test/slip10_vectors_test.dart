import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto_wallet/core/crypto/slip10.dart';
import 'package:flutter_test/flutter_test.dart';

/// The official SLIP-0010 test vectors for ed25519
/// (https://github.com/satoshilabs/slips/blob/master/slip-0010.md).
///
/// They pin the derivation function itself, for any path — unlike the address
/// tests, which pin one phrase on the Solana and Aptos paths.
void main() {
  String derive(String seedHex, List<int> path) => hex.encode(
    Slip10.deriveEd25519Seed(Uint8List.fromList(hex.decode(seedHex)), path),
  );

  group('SLIP-0010 ed25519 — vector 1', () {
    const String seed = '000102030405060708090a0b0c0d0e0f';

    final Map<String, (List<int>, String)> cases =
        <String, (List<int>, String)>{
          "m": (
            <int>[],
            '2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7',
          ),
          "m/0'": (
            <int>[0],
            '68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3',
          ),
          "m/0'/1'": (
            <int>[0, 1],
            'b1d0bad404bf35da785a64ca1ac54b2617211d2777696fbffaf208f746ae84f2',
          ),
          "m/0'/1'/2'": (
            <int>[0, 1, 2],
            '92a5b23c0b8a99e37d07df3fb9966917f5d06e02ddbd909c7e184371463e9fc9',
          ),
          "m/0'/1'/2'/2'": (
            <int>[0, 1, 2, 2],
            '30d1dc7e5fc04c31219ab25a27ae00b50f6fd66622f6e9c913253d6511d1e662',
          ),
          "m/0'/1'/2'/2'/1000000000'": (
            <int>[0, 1, 2, 2, 1000000000],
            '8f94d394a8e8fd6b1bc2f3f49f5c47e385281d5c17e65324b0f62483e37e8793',
          ),
        };

    cases.forEach((String path, (List<int>, String) c) {
      test(path, () => expect(derive(seed, c.$1), c.$2));
    });
  });

  group('SLIP-0010 ed25519 — vector 2', () {
    const String seed =
        'fffcf9f6f3f0edeae7e4e1dedbd8d5d2cfccc9c6c3c0bdbab7b4b1aeaba8a5a2'
        '9f9c999693908d8a8784817e7b7875726f6c696663605d5a5754514e4b484542';

    test('m', () {
      expect(
        derive(seed, <int>[]),
        '171cb88b1b3c1db25add599712e36245d75bc65a1a5c9e18d76f9f2b1eab4012',
      );
    });

    test("m/0'", () {
      expect(
        derive(seed, <int>[0]),
        '1559eb2bbec5790b0c65d8693e4d0875b1747f4970ae8b650486ed7470845635',
      );
    });
  });
}
