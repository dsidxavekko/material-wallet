import 'dart:convert';

import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const String address = '0x1985ca180559f52d8d37809fa63a3dc89870507ff5e9340aa8360d7322bb23b0';
  const String usdcFa =
      '0xbae207659db88bea0cbead6da0ed00aac12edcdda169e591cd41c94180b46f3b';

  http.Response indexer(List<Map<String, Object?>> rows) => http.Response(
        jsonEncode(<String, Object?>{
          'data': <String, Object?>{'current_fungible_asset_balances': rows},
        }),
        200,
      );

  Map<String, Object?> row(String type, Object amount, String symbol, int decimals) =>
      <String, Object?>{
        'asset_type': type,
        'amount': amount,
        'metadata': <String, Object?>{
          'name': symbol,
          'symbol': symbol,
          'decimals': decimals,
        },
      };

  test('lists fungible assets and coins, merges duplicates, skips APT and dust',
      () async {
    String? query;
    Map<String, Object?>? variables;
    final ChainApi api = ChainApi(
      client: MockClient((http.Request request) async {
        final Map<String, Object?> body =
            jsonDecode(request.body) as Map<String, Object?>;
        query = body['query'] as String;
        variables = (body['variables'] as Map).cast<String, Object?>();
        expect(request.url.toString(), ChainApi.aptosIndexerUrl);
        return indexer(<Map<String, Object?>>[
          row(usdcFa, 4000000, 'USDC', 6),
          row(usdcFa, 1000000, 'USDC', 6),
          row('0x1::aptos_coin::AptosCoin', 500000000, 'APT', 8),
          row('0xf22b::asset::USDT', 0, 'USDT', 6),
          row('0xf22b::asset::USDC', 250000, 'USDC', 6),
          row('0xdead::coin::Broken', 10, 'X', 0)..remove('metadata'),
        ]);
      }),
    );

    final List<TokenBalance> tokens =
        await api.fetchTokenBalances(NetworkCatalog.aptos, address);

    expect(tokens.map((TokenBalance t) => t.contractAddress),
        <String>[usdcFa, '0xf22b::asset::USDC']);
    expect(tokens.first.balance, BigInt.from(5000000));
    expect(tokens.first.decimals, 6);
    expect(query, contains('current_fungible_asset_balances'));
    // The owner is sent in the indexer's full form: 0x + 64 hex digits.
    expect(variables!['owner'], address);
    api.dispose();
  });

  test('a short address is padded to the indexer form', () async {
    Map<String, Object?>? variables;
    final ChainApi api = ChainApi(
      client: MockClient((http.Request request) async {
        variables = ((jsonDecode(request.body) as Map)['variables'] as Map)
            .cast<String, Object?>();
        return indexer(const <Map<String, Object?>>[]);
      }),
    );
    await api.fetchTokenBalances(NetworkCatalog.aptos, '0xA');
    expect(variables!['owner'], '0x${'0' * 63}a');
    api.dispose();
  });

  test('an indexer outage leaves the balance screen without tokens, not broken',
      () async {
    final ChainApi api = ChainApi(
      client: MockClient((_) async => http.Response('nope', 503)),
    );
    expect(await api.fetchTokenBalances(NetworkCatalog.aptos, address), isEmpty);
    api.dispose();
  });

  test('the live balance of one asset sums its rows', () async {
    final ChainApi api = ChainApi(
      client: MockClient((_) async => indexer(<Map<String, Object?>>[
            row(usdcFa, 4000000, 'USDC', 6),
            row(usdcFa, 1000000, 'USDC', 6),
          ])),
    );
    expect(
      await api.fetchAptosTokenBalance(NetworkCatalog.aptos, address, usdcFa),
      BigInt.from(5000000),
    );
    expect(
      await api.fetchAptosTokenBalance(NetworkCatalog.aptos, address, '0xother'),
      BigInt.zero,
    );
    api.dispose();
  });
}
