import 'dart:convert';

import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/networks/price_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const String owner = 'HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk';
  const String usdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
  const String other = 'DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263';

  Map<String, Object?> account(String mint, String amount, int decimals) =>
      <String, Object?>{
        'pubkey': 'acct',
        'account': <String, Object?>{
          'data': <String, Object?>{
            'parsed': <String, Object?>{
              'info': <String, Object?>{
                'mint': mint,
                'tokenAmount': <String, Object?>{
                  'amount': amount,
                  'decimals': decimals,
                },
              },
            },
          },
        },
      };

  http.Response rpc(Object result) => http.Response(
        jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': 1, 'result': result}),
        200,
      );

  group('ChainApi.fetchTokenBalances on Solana', () {
    test('reads both token programs and merges accounts per mint', () async {
      final List<String> programs = <String>[];
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          final Map<String, Object?> body =
              jsonDecode(request.body) as Map<String, Object?>;
          expect(body['method'], 'getTokenAccountsByOwner');
          final String program = ((body['params']! as List<Object?>)[1]!
              as Map<String, Object?>)['programId']! as String;
          programs.add(program);
          return rpc(<String, Object?>{
            'value': program.startsWith('Tokenkeg')
                ? <Object?>[
                    account(usdc, '1500000', 6),
                    account(usdc, '500000', 6), // second account, same mint
                    account(other, '0', 9), // empty: skipped
                  ]
                : <Object?>[account(other, '2000000000', 9)],
          });
        }),
      );

      final List<TokenBalance> tokens =
          await api.fetchTokenBalances(NetworkCatalog.solana, owner);

      expect(programs, hasLength(2));
      expect(programs.last, startsWith('Tokenz'));
      expect(tokens, hasLength(2));
      final TokenBalance u =
          tokens.firstWhere((TokenBalance t) => t.contractAddress == usdc);
      expect(u.balance, BigInt.from(2000000));
      expect(u.decimals, 6);
      expect(u.amountLabel, '2');
      // Not labelled with an invented ticker.
      expect(u.symbol, 'EPjF…Dt1v');
      expect(
        tokens.firstWhere((TokenBalance t) => t.contractAddress == other).balance,
        BigInt.from(2000000000),
      );
    });

    test('a failing node gives no tokens rather than breaking the balance',
        () async {
      final ChainApi api = ChainApi(
        client: MockClient((_) async => http.Response('boom', 500)),
      );
      expect(
        await api.fetchTokenBalances(NetworkCatalog.solana, owner),
        isEmpty,
      );
    });
  });

  group('PriceApi.enrichSplTokens', () {
    TokenBalance raw(String mint, int amount, int decimals) => TokenBalance(
          symbol: ChainApi.splPlaceholderSymbol(mint),
          name: '',
          decimals: decimals,
          balance: BigInt.from(amount),
          contractAddress: mint,
        );

    test('adds prices from one batched request and tickers from lookups',
        () async {
      final List<Uri> requests = <Uri>[];
      final PriceApi api = PriceApi(
        client: MockClient((http.Request request) async {
          requests.add(request.url);
          if (request.url.path.endsWith('/simple/token_price/solana')) {
            return http.Response(
              jsonEncode(<String, Object?>{
                usdc.toLowerCase(): <String, Object?>{'usd': 1.0},
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/coins/solana/contract/$usdc')) {
            return http.Response(
              jsonEncode(<String, Object?>{'symbol': 'usdc', 'name': 'USD Coin'}),
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final List<TokenBalance> tokens = await api.enrichSplTokens(
        <TokenBalance>[raw(other, 5000000000, 9), raw(usdc, 2500000, 6)],
      );

      // One batched price request covering both mints.
      final Uri priced = requests
          .firstWhere((Uri u) => u.path.endsWith('/simple/token_price/solana'));
      expect(
        priced.queryParameters['contract_addresses'],
        '$other,$usdc',
      );

      // Priced token first, with its real ticker and USD value.
      expect(tokens.first.symbol, 'USDC');
      expect(tokens.first.name, 'USD Coin');
      expect(tokens.first.usdValue, closeTo(2.5, 1e-9));
      // The unknown token keeps its mint label and has no price.
      expect(tokens.last.contractAddress, other);
      expect(tokens.last.usdRate, isNull);
      expect(tokens.last.symbol, ChainApi.splPlaceholderSymbol(other));
    });

    test('a known ticker is looked up once, not on every refresh', () async {
      int metaRequests = 0;
      final PriceApi api = PriceApi(
        client: MockClient((http.Request request) async {
          if (request.url.path.contains('/coins/solana/contract/')) {
            metaRequests++;
            return http.Response(
              jsonEncode(<String, Object?>{'symbol': 'usdc', 'name': 'USD Coin'}),
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );

      await api.enrichSplTokens(<TokenBalance>[raw(usdc, 1, 6)]);
      await api.enrichSplTokens(<TokenBalance>[raw(usdc, 2, 6)]);

      expect(metaRequests, 1);
    });

    test('an unreachable price API leaves the tokens as they were', () async {
      final PriceApi api = PriceApi(
        client: MockClient((_) async => throw http.ClientException('down')),
      );
      final List<TokenBalance> out =
          await api.enrichSplTokens(<TokenBalance>[raw(usdc, 7, 6)]);
      expect(out.single.balance, BigInt.from(7));
      expect(out.single.usdRate, isNull);
    });
  });
}
