import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto_wallet/core/crypto/base58.dart';
import 'package:crypto_wallet/core/crypto/slip10.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/address_deriver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String hexOf(Uint8List bytes) => hex.encode(bytes);

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String secondMnemonic =
      'legal winner thank year wave sausage worth useful legal winner thank '
      'yellow';

  /// The Phantom-compatible Solana address for [mnemonic].
  const String address = 'HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk';

  group('Base58', () {
    test('keeps leading zeros as 1s', () {
      expect(Base58.encode(Uint8List.fromList(<int>[0, 0, 1])), '112');
    });

    test('encodes the reference public key', () {
      final Uint8List publicKey = Uint8List.fromList(hex.decode(
        'f036276246a75b9de3349ed42b15e232f6518fc20f5fcd4f1d64e81f9bd258f7',
      ));
      expect(Base58.encode(publicKey), address);
    });
  });

  group("SLIP-0010 (ed25519, m/44'/501'/0'/0')", () {
    test('matches the reference seed', () {
      final Uint8List seed = AddressDeriver.seedFromMnemonic(mnemonic);
      expect(
        hexOf(Slip10.deriveEd25519Seed(seed, Slip10.solanaPath)),
        '37df573b3ac4ad5b522e064e25b63ea16bcbe79d449e81a0268d1047948bb445',
      );
    });
  });

  group('Solana address derivation', () {
    test('matches the Phantom-compatible address', () {
      final Uint8List seed = AddressDeriver.seedFromMnemonic(mnemonic);
      expect(AddressDeriver.solanaAddressFromSeed(seed), address);
    });

    test('matches a second known vector', () {
      final Uint8List seed = AddressDeriver.seedFromMnemonic(secondMnemonic);
      expect(
        AddressDeriver.solanaAddressFromSeed(seed),
        'BLeUXTx9thHGT7VJUtF9vHEmfMDgW1nnKZ9UVer2CoLX',
      );
    });

    test('different phrases produce different addresses', () {
      expect(
        AddressDeriver.solanaAddressFromSeed(
          AddressDeriver.seedFromMnemonic(mnemonic),
        ),
        isNot(
          AddressDeriver.solanaAddressFromSeed(
            AddressDeriver.seedFromMnemonic(secondMnemonic),
          ),
        ),
      );
    });
  });

  group('ChainApi JSON-RPC', () {
    /// Responds to every call the two JSON-RPC networks make.
    MockClient client() => MockClient((http.Request request) async {
          final String body = request.body;
          Object? result;

          if (body.contains('eth_getBalance')) {
            result = '0xde0b6b3a7640000'; // 1 BNB
          } else if (body.contains('eth_gasPrice')) {
            result = '0x3b9aca00'; // 1 gwei
          } else if (body.contains('getBalance')) {
            result = <String, Object?>{
              'context': <String, Object?>{'slot': 1},
              'value': 1500000000,
            };
          } else if (body.contains('getSignaturesForAddress')) {
            result = <Object?>[
              <String, Object?>{
                'signature': 'SIG1',
                'blockTime': 1700000000,
                'err': null,
              },
            ];
          } else if (body.contains('getTransaction')) {
            result = <String, Object?>{
              'blockTime': 1700000000,
              'meta': <String, Object?>{
                'err': null,
                'fee': 10000,
                'preBalances': <Object?>[1000000000, 500000000],
                'postBalances': <Object?>[990000000, 510000000],
              },
              'transaction': <String, Object?>{
                'message': <String, Object?>{
                  'accountKeys': <Object?>['FEE_PAYER', address],
                },
              },
            };
          }

          return http.Response(
            jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 1,
              'result': result,
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        });

    test('BNB balance comes from eth_getBalance', () async {
      final ChainApi api = ChainApi(client: client());
      expect(
        await api.fetchBalance(NetworkCatalog.bnb, address),
        BigInt.from(1000000000000000000),
      );
    });

    test('BNB reports no activity (no key-less history index)', () async {
      final ChainApi api = ChainApi(client: client());
      expect(await api.fetchTransactions(NetworkCatalog.bnb, address), isEmpty);
    });

    test('BNB fee estimate uses eth_gasPrice × 21,000', () async {
      final ChainApi api = ChainApi(client: client());
      expect(
        await api.fetchFeeEstimate(NetworkCatalog.bnb),
        BigInt.from(1000000000) * BigInt.from(21000),
      );
    });

    test('Solana balance comes from getBalance', () async {
      final ChainApi api = ChainApi(client: client());
      expect(
        await api.fetchBalance(NetworkCatalog.solana, address),
        BigInt.from(1500000000),
      );
    });

    test('Solana parses an incoming transfer from the balance delta', () async {
      final ChainApi api = ChainApi(client: client());
      final List<ChainTransaction> txs =
          await api.fetchTransactions(NetworkCatalog.solana, address);

      expect(txs, hasLength(1));
      expect(txs.first.isIncoming, isTrue);
      expect(txs.first.amount, BigInt.from(10000000));
      expect(txs.first.fee, BigInt.zero);
      expect(txs.first.counterparty, 'FEE_PAYER');
      expect(txs.first.confirmed, isTrue);
      expect(txs.first.failed, isFalse);
    });

    test('Solana fee estimate is the flat 5,000 lamports', () async {
      final ChainApi api = ChainApi(client: client());
      expect(
        await api.fetchFeeEstimate(NetworkCatalog.solana),
        BigInt.from(5000),
      );
    });
  });
}
