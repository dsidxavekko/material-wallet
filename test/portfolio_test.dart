import 'dart:convert';

import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/networks/price_api.dart';
import 'package:crypto_wallet/state/portfolio_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeChain extends ChainApi {
  final Map<String, BigInt> balances = <String, BigInt>{};
  final Set<String> failing = <String>{};
  final Map<String, List<TokenBalance>> tokens = <String, List<TokenBalance>>{};

  @override
  Future<BigInt> fetchBalance(NetworkConfig network, String address) async {
    if (failing.contains(network.id)) {
      throw const ChainApiException('node down');
    }
    return balances[network.id] ?? BigInt.zero;
  }

  @override
  Future<List<TokenBalance>> fetchTokenBalances(
    NetworkConfig network,
    String address,
  ) async =>
      tokens[network.id] ?? const <TokenBalance>[];

  @override
  void dispose() {}
}

void main() {
  const List<NetworkConfig> nets = <NetworkConfig>[
    NetworkCatalog.bitcoin,
    NetworkCatalog.ethereum,
    NetworkCatalog.polygon,
    NetworkCatalog.base,
  ];

  test('one price request covers every coin; sorted by value', () async {
    final List<Uri> priceRequests = <Uri>[];
    final MockClient client = MockClient((http.Request request) async {
      priceRequests.add(request.url);
      return http.Response(
        jsonEncode(<String, Object>{
          'bitcoin': <String, Object>{'usd': 60000.0},
          'ethereum': <String, Object>{'usd': 2000.0},
          'polygon-ecosystem-token': <String, Object>{'usd': 0.5},
        }),
        200,
      );
    });

    final _FakeChain chain = _FakeChain()
      ..balances['bitcoin'] = BigInt.from(10000000) // 0.1 BTC = $6000
      ..balances['ethereum'] = BigInt.parse('1000000000000000000') // $2000
      ..balances['polygon'] = BigInt.parse('10000000000000000000') // $5
      ..tokens['ethereum'] = <TokenBalance>[
        TokenBalance(
          symbol: 'USDC',
          name: 'USD Coin',
          decimals: 6,
          balance: BigInt.zero,
          contractAddress: '0xusdc',
          usdRate: 1,
        ),
      ];
    chain.tokens['base'] = <TokenBalance>[
      TokenBalance(
        symbol: 'USDC',
        name: 'USD Coin',
        decimals: 6,
        balance: BigInt.from(1000000000), // 1000 USDC
        contractAddress: '0xusdc',
        usdRate: 1,
      ),
    ];

    final PortfolioController portfolio = PortfolioController(
      addressFor: (NetworkConfig n) => 'addr-${n.id}',
      chainApi: chain,
      priceApi: PriceApi(client: client),
      networks: nets,
    );
    await portfolio.load();

    // One batched request for all three distinct coins.
    expect(priceRequests, hasLength(1));
    final String ids = priceRequests.single.queryParameters['ids']!;
    expect(ids.split(',').toSet(), <String>{
      'bitcoin',
      'ethereum',
      'polygon-ecosystem-token',
    });

    expect(
      portfolio.entries.map((PortfolioEntry e) => e.network.id).toList(),
      <String>['bitcoin', 'ethereum', 'base', 'polygon'],
    );
    expect(portfolio.entries[2].totalUsd, closeTo(1000, 1e-9)); // tokens only… 
    expect(portfolio.totalUsd, closeTo(6000 + 2000 + 1000 + 5, 1e-6));
    expect(portfolio.incomplete, isFalse);
    portfolio.dispose();
  });

  test('a hidden token is not counted in the entry or the total', () async {
    final _FakeChain chain = _FakeChain()
      ..balances['ethereum'] = BigInt.parse('1000000000000000000') // $2000
      ..tokens['ethereum'] = <TokenBalance>[
        TokenBalance(
          symbol: 'USDC',
          name: 'USD Coin',
          decimals: 6,
          balance: BigInt.from(1000000000),
          contractAddress: '0xusdc',
          usdRate: 1,
        ),
        TokenBalance(
          symbol: 'AIRDROP',
          name: 'Airdrop',
          decimals: 6,
          balance: BigInt.from(500000000),
          contractAddress: '0xairdrop',
          usdRate: 1,
        ),
      ];
    final PortfolioController portfolio = PortfolioController(
      addressFor: (NetworkConfig n) => 'addr-${n.id}',
      chainApi: chain,
      priceApi: PriceApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object>{
              'ethereum': <String, Object>{'usd': 2000.0},
            }),
            200,
          ),
        ),
      ),
      networks: const <NetworkConfig>[NetworkCatalog.ethereum],
      isTokenHidden: (String networkId, TokenBalance t) =>
          networkId == 'ethereum' && t.contractAddress == '0xairdrop',
    );
    await portfolio.load();

    expect(portfolio.entries.single.visibleTokens, hasLength(1));
    expect(portfolio.totalUsd, closeTo(2000 + 1000, 1e-6)); // not + 500
    portfolio.dispose();
  });

  test('a failing network is shown as unavailable, never as empty', () async {
    final _FakeChain chain = _FakeChain()
      ..balances['bitcoin'] = BigInt.from(100000000)
      ..failing.add('ethereum');
    final PortfolioController portfolio = PortfolioController(
      addressFor: (NetworkConfig n) => 'addr-${n.id}',
      chainApi: chain,
      priceApi: PriceApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object>{
              'bitcoin': <String, Object>{'usd': 50000.0},
            }),
            200,
          ),
        ),
      ),
      networks: const <NetworkConfig>[
        NetworkCatalog.bitcoin,
        NetworkCatalog.ethereum,
      ],
    );
    await portfolio.load();

    final PortfolioEntry eth = portfolio.entries
        .firstWhere((PortfolioEntry e) => e.network.id == 'ethereum');
    expect(eth.failed, isTrue);
    expect(eth.error, 'node down');
    expect(portfolio.incomplete, isTrue);
    // Failures sort last, and the total counts only what was read.
    expect(portfolio.entries.last.network.id, 'ethereum');
    expect(portfolio.totalUsd, closeTo(50000, 1e-6));
    portfolio.dispose();
  });

  test('a locked wallet (no addresses) loads nothing', () async {
    final PortfolioController portfolio = PortfolioController(
      addressFor: (_) => null,
      chainApi: _FakeChain(),
      priceApi: PriceApi(client: MockClient((_) async => http.Response('{}', 200))),
      networks: nets,
    );
    await portfolio.load();
    expect(portfolio.entries, isEmpty);
    expect(portfolio.totalUsd, isNull);
    portfolio.dispose();
  });

  test('fetchPrices serves fresh ids from the cache and asks only for the rest',
      () async {
    final List<String> asked = <String>[];
    final PriceApi api = PriceApi(
      client: MockClient((http.Request request) async {
        asked.add(request.url.queryParameters['ids']!);
        final List<String> ids = request.url.queryParameters['ids']!.split(',');
        return http.Response(
          jsonEncode(<String, Object>{
            for (final String id in ids) id: <String, Object>{'usd': 1.0},
          }),
          200,
        );
      }),
    );

    await api.fetchPrices(<String>['bitcoin']);
    final Map<String, CoinPrice> second =
        await api.fetchPrices(<String>['bitcoin', 'ethereum']);

    expect(asked, <String>['bitcoin', 'ethereum']);
    expect(second.keys.toSet(), <String>{'bitcoin', 'ethereum'});
  });
}
