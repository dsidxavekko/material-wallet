import 'dart:convert';

import 'package:crypto_wallet/core/utils/csv_export.dart';
import 'package:crypto_wallet/data/networks/activity_merge.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final BigInt _fee = BigInt.parse('21000000000000'); // 0.000021 ETH

void main() {
  const String me = '0x1111111111111111111111111111111111111111';
  const String other = '0x2222222222222222222222222222222222222222';
  const String usdc = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';

  ChainTransaction call({
    required String hash,
    required DateTime at,
    bool incoming = false,
    String to = usdc,
    String? rawInput,
  }) =>
      ChainTransaction(
        hash: hash,
        timestamp: at,
        amount: incoming ? BigInt.zero : -_fee,
        fee: _fee,
        counterparty: to,
        isIncoming: incoming,
        confirmed: true,
        nonce: 5,
        rawInput: rawInput,
      );

  TokenTransfer transfer({
    required String hash,
    required DateTime at,
    required String from,
    required String to,
    int value = 100000000,
  }) =>
      TokenTransfer(
        hash: hash,
        timestamp: at,
        from: from,
        to: to,
        value: BigInt.from(value),
        symbol: 'USDC',
        decimals: 6,
        contract: usdc,
      );

  final DateTime t1 = DateTime.utc(2026, 1, 1, 10);
  final DateTime t2 = DateTime.utc(2026, 1, 2, 10);
  final DateTime t3 = DateTime.utc(2026, 1, 3, 10);

  group('mergeTokenTransfers', () {
    test('an outgoing token call becomes "Sent 100 USDC", fee kept', () {
      final List<ChainTransaction> merged = mergeTokenTransfers(
        native: <ChainTransaction>[call(hash: '0xaa', at: t1)],
        transfers: <TokenTransfer>[
          transfer(hash: '0xAA', at: t1, from: me, to: other),
        ],
        address: me,
      );

      expect(merged, hasLength(1));
      final ChainTransaction row = merged.single;
      expect(row.isToken, isTrue);
      expect(row.isIncoming, isFalse);
      expect(row.amountLabel(NetworkCatalog.ethereum), '−100 USDC');
      expect(row.fee, _fee);
      // The contract stays the call target — a speed-up signs `to` from it —
      // while the display peer is the real recipient.
      expect(row.counterparty, usdc);
      expect(row.displayCounterparty, other);
      expect(row.nonce, 5);
    });

    test('a token received has no call of its own and becomes its own row', () {
      final List<ChainTransaction> merged = mergeTokenTransfers(
        native: const <ChainTransaction>[],
        transfers: <TokenTransfer>[
          transfer(hash: '0xbb', at: t2, from: other, to: me),
        ],
        address: me,
      );

      expect(merged, hasLength(1));
      expect(merged.single.isIncoming, isTrue);
      expect(merged.single.amountLabel(NetworkCatalog.ethereum), '+100 USDC');
      expect(merged.single.fee, BigInt.zero);
      expect(merged.single.displayCounterparty, other);
      expect(merged.single.nonce, isNull);
    });

    test('an incoming leg inside my own call is a separate row', () {
      // A swap: I paid ETH-fee and sent token A, and received token B.
      final List<ChainTransaction> merged = mergeTokenTransfers(
        native: <ChainTransaction>[call(hash: '0xcc', at: t1)],
        transfers: <TokenTransfer>[
          transfer(hash: '0xcc', at: t1, from: me, to: other),
          transfer(hash: '0xcc', at: t1, from: other, to: me, value: 5),
        ],
        address: me,
      );

      expect(merged, hasLength(2));
      expect(merged.where((ChainTransaction t) => t.isIncoming), hasLength(1));
      expect(
        merged.where((ChainTransaction t) => !t.isIncoming).single.fee,
        _fee,
      );
    });

    test('an approval without a transfer reads as an approval', () {
      final ChainTransaction approve = call(
        hash: '0xdd',
        at: t1,
        rawInput: '0x095ea7b3${'0' * 128}',
      );
      final List<ChainTransaction> merged = mergeTokenTransfers(
        native: <ChainTransaction>[approve],
        transfers: const <TokenTransfer>[],
        address: me,
      );

      expect(merged.single.isApproval, isTrue);
      expect(merged.single.isToken, isFalse);
    });

    test('newest first, merged rows interleave by time', () {
      final List<ChainTransaction> merged = mergeTokenTransfers(
        native: <ChainTransaction>[
          call(hash: '0x01', at: t1, to: other),
          call(hash: '0x03', at: t3, to: other),
        ],
        transfers: <TokenTransfer>[
          transfer(hash: '0x02', at: t2, from: other, to: me),
        ],
        address: me,
      );

      expect(
        merged.map((ChainTransaction t) => t.hash),
        <String>['0x03', '0x02', '0x01'],
      );
    });
  });

  group('cache compatibility', () {
    test('a row cached before token fields existed still reads', () {
      final ChainTransaction old = ChainTransaction.fromJson(
        <String, Object?>{
          'hash': '0xold',
          'timestamp': t1.toIso8601String(),
          'amount': '-5',
          'fee': '1',
          'counterparty': other,
          'isIncoming': false,
          'confirmed': true,
        },
      );

      expect(old.isToken, isFalse);
      expect(old.tokenSymbol, isNull);
      expect(old.displayCounterparty, other);
    });

    test('token fields survive a round trip', () {
      final ChainTransaction row = mergeTokenTransfers(
        native: <ChainTransaction>[call(hash: '0xaa', at: t1)],
        transfers: <TokenTransfer>[
          transfer(hash: '0xaa', at: t1, from: me, to: other),
        ],
        address: me,
      ).single;

      final ChainTransaction back = ChainTransaction.fromJson(
        (jsonDecode(jsonEncode(row.toJson())) as Map<String, Object?>),
      );

      expect(back.isToken, isTrue);
      expect(back.tokenAmount, BigInt.from(100000000));
      expect(back.displayCounterparty, other);
    });
  });

  group('csv', () {
    test('a token row has the token ticker and a separate fee ticker', () {
      final ChainTransaction row = mergeTokenTransfers(
        native: <ChainTransaction>[call(hash: '0xaa', at: t1)],
        transfers: <TokenTransfer>[
          transfer(hash: '0xaa', at: t1, from: me, to: other),
        ],
        address: me,
      ).single;

      final String csv = buildActivityCsv(
        AccountSnapshot(
          network: NetworkCatalog.ethereum,
          address: me,
          balance: BigInt.zero,
          transactions: <ChainTransaction>[row],
          chart: const <double>[],
          fetchedAt: t1,
        ),
      );

      final List<String> lines = csv.trim().split('\n');
      expect(lines.first, contains(',fee,fee_ticker,'));
      expect(lines.first, endsWith(',status,note'));
      expect(lines[1], contains(',out,100,USDC,0.000021,ETH,$other,'));
    });
  });

  group('paging', () {
    http.Response json(Object body) => http.Response(
          jsonEncode(body),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );

    test('Blockscout: both feeds are asked, and the cursors are followed',
        () async {
      final List<Uri> seen = <Uri>[];
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          seen.add(request.url);
          final bool transfers = request.url.path.endsWith('token-transfers');
          final bool second = request.url.queryParameters.containsKey('index');
          if (transfers) {
            return json(<String, Object?>{
              'items': <Object?>[
                <String, Object?>{
                  'transaction_hash': '0xt${second ? 2 : 1}',
                  'timestamp': '2026-01-02T10:00:00.000000Z',
                  'from': <String, Object?>{'hash': other},
                  'to': <String, Object?>{'hash': me},
                  'total': <String, Object?>{
                    'value': '1000000',
                    'decimals': '6',
                  },
                  'token': <String, Object?>{
                    'symbol': 'USDC',
                    'address_hash': usdc,
                  },
                },
                // An NFT transfer has no fungible value and is skipped.
                <String, Object?>{
                  'transaction_hash': '0xnft',
                  'timestamp': '2026-01-02T10:00:00.000000Z',
                  'from': <String, Object?>{'hash': other},
                  'to': <String, Object?>{'hash': me},
                  'total': <String, Object?>{'token_id': '7'},
                  'token': <String, Object?>{'symbol': 'APE'},
                },
              ],
              'next_page_params': second
                  ? null
                  : <String, Object?>{'block_number': 10, 'index': 3},
            });
          }
          return json(<String, Object?>{
            'items': <Object?>[],
            'next_page_params': null,
          });
        }),
      );

      final ActivityPage first =
          await api.fetchActivityPage(NetworkCatalog.ethereum, me);
      expect(first.transfers, hasLength(1));
      expect(first.next, isNotNull);
      // The native feed ended on page one, so only transfers are asked again.
      expect(first.next!.native, isNull);
      expect(first.next!.transfers, <String, String>{
        'block_number': '10',
        'index': '3',
      });

      seen.clear();
      final ActivityPage second = await api.fetchActivityPage(
        NetworkCatalog.ethereum,
        me,
        after: first.next,
      );
      expect(seen, hasLength(1));
      expect(seen.single.path, endsWith('token-transfers'));
      expect(seen.single.queryParameters['block_number'], '10');
      expect(seen.single.queryParameters['type'], 'ERC-20');
      expect(second.transfers.single.hash, '0xt2');
      expect(second.next, isNull);
    });

    test('a failing token feed does not take the native list down', () async {
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          if (request.url.path.endsWith('token-transfers')) {
            return http.Response('boom', 500);
          }
          return json(<String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'hash': '0xabc',
                'timestamp': '2026-01-02T10:00:00.000000Z',
                'from': <String, Object?>{'hash': me},
                'to': <String, Object?>{'hash': other},
                'value': '1',
                'fee': <String, Object?>{'value': '1'},
                'status': 'ok',
                'block': 1,
              },
            ],
          });
        }),
      );

      final ActivityPage page =
          await api.fetchActivityPage(NetworkCatalog.ethereum, me);
      expect(page.native, hasLength(1));
      expect(page.transfers, isEmpty);
    });

    test('Bitcoin: a full confirmed page yields a txid cursor', () async {
      const String btc = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
      Map<String, Object?> txEntry(int i) => <String, Object?>{
            'txid': 'tx$i',
            'fee': 100,
            'status': <String, Object?>{
              'confirmed': true,
              'block_time': 1700000000 + i,
            },
            'vin': <Object?>[],
            'vout': <Object?>[
              <String, Object?>{'scriptpubkey_address': btc, 'value': 1000},
            ],
          };
      final List<Uri> seen = <Uri>[];
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          seen.add(request.url);
          final bool older = request.url.path.contains('/txs/chain/');
          return json(<Object?>[
            for (int i = 0; i < (older ? 3 : 25); i++) txEntry(i),
          ]);
        }),
      );

      final ActivityPage first =
          await api.fetchActivityPage(NetworkCatalog.bitcoin, btc);
      expect(first.native, hasLength(25));
      expect(first.next!.native!['last_seen'], 'tx0');

      final ActivityPage second = await api.fetchActivityPage(
        NetworkCatalog.bitcoin,
        btc,
        after: first.next,
      );
      expect(seen.last.path, endsWith('/txs/chain/tx0'));
      expect(second.next, isNull);
    });

    test('Solana: the cursor is the last signature, passed as before',
        () async {
      Object? lastBefore;
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          final Map<String, Object?> body =
              jsonDecode(request.body) as Map<String, Object?>;
          if (body['method'] == 'getSignaturesForAddress') {
            final Map<String, Object?> options =
                (body['params']! as List<Object?>)[1]! as Map<String, Object?>;
            lastBefore = options['before'];
            return json(<String, Object?>{
              'result': <Object?>[
                for (int i = 0; i < 6; i++)
                  <String, Object?>{'signature': 'sig$i'},
              ],
            });
          }
          return json(<String, Object?>{'result': null});
        }),
      );

      final ActivityPage first = await api.fetchActivityPage(
        NetworkCatalog.solana,
        'SoLaNaAddress',
      );
      expect(first.next!.native!['before'], 'sig5');

      await api.fetchActivityPage(
        NetworkCatalog.solana,
        'SoLaNaAddress',
        after: first.next,
      );
      expect(lastBefore, 'sig5');
    });

    test('Aptos: pages walk back by sequence number and stop at zero',
        () async {
      final List<Uri> seen = <Uri>[];
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          seen.add(request.url);
          final bool older = request.url.queryParameters.containsKey('start');
          final int top = older ? 20 : 40;
          return json(<Object?>[
            for (int i = top; i > top - 15; i--)
              <String, Object?>{
                'type': 'user_transaction',
                'sequence_number': '$i',
                'sender': '0x1',
                'hash': '0xh$i',
                'success': true,
                'timestamp': '1700000000000000',
                'payload': <String, Object?>{'function': '0x1::foo::bar'},
              },
          ]);
        }),
      );

      final ActivityPage first =
          await api.fetchActivityPage(NetworkCatalog.aptos, '0x1');
      expect(first.next!.native, <String, String>{'start': '11', 'limit': '15'});

      final ActivityPage second = await api.fetchActivityPage(
        NetworkCatalog.aptos,
        '0x1',
        after: first.next,
      );
      expect(seen.last.queryParameters['start'], '11');
      expect(second.next!.native!['start'], '0');
      expect(second.next!.native!['limit'], '6');
    });
  });
}
