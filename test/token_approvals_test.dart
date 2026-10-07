import 'dart:convert';

import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An approval lets a contract move tokens out of the account at will. The only
/// remedy is overwriting it with zero, so reading them correctly is what makes
/// the revoke button trustworthy.
void main() {
  http.Response json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: const <String, String>{'content-type': 'application/json'},
      );

  const String unlimited =
      '115792089237316195423570985008687907853269984665640564039457584007913129639935';

  ChainApi api(http.Response Function() respond) =>
      ChainApi(client: MockClient((_) async => respond()));

  ChainApi approvalsApi(List<Object> items) => api(
        () => json(<String, Object>{'items': items}),
      );

  Map<String, Object> approval({
    required String symbol,
    required String spender,
    required String value,
    String decimals = '6',
  }) =>
      <String, Object>{
        'token': <String, Object>{
          'symbol': symbol,
          'decimals': decimals,
          'address_hash': '0xtoken',
        },
        'value': value,
        'spender': <String, Object>{'hash': spender},
      };

  test('parses approvals and flags an unlimited allowance', () async {
    final ChainApi client = approvalsApi(<Object>[
      approval(symbol: 'USDT', spender: '0xaaa', value: '1000000'),
      approval(
        symbol: 'WETH',
        spender: '0xbbb',
        value: unlimited,
        decimals: '18',
      ),
    ]);

    final List<TokenApproval> result =
        await client.fetchTokenApprovals(NetworkCatalog.ethereum, '0xabc');

    expect(result, hasLength(2));
    // The unlimited allowance sorts first: it is the one that can drain
    // everything, so it must not hide below a row of dust.
    expect(result.first.symbol, 'WETH');
    expect(result.first.isUnlimited, isTrue);
    expect(result.first.amountLabel, 'Unlimited');
    expect(result.last.isUnlimited, isFalse);
    expect(result.last.amountLabel, '1');
    expect(result.last.spender, '0xaaa');
  });

  test('drops a zero allowance, which is already revoked', () async {
    final ChainApi client = approvalsApi(<Object>[
      approval(symbol: 'USDT', spender: '0xaaa', value: '0'),
    ]);

    expect(
      await client.fetchTokenApprovals(NetworkCatalog.ethereum, '0xabc'),
      isEmpty,
    );
  });

  test('reads decimals given as a number or a string', () async {
    final ChainApi client = approvalsApi(<Object>[
      <String, Object>{
        'token': <String, Object>{
          'symbol': 'USDT',
          'decimals': 18,
          'address_hash': '0xtoken',
        },
        'value': '1000000000000000000',
        'spender': <String, Object>{'hash': '0xaaa'},
      },
    ]);

    final List<TokenApproval> result =
        await client.fetchTokenApprovals(NetworkCatalog.ethereum, '0xabc');
    expect(result.single.decimals, 18);
  });

  test('returns an empty list on networks without a token index', () async {
    final ChainApi client = api(() {
      fail('the network should not be queried for approvals');
    });

    expect(await client.fetchTokenApprovals(NetworkCatalog.bitcoin, 'bc1q'),
        isEmpty);
    expect(await client.fetchTokenApprovals(NetworkCatalog.solana, 'x'), isEmpty);
    // BNB is JSON-RPC only, so there is no Blockscout token index.
    expect(await client.fetchTokenApprovals(NetworkCatalog.bnb, '0xabc'),
        isEmpty);
  });

  test('a failing approvals request degrades to an empty list', () async {
    final ChainApi client = api(() => http.Response('boom', 500));
    expect(
      await client.fetchTokenApprovals(NetworkCatalog.ethereum, '0xabc'),
      isEmpty,
    );
  });

  group('fetchTokenBalance', () {
    // A real-shaped address: the calldata encoder rejects anything else, which
    // is itself the check that a malformed owner never reaches a node.
    const String ownerAddress = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';
    const String tokenContract =
        '0x6B175474E89094C44Da98b954EedeAC495271d0F';

    /// A node answering `balanceOf`. The request it received is recorded in
    /// [seen] rather than asserted inside the handler: a failed expectation
    /// there is swallowed by the client's own error handling and surfaces as
    /// "could not reach the API", hiding the real cause.
    ChainApi node({bool shortAnswer = false, List<String>? seen}) =>
        ChainApi(
          client: MockClient((http.Request request) async {
            final Map<String, Object?> body =
                jsonDecode(request.body) as Map<String, Object?>;
            seen?.add('${body['method']} ${jsonEncode(body['params'])}');
            return json(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 1,
              'result': shortAnswer ? '0x1' : _word(BigInt.from(5) * pow10(18)),
            });
          }),
        );

    test('reads the 32-byte word eth_call returns', () async {
      expect(
        await node().fetchTokenBalance(
          network: NetworkCatalog.ethereum,
          token: tokenContract,
          owner: ownerAddress,
        ),
        BigInt.from(5) * pow10(18),
      );
    });

    test('asks the token contract for balanceOf of the owner', () async {
      final List<String> seen = <String>[];
      await node(seen: seen).fetchTokenBalance(
        network: NetworkCatalog.ethereum,
        token: tokenContract,
        owner: ownerAddress,
      );

      expect(seen.single, startsWith('eth_call '));
      expect(seen.single, contains(tokenContract));
      expect(seen.single, contains('0x70a08231'), reason: 'balanceOf selector');
    });

    test('throws rather than reporting a balance it could not read', () async {
      // A malformed answer must not be read as "no tokens": that would let a
      // transfer sign against a holding the node never confirmed.
      expect(
        () => node(shortAnswer: true).fetchTokenBalance(
          network: NetworkCatalog.ethereum,
          token: tokenContract,
          owner: ownerAddress,
        ),
        throwsA(isA<ChainApiException>()),
      );
    });
  });
}

/// `0x`-prefixed, zero-padded 32-byte big-endian word — how a node encodes an
/// `uint256` return value.
String _word(BigInt value) => '0x${value.toRadixString(16).padLeft(64, '0')}';

/// 10^18, the scale of an 18-decimal token holding.
BigInt pow10(int exponent) {
  BigInt result = BigInt.one;
  for (int i = 0; i < exponent; i++) {
    result *= BigInt.from(10);
  }
  return result;
}
