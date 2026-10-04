import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto_wallet/core/crypto/slip10.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/address_deriver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String secondMnemonic =
      'legal winner thank year wave sausage worth useful legal winner thank '
      'yellow';

  /// The Petra-compatible Aptos address for [mnemonic].
  const String address =
      '0xeb663b681209e7087d681c5d3eed12aaa8e1915e7c87794542c3f96e94b3d3bf';

  /// Short (canonical) form without the `0x` prefix or leading zeros.
  const String shortAddress =
      'eb663b681209e7087d681c5d3eed12aaa8e1915e7c87794542c3f96e94b3d3bf';

  /// Two user transactions (one out, one in) plus an entry the parser skips.
  final List<Object?> transactions = <Object?>[
    <String, Object?>{'type': 'block_metadata_transaction', 'hash': '0xBLOCK'},
    <String, Object?>{
      'type': 'user_transaction',
      'hash': '0xOUT',
      'sender': address,
      'success': true,
      'timestamp': '1700000000000000',
      'gas_used': '400',
      'gas_unit_price': '100',
      'payload': <String, Object?>{
        'function': '0x1::aptos_account::transfer',
        'arguments': <Object?>['0x1234', '50000000'],
      },
    },
    <String, Object?>{
      'type': 'user_transaction',
      'hash': '0xIN',
      'sender': '0xabcd',
      'success': true,
      'timestamp': '1700000100000000',
      'gas_used': '400',
      'gas_unit_price': '100',
      'payload': <String, Object?>{
        'function': '0x1::aptos_account::transfer',
        // The recipient arrives in short form — the parser must canonicalise.
        'arguments': <Object?>[shortAddress, '25000000'],
      },
    },
  ];

  group("SLIP-0010 (ed25519, m/44'/637'/0'/0'/0')", () {
    test('matches the reference seed', () {
      final Uint8List seed = AddressDeriver.seedFromMnemonic(mnemonic);
      expect(
        hex.encode(Slip10.deriveEd25519Seed(seed, Slip10.aptosPath)),
        'cc92c0eaf80206d817f150e21917f797e49cf644a33ac514de3c316baa2f1bf5',
      );
    });
  });

  group('Aptos address derivation', () {
    test('matches the Petra-compatible authentication key', () {
      final Uint8List seed = AddressDeriver.seedFromMnemonic(mnemonic);
      expect(AddressDeriver.aptosAddressFromSeed(seed), address);
    });

    test('matches a second known vector', () {
      final Uint8List seed = AddressDeriver.seedFromMnemonic(secondMnemonic);
      expect(
        AddressDeriver.aptosAddressFromSeed(seed),
        '0xa3a54a136006c8ec675ab183930bcdf9a8c19e3c71bc1fa2ad5539ff3bb605f2',
      );
    });

    test('is a 32-byte hex string', () {
      final Uint8List seed = AddressDeriver.seedFromMnemonic(mnemonic);
      final String value = AddressDeriver.aptosAddressFromSeed(seed);
      expect(value, startsWith('0x'));
      expect(value.length, 66);
    });
  });

  group('ChainApi (Aptos REST)', () {
    MockClient client() => MockClient((http.Request request) async {
          final String url = request.url.toString();

          if (url.contains('estimate_gas_price')) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'gas_estimate': 100,
                'prioritized_gas_estimate': 150,
              }),
              200,
            );
          }
          if (url.contains('balance')) {
            // A bare number of octas, exactly like the real node.
            return http.Response('123456789', 200);
          }
          if (url.contains('transactions')) {
            return http.Response(jsonEncode(transactions), 200);
          }
          return http.Response('{}', 404);
        });

    test('balance is read as octas', () async {
      final ChainApi api = ChainApi(client: client());
      expect(
        await api.fetchBalance(NetworkCatalog.aptos, address),
        BigInt.from(123456789),
      );
    });

    test('fee estimate uses gas_estimate × 1,000', () async {
      final ChainApi api = ChainApi(client: client());
      expect(
        await api.fetchFeeEstimate(NetworkCatalog.aptos),
        BigInt.from(100000),
      );
    });

    test('account without a balance resource reports zero', () async {
      final ChainApi api = ChainApi(
        client: MockClient((_) async => http.Response('not found', 404)),
      );
      expect(
        await api.fetchBalance(NetworkCatalog.aptos, address),
        BigInt.zero,
      );
    });

    test('parses outgoing and incoming transfers', () async {
      final ChainApi api = ChainApi(client: client());
      final List<ChainTransaction> txs =
          await api.fetchTransactions(NetworkCatalog.aptos, address);

      expect(txs, hasLength(2));

      final ChainTransaction outgoing = txs
          .firstWhere((ChainTransaction t) => t.hash == '0xOUT');
      expect(outgoing.isIncoming, isFalse);
      // Sender pays amount + fee: 50,000,000 + (400 × 100).
      expect(outgoing.amount, BigInt.from(-50040000));
      expect(outgoing.fee, BigInt.from(40000));
      expect(outgoing.counterparty, '0x1234');

      final ChainTransaction incoming = txs
          .firstWhere((ChainTransaction t) => t.hash == '0xIN');
      expect(incoming.isIncoming, isTrue);
      expect(incoming.amount, BigInt.from(25000000));
      expect(incoming.fee, BigInt.zero);
      expect(incoming.counterparty, '0xabcd');
    });

    test('newest transaction comes first', () async {
      final ChainApi api = ChainApi(client: client());
      final List<ChainTransaction> txs =
          await api.fetchTransactions(NetworkCatalog.aptos, address);
      expect(txs.first.hash, '0xIN');
    });
  });
}
