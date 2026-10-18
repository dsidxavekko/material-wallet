import 'dart:convert';

import 'package:crypto_wallet/core/theme/app_theme.dart';
import 'package:crypto_wallet/core/utils/csv_export.dart';
import 'package:crypto_wallet/core/utils/formatters.dart';
import 'package:crypto_wallet/features/activity/widgets/transaction_tile.dart';
import 'package:crypto_wallet/data/networks/activity.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String wallet = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';
const String other = '0x71C7656EC7ab88b098defB751B7401B5f6d8976F';
const String usdc = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
const String weth = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';

DateTime at(int minute) => DateTime.utc(2026, 5, 1, 12, minute);

ChainTransaction native({
  required String hash,
  required int minute,
  bool incoming = false,
  String counterparty = usdc,
  bool confirmed = true,
}) =>
    ChainTransaction(
      hash: hash,
      timestamp: at(minute),
      amount: incoming ? BigInt.zero : -BigInt.from(21000),
      fee: BigInt.from(21000),
      counterparty: counterparty,
      isIncoming: incoming,
      confirmed: confirmed,
      nonce: incoming ? null : minute,
    );

TokenTransfer transfer({
  required String hash,
  required int minute,
  String from = wallet,
  String to = other,
  String contract = usdc,
  String symbol = 'USDC',
  int decimals = 6,
  int amount = 100000000,
}) =>
    TokenTransfer(
      hash: hash,
      timestamp: at(minute),
      from: from,
      to: to,
      symbol: symbol,
      contract: contract,
      decimals: decimals,
      amount: BigInt.from(amount),
    );

void main() {
  group('mergeTokenTransfers', () {
    test('an outgoing token send becomes one row: the token and the fee', () {
      final List<ChainTransaction> rows = mergeTokenTransfers(
        natives: <ChainTransaction>[native(hash: '0xa', minute: 5)],
        transfers: <TokenTransfer>[transfer(hash: '0xa', minute: 5)],
        address: wallet,
      );

      expect(rows, hasLength(1));
      final ChainTransaction row = rows.single;
      expect(row.isTokenTransfer, isTrue);
      expect(row.isIncoming, isFalse);
      expect(row.amountLabel(NetworkCatalog.ethereum), '−100 USDC');
      expect(row.ticker(NetworkCatalog.ethereum), 'USDC');
      expect(row.fee, BigInt.from(21000), reason: 'the native fee stays');
      expect(row.displayCounterparty, other, reason: 'the real recipient');
      expect(
        row.counterparty,
        usdc,
        reason: 'the transaction itself went to the token contract, and a '
            'speed-up must resend there',
      );
      expect(row.nonce, 5, reason: 'replacement data is preserved');
    });

    test('an incoming transfer with no native row still shows, at no fee', () {
      final List<ChainTransaction> rows = mergeTokenTransfers(
        natives: const <ChainTransaction>[],
        transfers: <TokenTransfer>[
          transfer(hash: '0xb', minute: 7, from: other, to: wallet),
        ],
        address: wallet,
      );

      expect(rows, hasLength(1));
      expect(rows.single.isIncoming, isTrue);
      expect(rows.single.amountLabel(NetworkCatalog.ethereum), '+100 USDC');
      expect(rows.single.fee, BigInt.zero, reason: 'the sender paid the fee');
      expect(rows.single.amount, BigInt.zero);
      expect(rows.single.displayCounterparty, other);
      expect(rows.single.confirmed, isTrue);
    });

    test('a swap: the token out merges with the fee, the token in is its own row',
        () {
      final List<ChainTransaction> rows = mergeTokenTransfers(
        natives: <ChainTransaction>[
          native(hash: '0xs', minute: 9, counterparty: other),
        ],
        transfers: <TokenTransfer>[
          transfer(hash: '0xs', minute: 9),
          transfer(
            hash: '0xs',
            minute: 9,
            from: other,
            to: wallet,
            contract: weth,
            symbol: 'WETH',
            decimals: 18,
            amount: 5 * 1000000000000000,
          ),
        ],
        address: wallet,
      );

      expect(rows, hasLength(2));
      final ChainTransaction out = rows.firstWhere((r) => !r.isIncoming);
      final ChainTransaction inn = rows.firstWhere((r) => r.isIncoming);
      expect(out.fee, BigInt.from(21000));
      expect(out.token!.symbol, 'USDC');
      expect(inn.token!.symbol, 'WETH');
      expect(inn.amountLabel(NetworkCatalog.ethereum), '+0.005 WETH');
      expect(inn.fee, BigInt.zero, reason: 'the fee is counted once');
    });

    test('a native row without token transfers is untouched', () {
      final ChainTransaction row = native(
        hash: '0xn',
        minute: 3,
        counterparty: other,
      );
      final List<ChainTransaction> rows = mergeTokenTransfers(
        natives: <ChainTransaction>[row],
        transfers: const <TokenTransfer>[],
        address: wallet,
      );
      expect(rows.single, same(row));
    });

    test('a pending token send keeps its place at the top as a native row', () {
      final List<ChainTransaction> rows = mergeTokenTransfers(
        natives: <ChainTransaction>[
          native(hash: '0xp', minute: 59, confirmed: false),
          native(hash: '0xold', minute: 1),
        ],
        transfers: const <TokenTransfer>[],
        address: wallet,
      );
      expect(rows.first.hash, '0xp');
      expect(rows.first.isPending, isTrue);
    });

    test('rows come out newest first', () {
      final List<ChainTransaction> rows = mergeTokenTransfers(
        natives: <ChainTransaction>[native(hash: '0x1', minute: 2)],
        transfers: <TokenTransfer>[
          transfer(hash: '0x2', minute: 8, from: other, to: wallet),
        ],
        address: wallet,
      );
      expect(rows.map((r) => r.hash), <String>['0x2', '0x1']);
    });

    test(
        'while the native list has older pages, transfers older than its oldest '
        'row are held back', () {
      // The transfer at minute 2 belongs to a transaction the next native page
      // will bring. Showing it now would split one send into two rows later.
      final List<ChainTransaction> rows = mergeTokenTransfers(
        natives: <ChainTransaction>[
          native(hash: '0xnew', minute: 20),
          native(hash: '0xmid', minute: 10),
        ],
        transfers: <TokenTransfer>[
          transfer(hash: '0xnew', minute: 20),
          transfer(hash: '0xold', minute: 2),
        ],
        address: wallet,
        nativeHasMore: true,
      );
      expect(rows.map((r) => r.hash), <String>['0xnew', '0xmid']);
    });

    test('and the other way round: natives older than the oldest transfer wait',
        () {
      final List<ChainTransaction> rows = mergeTokenTransfers(
        natives: <ChainTransaction>[
          native(hash: '0xa', minute: 20, counterparty: other),
          native(hash: '0xb', minute: 2, counterparty: other),
        ],
        transfers: <TokenTransfer>[transfer(hash: '0xa', minute: 20)],
        address: wallet,
        transfersHasMore: true,
      );
      expect(rows.map((r) => r.hash), <String>['0xa']);
    });

    test('with both lists exhausted nothing is held back', () {
      final List<ChainTransaction> rows = mergeTokenTransfers(
        natives: <ChainTransaction>[native(hash: '0xb', minute: 2)],
        transfers: <TokenTransfer>[
          transfer(hash: '0xold', minute: 1, from: other, to: wallet),
        ],
        address: wallet,
      );
      expect(rows, hasLength(2));
    });
  });

  group('persistence', () {
    test('a token row survives a JSON round trip', () {
      final ChainTransaction row = mergeTokenTransfers(
        natives: <ChainTransaction>[native(hash: '0xa', minute: 5)],
        transfers: <TokenTransfer>[transfer(hash: '0xa', minute: 5)],
        address: wallet,
      ).single;

      final ChainTransaction restored = ChainTransaction.fromJson(
        (jsonDecode(jsonEncode(row.toJson())) as Map<String, Object?>),
      );
      expect(restored.token!.symbol, 'USDC');
      expect(restored.token!.amount, BigInt.from(100000000));
      expect(restored.displayCounterparty, other);
    });

    test('a cache written before token rows existed still reads', () {
      final ChainTransaction restored = ChainTransaction.fromJson(
        <String, Object?>{
          'hash': '0xold',
          'timestamp': '2026-01-01T00:00:00.000Z',
          'amount': '-5',
          'fee': '1',
          'counterparty': usdc,
          'isIncoming': false,
          'confirmed': true,
        },
      );
      expect(restored.token, isNull);
      expect(restored.displayCounterparty, usdc);
    });

    test('a damaged token payload reads as a native row, not a crash', () {
      final ChainTransaction restored = ChainTransaction.fromJson(
        <String, Object?>{
          'hash': '0xold',
          'timestamp': '2026-01-01T00:00:00.000Z',
          'amount': '-5',
          'fee': '1',
          'counterparty': usdc,
          'token': <String, Object?>{'symbol': 'USDC'},
        },
      );
      expect(restored.token, isNull);
    });
  });

  group('CSV with token rows', () {
    test('reports the token amount and ticker with the fee in the coin', () {
      final ChainTransaction row = mergeTokenTransfers(
        natives: <ChainTransaction>[native(hash: '0xa', minute: 5)],
        transfers: <TokenTransfer>[transfer(hash: '0xa', minute: 5)],
        address: wallet,
      ).single;

      final String csv = buildActivityCsv(
        AccountSnapshot(
          network: NetworkCatalog.ethereum,
          address: wallet,
          balance: BigInt.zero,
          transactions: <ChainTransaction>[row],
          chart: const <double>[],
          fetchedAt: at(0),
        ),
      );
      final List<String> lines = csv.trim().split('\n');
      expect(
        lines.first,
        'date,network,direction,amount,ticker,fee,fee_ticker,counterparty,'
        'hash,status,note',
      );
      expect(
        lines[1],
        '2026-05-01T12:05:00.000Z,Ethereum,out,100,USDC,0.000000000000021,ETH,'
        '$other,0xa,confirmed,',
      );
    });
  });

  group('ChainApi activity paging', () {
    http.Response json(Object body) => http.Response(
          jsonEncode(body),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );

    Map<String, Object?> nativeItem(String hash, String to, String ts) =>
        <String, Object?>{
          'hash': hash,
          'timestamp': ts,
          'from': <String, Object>{'hash': wallet},
          'to': <String, Object>{'hash': to},
          'value': '0',
          'fee': <String, Object>{'value': '21000'},
          'status': 'ok',
          'block': 1,
        };

    Map<String, Object?> transferItem(
      String hash,
      String ts, {
      String type = 'ERC-20',
      String from = wallet,
      String to = other,
    }) =>
        <String, Object?>{
          'transaction_hash': hash,
          'timestamp': ts,
          'from': <String, Object>{'hash': from},
          'to': <String, Object>{'hash': to},
          'token': <String, Object?>{
            'address_hash': usdc,
            'symbol': 'USDC',
            'decimals': '6',
            'type': type,
          },
          'total': <String, Object?>{'decimals': '6', 'value': '100000000'},
        };

    test('merges the token feed into the native history', () async {
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          if (request.url.path.endsWith('/token-transfers')) {
            expect(request.url.queryParameters['type'], 'ERC-20');
            return json(<String, Object?>{
              'items': <Object>[
                transferItem('0xa', '2026-05-01T12:05:00.000000Z'),
                transferItem(
                  '0xin',
                  '2026-05-01T12:03:00.000000Z',
                  from: other,
                  to: wallet,
                ),
              ],
              'next_page_params': null,
            });
          }
          return json(<String, Object?>{
            'items': <Object>[
              nativeItem('0xa', usdc, '2026-05-01T12:05:00.000000Z'),
            ],
            'next_page_params': null,
          });
        }),
      );

      final ActivityPage page =
          await api.fetchActivityPage(NetworkCatalog.ethereum, wallet);

      expect(page.transactions.map((t) => t.hash), <String>['0xa', '0xin']);
      expect(page.transactions.first.amountLabel(NetworkCatalog.ethereum),
          '−100 USDC');
      expect(page.transactions.last.isIncoming, isTrue);
      expect(page.next, isNull, reason: 'both feeds are exhausted');
    });

    test('skips NFT transfers and entries without an amount', () async {
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          if (request.url.path.endsWith('/token-transfers')) {
            return json(<String, Object?>{
              'items': <Object>[
                transferItem('0x1', '2026-05-01T12:05:00.000000Z',
                    type: 'ERC-721'),
                <String, Object?>{
                  'transaction_hash': '0x2',
                  'timestamp': '2026-05-01T12:04:00.000000Z',
                  'from': <String, Object>{'hash': other},
                  'to': <String, Object>{'hash': wallet},
                  'token': <String, Object?>{'address_hash': usdc},
                  'total': <String, Object?>{'token_id': '7'},
                },
              ],
            });
          }
          return json(<String, Object?>{'items': <Object>[]});
        }),
      );
      final ActivityPage page =
          await api.fetchActivityPage(NetworkCatalog.ethereum, wallet);
      expect(page.transactions, isEmpty);
    });

    test('the native history still loads when the token feed fails', () async {
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          if (request.url.path.endsWith('/token-transfers')) {
            return http.Response('boom', 500);
          }
          return json(<String, Object?>{
            'items': <Object>[
              nativeItem('0xa', other, '2026-05-01T12:05:00.000000Z'),
            ],
          });
        }),
      );
      final ActivityPage page =
          await api.fetchActivityPage(NetworkCatalog.ethereum, wallet);
      expect(page.transactions.single.hash, '0xa');
    });

    test('"Load more" continues from next_page_params and re-merges', () async {
      final List<Uri> requested = <Uri>[];
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          requested.add(request.url);
          final bool tokens = request.url.path.endsWith('/token-transfers');
          final bool second =
              request.url.queryParameters.containsKey('block_number');
          if (tokens) {
            return json(second
                ? <String, Object?>{
                    'items': <Object>[
                      transferItem('0xold', '2026-05-01T11:00:00.000000Z'),
                    ],
                  }
                : <String, Object?>{
                    'items': <Object>[
                      transferItem('0xnew', '2026-05-01T12:00:00.000000Z'),
                    ],
                    'next_page_params': <String, Object?>{
                      'block_number': 90,
                      'index': 4,
                      'items_count': 50,
                    },
                  });
          }
          return json(second
              ? <String, Object?>{
                  'items': <Object>[
                    nativeItem('0xold', usdc, '2026-05-01T11:00:00.000000Z'),
                  ],
                }
              : <String, Object?>{
                  'items': <Object>[
                    nativeItem('0xnew', usdc, '2026-05-01T12:00:00.000000Z'),
                  ],
                  'next_page_params': <String, Object?>{
                    'block_number': 100,
                    'index': 2,
                    'items_count': 50,
                  },
                });
        }),
      );

      final ActivityPage first =
          await api.fetchActivityPage(NetworkCatalog.ethereum, wallet);
      expect(first.next, isNotNull);
      expect(first.transactions.map((t) => t.hash), <String>['0xnew']);

      requested.clear();
      final ActivityPage second = await api.fetchActivityPage(
        NetworkCatalog.ethereum,
        wallet,
        after: first.next,
      );

      // Each feed continues from its own cursor.
      final Uri nativeUrl =
          requested.firstWhere((u) => u.path.endsWith('/transactions'));
      final Uri tokenUrl =
          requested.firstWhere((u) => u.path.endsWith('/token-transfers'));
      expect(nativeUrl.queryParameters['block_number'], '100');
      expect(nativeUrl.queryParameters['items_count'], '50');
      expect(tokenUrl.queryParameters['block_number'], '90');
      expect(tokenUrl.queryParameters['type'], 'ERC-20');

      expect(second.transactions.map((t) => t.hash), <String>['0xnew', '0xold']);
      expect(second.transactions.every((t) => t.isTokenTransfer), isTrue);
      expect(second.next, isNull, reason: 'nothing older is left');
    });

    test('only the feed that still has pages is fetched again', () async {
      final List<Uri> requested = <Uri>[];
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          requested.add(request.url);
          final bool tokens = request.url.path.endsWith('/token-transfers');
          if (tokens) {
            return json(<String, Object?>{
              'items': <Object>[
                transferItem('0xa', '2026-05-01T12:00:00.000000Z'),
              ],
            });
          }
          return json(<String, Object?>{
            'items': <Object>[
              nativeItem('0xa', usdc, '2026-05-01T12:00:00.000000Z'),
            ],
            'next_page_params': <String, Object?>{'block_number': 5},
          });
        }),
      );
      final ActivityPage first =
          await api.fetchActivityPage(NetworkCatalog.ethereum, wallet);
      requested.clear();
      await api.fetchActivityPage(
        NetworkCatalog.ethereum,
        wallet,
        after: first.next,
      );
      expect(requested.where((u) => u.path.endsWith('/token-transfers')),
          isEmpty);
    });

    test('Bitcoin continues from the oldest confirmed txid', () async {
      const String btc = 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu';
      Map<String, Object?> tx(int n) => <String, Object?>{
            'txid': 'tx$n',
            'fee': 100,
            'status': <String, Object?>{
              'confirmed': true,
              'block_time': 1700000000 - n * 600,
            },
            'vin': <Object>[],
            'vout': <Object>[
              <String, Object?>{'scriptpubkey_address': btc, 'value': 1000},
            ],
          };
      final List<Uri> requested = <Uri>[];
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          requested.add(request.url);
          if (request.url.path.contains('/txs/chain/')) {
            return json(<Object>[tx(100)]);
          }
          return json(<Object>[for (int i = 0; i < 25; i++) tx(i)]);
        }),
      );

      final ActivityPage first =
          await api.fetchActivityPage(NetworkCatalog.bitcoin, btc);
      expect(first.transactions, hasLength(25));
      expect(first.next, isNotNull);

      final ActivityPage second = await api.fetchActivityPage(
        NetworkCatalog.bitcoin,
        btc,
        after: first.next,
      );
      expect(requested.last.path, endsWith('/txs/chain/tx24'));
      expect(second.transactions, hasLength(26));
      expect(second.next, isNull, reason: 'a short page is the last one');
    });
  });

  group('TransactionTile', () {
    Future<void> pump(WidgetTester tester, ChainTransaction row,
        {double? tokenUsdRate}) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TransactionTile(
              transaction: row,
              network: NetworkCatalog.ethereum,
              currency: AppCurrency.usd,
              price: const CoinPrice(usd: 3000, change24h: 0),
              tokenUsdRate: tokenUsdRate,
            ),
          ),
        ),
      );
    }

    testWidgets('a token send reads "Sent USDC", not "Sent ETH"',
        (tester) async {
      final ChainTransaction row = mergeTokenTransfers(
        natives: <ChainTransaction>[native(hash: '0xa', minute: 5)],
        transfers: <TokenTransfer>[transfer(hash: '0xa', minute: 5)],
        address: wallet,
      ).single;

      await pump(tester, row, tokenUsdRate: 1);

      expect(find.text('Sent USDC'), findsOneWidget);
      expect(find.text('−100 USDC'), findsOneWidget);
      expect(find.text(r'$100.00'), findsOneWidget,
          reason: 'priced by the token rate, not the ETH price');
      expect(find.textContaining('Sent ETH'), findsNothing);
    });

    testWidgets('an unpriced token row shows no fiat value', (tester) async {
      final ChainTransaction row = mergeTokenTransfers(
        natives: const <ChainTransaction>[],
        transfers: <TokenTransfer>[
          transfer(hash: '0xb', minute: 7, from: other, to: wallet),
        ],
        address: wallet,
      ).single;

      await pump(tester, row);

      expect(find.text('Received USDC'), findsOneWidget);
      expect(find.text('+100 USDC'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
    });
  });
}
