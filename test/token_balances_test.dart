import 'dart:convert';

import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  http.Response json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: const <String, String>{'content-type': 'application/json'},
      );

  test('parses, filters and sorts ERC-20 balances by USD value', () async {
    final ChainApi api = ChainApi(
      client: MockClient((_) async => json(<String, Object>{
            'items': <Object>[
              <String, Object>{
                'token': <String, Object>{
                  'symbol': 'USDT',
                  'name': 'Tether',
                  'decimals': '6',
                  'address_hash': '0xusdt',
                  'exchange_rate': '1.0',
                },
                'value': '291368219',
              },
              <String, Object>{
                'token': <String, Object>{
                  'symbol': 'ZERO',
                  'decimals': '18',
                  'address_hash': '0xz',
                },
                'value': '0',
              },
              <String, Object>{
                'token': <String, Object>{
                  'symbol': 'WETH',
                  'name': 'WETH',
                  'decimals': '18',
                  'address_hash': '0xw',
                  'exchange_rate': '2704.45',
                },
                'value': '1465109424750435891',
              },
            ],
          })),
    );

    final List<TokenBalance> tokens =
        await api.fetchTokenBalances(NetworkCatalog.ethereum, '0xabc');

    // Zero balances are dropped and the list is ordered by USD value.
    expect(tokens.map((TokenBalance t) => t.symbol).toList(),
        <String>['WETH', 'USDT']);
    expect(tokens.first.usdValue, greaterThan(tokens[1].usdValue!));
    expect(tokens.first.contractAddress, '0xw');
    expect(tokens[1].amountLabel, '291.368219');
  });

  test('returns an empty list on networks without a token index', () async {
    final ChainApi api = ChainApi(
      client: MockClient((_) async {
        fail('the network should not be queried for token balances');
      }),
    );

    expect(await api.fetchTokenBalances(NetworkCatalog.bitcoin, 'bc1q'), isEmpty);
    expect(await api.fetchTokenBalances(NetworkCatalog.solana, 'x'), isEmpty);
    // BNB is JSON-RPC only, so there is no Blockscout token index.
    expect(await api.fetchTokenBalances(NetworkCatalog.bnb, '0xabc'), isEmpty);
  });

  test('a failing token request degrades to an empty list', () async {
    final ChainApi api = ChainApi(
      client: MockClient((_) async => http.Response('boom', 500)),
    );

    expect(
      await api.fetchTokenBalances(NetworkCatalog.ethereum, '0xabc'),
      isEmpty,
    );
  });
}
