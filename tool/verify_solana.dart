// Manual verification of the Solana signing path against a live cluster.
//
// Run: dart run tool/verify_solana.dart
//
// Signs a SOL transfer offline with a throwaway key and asks Solana Devnet to
// *simulate* it with signature verification on (`sigVerify: true`). The key
// holds no funds, so the cluster rejects the transfer for the fee payer not
// existing (`AccountNotFound`) — which still proves it decoded the message,
// found the blockhash valid and accepted the ed25519 signature. A control with
// one flipped signature byte must fail differently (a signature failure).
//
// Nothing is sent and nothing is spent.
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto_wallet/core/crypto/base58.dart';
import 'package:crypto_wallet/data/wallet/solana_signer.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:http/http.dart' as http;

const String _rpc = 'https://api.devnet.solana.com';

Future<Map<String, Object?>> _call(
  http.Client client,
  String method,
  List<Object?> params,
) async {
  final http.Response response = await client.post(
    Uri.parse(_rpc),
    headers: const <String, String>{'Content-Type': 'application/json'},
    body: jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
      'params': params,
    }),
  );
  return jsonDecode(response.body) as Map<String, Object?>;
}

Future<void> main() async {
  final http.Client client = http.Client();
  try {
    final Uint8List seed =
        Uint8List.fromList(List<int>.generate(32, (int i) => (i * 5 + 3) % 256));
    final ed.PrivateKey key = ed.newKeyFromSeed(seed);
    final Uint8List from = Uint8List.fromList(ed.public(key).bytes);
    final Uint8List to = Uint8List.fromList(List<int>.generate(32, (int i) => i + 90));

    final Map<String, Object?> hashResponse = await _call(
      client,
      'getLatestBlockhash',
      const <Object?>[
        <String, Object?>{'commitment': 'confirmed'},
      ],
    );
    final String blockhash =
        ((hashResponse['result']! as Map)['value'] as Map)['blockhash']! as String;
    print('from          : ${Base58.encode(from)}');
    print('blockhash     : $blockhash');

    final Uint8List message = SolanaSigner.transferMessage(
      from: from,
      to: to,
      lamports: BigInt.from(1000000),
      recentBlockhash: Base58.decode(blockhash)!,
    );
    final Uint8List tx =
        SolanaSigner.signTransaction(privateSeed: seed, message: message);

    Future<Map<String, Object?>> simulate(Uint8List bytes) => _call(
          client,
          'simulateTransaction',
          <Object?>[
            base64Encode(bytes),
            const <String, Object?>{
              'encoding': 'base64',
              'sigVerify': true,
              'commitment': 'confirmed',
            },
          ],
        );

    final Map<String, Object?> good = await simulate(tx);
    print('');
    print('simulation    : ${jsonEncode(good['result'] ?? good['error'])}');

    final Uint8List tampered = Uint8List.fromList(tx);
    tampered[10] ^= 0xff; // flip a byte inside the signature
    final Map<String, Object?> bad = await simulate(tampered);
    print('control (bad) : ${jsonEncode(bad['result'] ?? bad['error'])}');

    final String goodText = jsonEncode(good['result'] ?? good['error']);
    final String badText = jsonEncode(bad['result'] ?? bad['error']);
    print('');
    if (goodText.contains('AccountNotFound') &&
        !goodText.toLowerCase().contains('signature') &&
        badText.toLowerCase().contains('signature')) {
      print('PASS: the cluster accepted the signature and rejected only the '
          'unfunded fee payer; the tampered copy failed signature verification.');
    } else {
      print('FAIL: expected AccountNotFound for the real signature and a '
          'signature failure for the tampered one.');
    }
  } finally {
    client.close();
  }
}
