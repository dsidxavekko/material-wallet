import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto_wallet/core/crypto/hashing.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const NetworkConfig network = NetworkCatalog.sepolia;
  const String raw = '0x02f8';

  http.Response rpcResult(Object? result) =>
      http.Response(jsonEncode(<String, Object?>{'result': result}), 200);

  http.Response rpcError(String message) => http.Response(
    jsonEncode(<String, Object?>{
      'error': <String, Object?>{'message': message},
    }),
    200,
  );

  test('BNB Chain can send, and says it has no history index (C6)', () {
    expect(NetworkCatalog.bnb.canSign, isTrue);
    expect(NetworkCatalog.bnb.chainId, 56);
    expect(NetworkCatalog.bnb.hasHistory, isFalse);
    expect(NetworkCatalog.ethereum.hasHistory, isTrue);
    expect(NetworkCatalog.base.hasHistory, isTrue);
  });

  test('every EVM network that can send lists more than one node', () {
    for (final NetworkConfig n in NetworkCatalog.all) {
      if (n.canSign && n.chainId != null) {
        expect(n.sendRpcUrls.length, greaterThan(1), reason: n.id);
        expect(n.sendRpcUrls.toSet().length, n.sendRpcUrls.length);
      }
    }
  });

  test(
    'the first node fails, the second accepts, and the hash is the same',
    () async {
      final List<String> hosts = <String>[];
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          hosts.add(request.url.host);
          if (request.url.toString() == network.sendRpcUrls.first) {
            throw http.ClientException('connection reset');
          }
          return rpcResult('0xabc');
        }),
      );

      final String hash = await api.sendRawTransaction(network, raw);

      expect(hash, '0xabc');
      expect(hosts, hasLength(2));
      expect(hosts.first, Uri.parse(network.sendRpcUrls.first).host);
      expect(hosts.last, Uri.parse(network.sendRpcUrls[1]).host);
    },
  );

  test('a 5xx moves on to the next node', () async {
    int calls = 0;
    final ChainApi api = ChainApi(
      client: MockClient((http.Request request) async {
        calls++;
        return calls == 1
            ? http.Response('bad gateway', 502)
            : rpcResult('0x1');
      }),
    );

    expect(await api.getTransactionCount(network, '0xabc'), 1);
    expect(calls, 2);
  });

  test('a JSON-RPC error is final: the next node is never asked', () async {
    int calls = 0;
    final ChainApi api = ChainApi(
      client: MockClient((http.Request request) async {
        calls++;
        return rpcError('insufficient funds for gas * price + value');
      }),
    );

    await expectLater(
      api.sendRawTransaction(network, raw),
      throwsA(
        isA<ChainApiException>().having(
          (ChainApiException e) => e.message,
          'message',
          contains('insufficient funds'),
        ),
      ),
    );
    expect(calls, 1);
  });

  test('"already known" counts as success with the keccak of the bytes', () async {
    final ChainApi api = ChainApi(
      client: MockClient((_) async => rpcError('already known')),
    );

    final String hash = await api.sendRawTransaction(network, raw);

    expect(
      hash,
      '0x${hex.encode(Hashing.keccak256(Uint8List.fromList(<int>[0x02, 0xf8])))}',
    );
  });

  test('every node unreachable surfaces the last transport error', () async {
    final ChainApi api = ChainApi(
      client: MockClient((_) async => throw http.ClientException('down')),
    );

    await expectLater(
      api.sendRawTransaction(network, raw),
      throwsA(isA<ChainApiException>()),
    );
  });
}
