import 'package:convert/convert.dart';
import 'package:crypto_wallet/core/crypto/ens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('namehash (EIP-137 vectors)', () {
    test('the empty name is 32 zero bytes', () {
      expect(hex.encode(Ens.namehash('')), '00' * 32);
    });

    test('eth', () {
      expect(
        hex.encode(Ens.namehash('eth')),
        '93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae',
      );
    });

    test('foo.eth', () {
      expect(
        hex.encode(Ens.namehash('foo.eth')),
        'de9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f',
      );
    });
  });

  group('normalize', () {
    test('lowercases and accepts plain names', () {
      expect(Ens.normalize(' Vitalik.ETH '), 'vitalik.eth');
      expect(Ens.normalize('my-name_1.sub.eth'), 'my-name_1.sub.eth');
    });

    test('refuses what it cannot normalise exactly', () {
      expect(Ens.normalize('vitаlik.eth'), isNull); // Cyrillic "а"
      expect(Ens.normalize('emoji😀.eth'), isNull);
      expect(Ens.normalize('a..eth'), isNull);
      expect(Ens.normalize('-bad.eth'), isNull);
      expect(Ens.normalize(''), isNull);
    });

    test('looksLikeName only claims .eth names', () {
      expect(Ens.looksLikeName('alice.eth'), isTrue);
      expect(Ens.looksLikeName('0x9858EfFD232B4033E47d90003D41EC34EcaEda94'),
          isFalse);
      expect(Ens.looksLikeName('alice.com'), isFalse);
    });
  });

  group('dnsEncode', () {
    test('length-prefixes labels and terminates with zero', () {
      expect(hex.encode(Ens.dnsEncode('foo.eth')), '03666f6f0365746800');
    });
  });

  group('resolveCallData', () {
    test('has the resolve(bytes,bytes) selector and a consistent layout', () {
      final String data = Ens.resolveCallData('foo.eth');
      expect(data, startsWith('0x9061b923'));

      final String body = data.substring(10);
      // Head: offset of the name, offset of the inner call.
      expect(body.substring(0, 64), '${'0' * 62}40');
      expect(body.substring(64, 128), '${'0' * 62}80');
      // Name tail: length 9, then the DNS-encoded name padded to 32 bytes.
      expect(body.substring(128, 192), '${'0' * 62}09');
      expect(
        body.substring(192, 256),
        '03666f6f03657468' '00${'0' * 46}',
      );
      // Inner call: 36 bytes = addr(bytes32) selector + namehash.
      expect(body.substring(256, 320), '${'0' * 62}24');
      expect(
        body.substring(320, 320 + 8 + 64),
        '3b3b57de${hex.encode(Ens.namehash('foo.eth'))}',
      );
    });
  });

  group('decodeResolveResult', () {
    String answer(String addressHex) =>
        '0x'
        '${'0' * 62}40' // offset of `result`
        '${'0' * 24}${'ab' * 20}' // resolver address
        '${'0' * 62}20' // result length 32
        '${'0' * 24}$addressHex';

    test('reads the address out of abi.encode(address)', () {
      expect(
        Ens.decodeResolveResult(answer('11' * 20)),
        '0x${'11' * 20}',
      );
    });

    test('the zero address and empty answers mean "not found"', () {
      expect(Ens.decodeResolveResult(answer('00' * 20)), isNull);
      expect(Ens.decodeResolveResult('0x'), isNull);
      expect(Ens.decodeResolveResult('0x${'0' * 128}'), isNull);
    });
  });
}
