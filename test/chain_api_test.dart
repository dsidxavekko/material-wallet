import 'dart:convert';

import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/state/send_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const String btcAddress = 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu';
  const String otherBtc = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
  const String evmAddress = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';
  const String otherEvm = '0x71C7656EC7ab88b098defB751B7401B5f6d8976F';

  http.Response json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: const <String, String>{'content-type': 'application/json'},
      );

  ChainApi api(http.Response Function() respond) =>
      ChainApi(client: MockClient((_) async => respond()));

  group('Bitcoin parsing', () {
    test('adds confirmed and pending balances', () async {
      final ChainApi client = api(
        () => json(<String, Object>{
          'chain_stats': <String, Object>{
            'funded_txo_sum': 200000000,
            'spent_txo_sum': 50000000,
          },
          'mempool_stats': <String, Object>{
            'funded_txo_sum': 10000000,
            'spent_txo_sum': 0,
          },
        }),
      );

      expect(
        await client.fetchBalance(NetworkCatalog.bitcoin, btcAddress),
        BigInt.from(160000000),
      );
    });

    test('treats a 404 (unknown address) as a zero balance', () async {
      final ChainApi client = api(() => http.Response('Not found', 404));
      expect(
        await client.fetchBalance(NetworkCatalog.bitcoin, btcAddress),
        BigInt.zero,
      );
    });

    test('derives the signed net amount of an incoming transfer', () async {
      final ChainApi client = api(
        () => json(<Object>[
          <String, Object>{
            'txid': 'aaa',
            'fee': 500,
            'status': <String, Object>{
              'confirmed': true,
              'block_time': 1700000000,
            },
            'vin': <Object>[
              <String, Object>{
                'prevout': <String, Object>{
                  'scriptpubkey_address': otherBtc,
                  'value': 100000,
                },
              },
            ],
            'vout': <Object>[
              <String, Object>{
                'scriptpubkey_address': btcAddress,
                'value': 90000,
              },
            ],
          },
        ]),
      );

      final txs =
          await client.fetchTransactions(NetworkCatalog.bitcoin, btcAddress);

      expect(txs, hasLength(1));
      expect(txs.first.isIncoming, isTrue);
      expect(txs.first.amount, BigInt.from(90000));
      expect(txs.first.counterparty, otherBtc);
      expect(txs.first.confirmed, isTrue);
    });

    test('derives a negative amount for an outgoing transfer', () async {
      final ChainApi client = api(
        () => json(<Object>[
          <String, Object>{
            'txid': 'bbb',
            'fee': 800,
            'status': <String, Object>{
              'confirmed': false,
              'block_time': 0,
            },
            'vin': <Object>[
              <String, Object>{
                'prevout': <String, Object>{
                  'scriptpubkey_address': btcAddress,
                  'value': 50000,
                },
              },
            ],
            'vout': <Object>[
              <String, Object>{
                'scriptpubkey_address': otherBtc,
                'value': 49200,
              },
            ],
          },
        ]),
      );

      final txs =
          await client.fetchTransactions(NetworkCatalog.bitcoin, btcAddress);

      expect(txs.first.isIncoming, isFalse);
      expect(txs.first.amount, BigInt.from(-50000));
      expect(txs.first.counterparty, otherBtc);
      expect(txs.first.confirmed, isFalse);
      expect(txs.first.isPending, isTrue);
    });
  });

  group('EVM parsing', () {
    test('reads the wei balance', () async {
      final ChainApi client = api(
        () => json(<String, Object>{'coin_balance': '1500000000000000000'}),
      );

      expect(
        await client.fetchBalance(NetworkCatalog.ethereum, evmAddress),
        BigInt.parse('1500000000000000000'),
      );
    });

    test('parses an outgoing transfer and includes the fee', () async {
      final ChainApi client = api(
        () => json(<String, Object>{
          'items': <Object>[
            <String, Object>{
              'hash': '0xabc',
              'timestamp': '2026-01-02T10:00:00.000000Z',
              'from': <String, Object>{'hash': evmAddress},
              'to': <String, Object>{'hash': otherEvm},
              'value': '1000000000000000000',
              'fee': <String, Object>{'value': '21000000000000'},
              'status': 'ok',
              'block': 123,
              'nonce': 7,
            },
          ],
        }),
      );

      final txs =
          await client.fetchTransactions(NetworkCatalog.ethereum, evmAddress);

      expect(txs, hasLength(1));
      expect(txs.first.isIncoming, isFalse);
      expect(txs.first.counterparty, otherEvm);
      expect(txs.first.amount, BigInt.parse('-1000021000000000000'));
      expect(txs.first.failed, isFalse);
      expect(txs.first.nonce, 7);
    });

    test('flags reverted transactions as failed', () async {
      final ChainApi client = api(
        () => json(<String, Object>{
          'items': <Object>[
            <String, Object>{
              'hash': '0xdef',
              'timestamp': '2026-01-02T10:00:00.000000Z',
              'from': <String, Object>{'hash': otherEvm},
              'to': <String, Object>{'hash': evmAddress},
              'value': '0',
              'fee': <String, Object>{'value': '21000000000000'},
              'status': 'error',
              'block': 124,
            },
          ],
        }),
      );

      final txs =
          await client.fetchTransactions(NetworkCatalog.ethereum, evmAddress);

      expect(txs.first.isIncoming, isTrue);
      expect(txs.first.failed, isTrue);
      expect(txs.first.isPending, isFalse);
    });
  });

  group('EIP-1559 fee data', () {
    ChainApi rpcApi(Object? Function(String method) result) =>
        ChainApi(
          client: MockClient((http.Request request) async {
            final Map<String, Object?> body =
                jsonDecode(request.body) as Map<String, Object?>;
            final String method = body['method'] as String? ?? '';
            return json(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 1,
              'result': result(method),
            });
          }),
        );

    test('adds twice the base fee to the priority tip', () async {
      final ChainApi client = rpcApi((String method) => switch (method) {
            'eth_maxPriorityFeePerGas' => '0x3b9aca00', // 1 gwei
            'eth_getBlockByNumber' => <String, Object?>{
                'baseFeePerGas': '0x3b9aca00', // 1 gwei
              },
            _ => null,
          });

      final ({BigInt baseFee, BigInt maxPriorityFeePerGas}) fees =
          await client.fetchFeeData(NetworkCatalog.ethereum);

      expect(fees.maxPriorityFeePerGas, BigInt.from(1000000000));
      expect(fees.baseFee, BigInt.from(1000000000));
      expect(
        FeePreset.normal.capFor(fees.baseFee, fees.maxPriorityFeePerGas),
        BigInt.from(3000000000),
      );
    });

    test('falls back to the legacy gas price when no 1559 data exists',
        () async {
      final ChainApi client = rpcApi((String method) => switch (method) {
            'eth_maxPriorityFeePerGas' => '0x0',
            'eth_getBlockByNumber' => <String, Object?>{},
            'eth_gasPrice' => '0x4a817c800', // 20 gwei
            _ => null,
          });

      final ({BigInt baseFee, BigInt maxPriorityFeePerGas}) fees =
          await client.fetchFeeData(NetworkCatalog.ethereum);

      expect(fees.maxPriorityFeePerGas, BigInt.parse('20000000000'));
      expect(fees.baseFee, BigInt.zero);
    });
  });

  group('errors', () {
    test('throws a ChainApiException on server errors', () async {
      final ChainApi client = api(() => http.Response('boom', 500));

      expect(
        () => client.fetchBalance(NetworkCatalog.ethereum, evmAddress),
        throwsA(isA<ChainApiException>()),
      );
    });

    test('returns a null fee estimate instead of inventing one', () async {
      final ChainApi client = api(() => http.Response('boom', 500));
      expect(await client.fetchFeeEstimate(NetworkCatalog.bitcoin), isNull);
    });
  });
}
