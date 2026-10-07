// Manual verification of the EIP-1559 signing path against a live node.
//
// Run: dart run tool/verify_eip1559.dart
//
// Signs a type-2 transfer offline and hands it to a real Sepolia node. The
// throwaway key holds no funds, so the node rejects the transfer for
// `insufficient funds` — which still proves the node decoded the RLP, recovered
// the sender and accepted the signature. A malformed payload is sent as a
// control to show the failure looks different (a decode error).
//
// No funds are spent and nothing is mined.
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto_wallet/core/crypto/hashing.dart';
import 'package:crypto_wallet/data/wallet/evm_signer.dart';
import 'package:convert/convert.dart';
import 'package:http/http.dart' as http;

const String _rpc = 'https://ethereum-sepolia-rpc.publicnode.com';
const int _expectedChainId = 11155111;

Future<Object?> _result(
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
  final Map<String, Object?> body =
      jsonDecode(response.body) as Map<String, Object?>;
  final Object? error = body['error'];
  if (error != null) {
    throw StateError('$method failed: $error');
  }
  return body['result'];
}

/// The node's error object for `eth_sendRawTransaction`, or `null` on success.
Future<Object?> _sendRaw(http.Client client, String raw) async {
  final http.Response response = await client.post(
    Uri.parse(_rpc),
    headers: const <String, String>{'Content-Type': 'application/json'},
    body: jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'eth_sendRawTransaction',
      'params': <Object?>[raw],
    }),
  );
  final Map<String, Object?> body =
      jsonDecode(response.body) as Map<String, Object?>;
  return body['error'] ?? body['result'];
}

BigInt _hex(String value) =>
    BigInt.parse(value.substring(2), radix: 16);

Future<void> main() async {
  final http.Client client = http.Client();
  try {
    final int chainId = _hex(
      await _result(client, 'eth_chainId', const <Object?>[]) as String,
    ).toInt();
    print('chain id      : $chainId (${chainId == _expectedChainId ? 'ok' : 'WRONG'})');

    final Map<String, Object?> block = await _result(
      client,
      'eth_getBlockByNumber',
      const <Object?>['latest', false],
    ) as Map<String, Object?>;
    final BigInt baseFee = _hex(block['baseFeePerGas']! as String);

    BigInt priority;
    try {
      priority = _hex(
        await _result(
              client,
              'eth_maxPriorityFeePerGas',
              const <Object?>[],
            ) as String,
      );
    } catch (_) {
      priority = baseFee ~/ BigInt.from(10);
    }
    if (priority == BigInt.zero) {
      priority = BigInt.from(1000000000);
    }
    final BigInt maxFee = baseFee * BigInt.two + priority;

    print('base fee      : ${baseFee / BigInt.from(1000000000)} gwei');
    print('priority tip  : ${priority / BigInt.from(1000000000)} gwei');
    print('fee cap       : ${maxFee / BigInt.from(1000000000)} gwei');

    // A deterministic throwaway key — no funds, so nothing can be spent.
    final Uint8List key =
        Uint8List.fromList(List<int>.generate(32, (int i) => (i * 7 + 13) % 256));

    const String to = '0x1111111111111111111111111111111111111111';
    final String raw = EvmSigner.signEip1559Transfer(
      privateKey: key,
      nonce: 0,
      maxPriorityFeePerGas: priority,
      maxFeePerGas: maxFee,
      gasLimit: BigInt.from(21000),
      to: to,
      value: BigInt.zero,
      chainId: chainId,
    );
    print('raw tx        : 0x$raw (${raw.length ~/ 2} bytes)');
    print(
      'tx hash       : 0x${hex.encode(Hashing.keccak256(Uint8List.fromList(hex.decode(raw))))}',
    );

    // Invariant: the node must reject the well-formed tx for lack of funds, not
    // for a decode/signature problem.
    final Object? signedError = await _sendRaw(client, '0x$raw');
    print('');
    print('node response : $signedError');

    final bool decoded = signedError is Map &&
        '${signedError['message']}'.toLowerCase().contains('insufficient funds');

    // Control: a deliberately malformed payload fails differently.
    final Object? controlError = await _sendRaw(client, '0x02ff');
    print('control (bad) : $controlError');

    print('');
    if (decoded) {
      print('PASS: the node decoded the type-2 transaction and recovered the '
          'sender (rejected only for insufficient funds).');
    } else {
      print('FAIL: expected an "insufficient funds" rejection, got the above.');
    }
  } finally {
    client.close();
  }
}
