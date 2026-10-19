// Manual verification of the Aptos BCS / signing path against a live node.
//
// Run: dart run tool/verify_aptos.dart
//
// Builds an `aptos_account::transfer` transaction with a throwaway key and
// POSTs it to the Aptos *testnet* `/transactions/simulate` endpoint (which
// executes nothing and needs an all-zero signature). The account does not
// exist, so the VM answers `SENDING_ACCOUNT_DOES_NOT_EXIST` — which proves the
// node parsed the BCS payload and chain id. A malformed body is sent as a
// control; it must be refused at the parse stage instead.
//
// Nothing is submitted and nothing is spent.
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto_wallet/data/wallet/aptos_signer.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:http/http.dart' as http;

const String _node = 'https://fullnode.testnet.aptoslabs.com/v1';

Future<http.Response> _simulate(http.Client client, Uint8List body) =>
    client.post(
      Uri.parse('$_node/transactions/simulate'),
      headers: const <String, String>{
        'Content-Type': 'application/x.aptos.signed_transaction+bcs',
      },
      body: body,
    );

Future<void> main() async {
  final http.Client client = http.Client();
  try {
    final Map<String, Object?> ledger = jsonDecode(
      (await client.get(Uri.parse(_node))).body,
    ) as Map<String, Object?>;
    final int chainId = (ledger['chain_id']! as num).toInt();
    final int now = int.parse('${ledger['ledger_timestamp']}') ~/ 1000000;
    print('chain id      : $chainId');

    final Uint8List seed =
        Uint8List.fromList(List<int>.generate(32, (int i) => (i * 11 + 5) % 256));
    final ed.PrivateKey key = ed.newKeyFromSeed(seed);
    final Uint8List publicKey = Uint8List.fromList(ed.public(key).bytes);
    // Auth key = sha3_256(pubkey ‖ 0x00) is the address; any 32 bytes work for
    // an account that must not exist.
    final Uint8List sender = Uint8List.fromList(List<int>.generate(32, (int i) => i + 1));

    final Uint8List raw = AptosSigner.rawTransfer(
      sender: sender,
      sequenceNumber: 0,
      to: Uint8List.fromList(List<int>.generate(32, (int i) => 200 - i)),
      amount: BigInt.from(1000),
      maxGasAmount: 2000,
      gasUnitPrice: 100,
      expirationTimestampSecs: now + 600,
      chainId: chainId,
    );
    final http.Response good = await _simulate(
      client,
      AptosSigner.simulationTransaction(
        rawTransaction: raw,
        publicKey: publicKey,
      ),
    );
    print('');
    print('simulation    : HTTP ${good.statusCode} ${good.body}');

    final http.Response bad = await _simulate(client, Uint8List.fromList(<int>[1, 2, 3]));
    print('control (bad) : HTTP ${bad.statusCode} ${bad.body}');

    print('');
    if (good.body.contains('SENDING_ACCOUNT_DOES_NOT_EXIST') &&
        bad.statusCode >= 400) {
      print('PASS: the node parsed the transaction (rejected only the missing '
          'sender); the malformed control failed to parse.');
    } else {
      print('FAIL: expected SENDING_ACCOUNT_DOES_NOT_EXIST for the real '
          'transaction and a parse error for the control.');
    }
  } finally {
    client.close();
  }
}
