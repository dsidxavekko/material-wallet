// Manual verification of ENS resolution against a live Ethereum node.
//
// Run: dart run tool/verify_ens.dart
//
// Sends the same Universal Resolver `eth_call` the Send screen builds
// (`Ens.resolveCallData`) for `vitalik.eth` and decodes it with
// `Ens.decodeResolveResult`, then compares the answer with the address that name
// has held for years. A name that does not exist is the control: the call must
// revert (or decode to nothing), never return an address.
//
// Read-only: one `eth_call`, nothing is signed or sent.
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:crypto_wallet/core/crypto/ens.dart';
import 'package:http/http.dart' as http;

const String _node = 'https://ethereum-rpc.publicnode.com';
const String _name = 'vitalik.eth';
const String _expected = '0xd8da6bf26964af9d7eed9e03e53415d37aa96045';
const String _missing = 'this-name-is-not-registered-9f3a1c.eth';

Future<String?> _resolve(http.Client client, String name) async {
  final http.Response response = await client.post(
    Uri.parse(_node),
    headers: <String, String>{'Content-Type': 'application/json'},
    body: jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'eth_call',
      'params': <Object?>[
        <String, Object?>{
          'to': Ens.universalResolver,
          'data': Ens.resolveCallData(Ens.normalize(name)!),
        },
        'latest',
      ],
    }),
  );
  final Map<String, Object?> body =
      jsonDecode(response.body) as Map<String, Object?>;
  final Object? result = body['result'];
  if (result is! String) {
    print('  node answered: ${body['error']}');
    return null;
  }
  return Ens.decodeResolveResult(result);
}

Future<void> main() async {
  final http.Client client = http.Client();
  try {
    final String? resolved = await _resolve(client, _name);
    print('$_name  ->  $resolved');
    final String? none = await _resolve(client, _missing);
    print('$_missing  ->  $none');

    print('');
    if (resolved?.toLowerCase() == _expected && none == null) {
      print(
        'PASS: the known name resolved to the expected address and the '
        'unregistered one to nothing.',
      );
    } else {
      exitCode = 1;
      print(
        'FAIL: expected $_expected for $_name and nothing for the control.',
      );
    }
  } finally {
    client.close();
  }
}
