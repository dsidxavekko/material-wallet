// Manual verification of Aptos token transfers against mainnet.
//
// Run: dart run tool/verify_aptos_token.dart
//
// Builds the real token-transfer transactions (`AptosSigner.rawTokenTransfer`)
// for two accounts that hold USDC today — one a *fungible asset*, one a legacy
// *coin* — and asks the node to **simulate** them with an all-zero signature.
// The sender's public key is read from its own earlier transaction (and checked
// against its authentication key), so the node's prologue accepts the sender and
// really executes the transfer against live state. Nothing is signed, sent or
// spent: no key of ours is involved at all.
//
// Also checks the indexer listing the wallet relies on, and runs controls
// (an asset that does not exist, more than the balance) that must fail.
//
// Exits non-zero on any FAIL.
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto_wallet/core/crypto/hashing.dart';
import 'package:crypto_wallet/data/wallet/aptos_signer.dart';
import 'package:http/http.dart' as http;

const String _node = 'https://fullnode.mainnet.aptoslabs.com/v1';
const String _indexer = 'https://api.mainnet.aptoslabs.com/v1/graphql';

const String _faUsdc =
    '0xbae207659db88bea0cbead6da0ed00aac12edcdda169e591cd41c94180b46f3b';
const String _coinUsdc =
    '0xf22bede237a07e121b56d91a491eb7bcdfd1f5907926a9e58338f964a01b17fa::asset::USDC';

int _failures = 0;

void _check(String name, bool ok, [String detail = '']) {
  print('${ok ? 'PASS' : 'FAIL'}  $name${detail.isEmpty ? '' : ' — $detail'}');
  if (!ok) _failures++;
}

Future<Object?> _get(http.Client c, String path) async {
  final http.Response r = await c.get(
    Uri.parse('$_node$path'),
    headers: const <String, String>{'Accept': 'application/json'},
  );
  return jsonDecode(r.body);
}

Future<List<Map<String, Object?>>> _holders(
  http.Client c,
  String asset,
) async {
  final http.Response r = await c.post(
    Uri.parse(_indexer),
    headers: const <String, String>{'Content-Type': 'application/json'},
    body: jsonEncode(<String, Object?>{
      'query': 'query { current_fungible_asset_balances(where: {asset_type: '
          '{_eq: "$asset"}, amount: {_gt: "2000000"}}, limit: 40, '
          'order_by: {amount: desc}) { owner_address amount } }',
    }),
  );
  final Map<String, Object?> body = jsonDecode(r.body) as Map<String, Object?>;
  return ((body['data']! as Map)['current_fungible_asset_balances']! as List)
      .cast<Map<String, Object?>>();
}

/// An account that holds [asset], whose key we can read from its own history.
Future<({String address, Uint8List publicKey, int sequence, BigInt amount})?>
    _findSender(http.Client c, String asset) async {
  for (final Map<String, Object?> holder in await _holders(c, asset)) {
    final String address = holder['owner_address']! as String;
    try {
      final Map<String, Object?> account =
          (await _get(c, '/accounts/$address'))! as Map<String, Object?>;
      final List<dynamic> txs =
          (await _get(c, '/accounts/$address/transactions?limit=5'))! as List<dynamic>;
      for (final dynamic t in txs) {
        final Map<String, Object?> tx = (t as Map).cast<String, Object?>();
        final Object? sig = tx['signature'];
        if (sig is Map &&
            sig['type'] == 'ed25519_signature' &&
            tx['sender'] == address) {
          final Uint8List key = Uint8List.fromList(
            hex.decode((sig['public_key']! as String).substring(2)),
          );
          final String auth = '0x${hex.encode(Hashing.sha3_256(Uint8List.fromList(<int>[...key, 0])))}';
          if (auth == account['authentication_key']) {
            return (
              address: address,
              publicKey: key,
              sequence: int.parse('${account['sequence_number']}'),
              amount: BigInt.parse('${holder['amount']}'),
            );
          }
        }
      }
    } catch (_) {
      // try the next holder
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return null;
}

Future<Map<String, Object?>> _simulate(
  http.Client c,
  Uint8List signedWithZeroSignature,
) async {
  final http.Response r = await c.post(
    Uri.parse('$_node/transactions/simulate'),
    headers: const <String, String>{
      'Content-Type': 'application/x.aptos.signed_transaction+bcs',
      'Accept': 'application/json',
    },
    body: signedWithZeroSignature,
  );
  final Object? body = jsonDecode(r.body);
  if (body is List && body.isNotEmpty) {
    return (body.first as Map).cast<String, Object?>();
  }
  return <String, Object?>{'success': false, 'vm_status': r.body};
}

Future<void> main() async {
  final http.Client client = http.Client();
  try {
    final Map<String, Object?> ledger =
        (await _get(client, ''))! as Map<String, Object?>;
    final int chainId = (ledger['chain_id']! as num).toInt();
    final int now = int.parse('${ledger['ledger_timestamp']}') ~/ 1000000;
    final Uint8List recipient =
        Uint8List.fromList(List<int>.generate(32, (int i) => (i * 7 + now) % 256));

    Future<Map<String, Object?>> run({
      required ({String address, Uint8List publicKey, int sequence, BigInt amount}) from,
      required String asset,
      required BigInt amount,
    }) async {
      final Uint8List raw = AptosSigner.rawTokenTransfer(
        sender: AptosSigner.addressBytes(from.address),
        sequenceNumber: from.sequence,
        assetType: asset,
        to: recipient,
        amount: amount,
        maxGasAmount: 100000,
        gasUnitPrice: 100,
        expirationTimestampSecs: now + 600,
        chainId: chainId,
      );
      return _simulate(
        client,
        AptosSigner.simulationTransaction(
          rawTransaction: raw,
          publicKey: from.publicKey,
        ),
      );
    }

    final fa = await _findSender(client, _faUsdc);
    _check('found a USDC (fungible asset) holder to simulate from', fa != null);
    if (fa != null) {
      final r = await run(from: fa, asset: _faUsdc, amount: BigInt.from(1));
      _check('fungible asset → a brand-new address', r['success'] == true,
          '${r['vm_status']}');
      final tooMuch =
          await run(from: fa, asset: _faUsdc, amount: fa.amount + BigInt.one);
      _check('control: more than the balance fails', tooMuch['success'] == false,
          '${tooMuch['vm_status']}');
      final noAsset = await run(
        from: fa,
        asset: '0x${'ab' * 32}',
        amount: BigInt.one,
      );
      _check('control: an asset that does not exist fails',
          noAsset['success'] == false, '${noAsset['vm_status']}');
    }

    final coin = await _findSender(client, _coinUsdc);
    _check('found a USDC (legacy coin) holder to simulate from', coin != null);
    if (coin != null) {
      final r = await run(from: coin, asset: _coinUsdc, amount: BigInt.from(1));
      _check('legacy coin → a brand-new address', r['success'] == true,
          '${r['vm_status']}');
      final tooMuch =
          await run(from: coin, asset: _coinUsdc, amount: coin.amount + BigInt.one);
      _check('control: more than the balance fails', tooMuch['success'] == false,
          '${tooMuch['vm_status']}');
    }
  } finally {
    client.close();
  }

  if (_failures > 0) {
    print('$_failures check(s) failed.');
    exit(1);
  }
  print('All checks passed. Nothing was sent.');
}
