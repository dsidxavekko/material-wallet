// Manual verification of the SPL token transfer against Solana mainnet.
//
// Run: dart run tool/verify_spl.dart
//
// Builds the real transfer messages (`SplTokenSigner`) between existing,
// funded mainnet accounts and asks a node to *simulate* them with
// `sigVerify: false` and `replaceRecentBlockhash`, so no key is needed and
// nothing can be sent: the cluster executes the instructions against real
// state and reports whether they would succeed.
//
// What it proves, which no vector can: that the Token and Associated Token
// Account programs accept the account order, the TransferChecked layout and
// the idempotent account creation this wallet produces.
//
//  1. USDC to a brand-new wallet   → creates its associated account, transfers.
//  2. USDC to a wallet that already has a USDC account → plain transfer.
//  3. Control: more than the sender holds → must fail with the program's
//     "insufficient funds" error, proving the simulation really executes.
//
// Exits non-zero on any FAIL.
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto_wallet/core/crypto/base58.dart';
import 'package:crypto_wallet/data/wallet/solana_signer.dart';
import 'package:crypto_wallet/data/wallet/spl_token_signer.dart';
import 'package:http/http.dart' as http;

const String _rpc = 'https://api.mainnet-beta.solana.com';
const String _usdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

Future<Object?> _call(http.Client c, String method, List<Object?> params) async {
  final http.Response r = await c.post(
    Uri.parse(_rpc),
    headers: const <String, String>{'Content-Type': 'application/json'},
    body: jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
      'params': params,
    }),
  );
  final Map<String, Object?> body = jsonDecode(r.body) as Map<String, Object?>;
  if (body['error'] != null) {
    throw StateError('$method: ${body['error']}');
  }
  return body['result'];
}

Map<String, Object?> _map(Object? o) => (o as Map).cast<String, Object?>();

Future<void> main() async {
  final http.Client client = http.Client();
  int failures = 0;
  void check(String name, bool ok, [String detail = '']) {
    print('${ok ? 'PASS' : 'FAIL'}  $name${detail.isEmpty ? '' : ' — $detail'}');
    if (!ok) failures++;
  }

  try {
    // Two large, long-lived exchange wallets that hold USDC and SOL. The script
    // only *reads* them and simulates; it never signs for them. If one is ever
    // emptied or closed, replace it with another funded system-owned wallet.
    const List<({String owner, String account})> candidates =
        <({String owner, String account})>[
      (
        owner: 'H8sMJSCQxfKiFTCfDR3DUMLPwcRbM61LGFJ8N4dK3WjS',
        account: '7dQmths1cyCQ4xaC5KcVfXz4BvVWtnHc3hcgnfnE1PBx',
      ),
      (
        owner: 'GJRs4FwHtemZ5ZE9x3FNvJ8TMwitKTh21yxdRPqn7npE',
        account: 'DeqZejBFrRwWraY4g4besYmibTY1QcV1Fcg6VfoEvn4T',
      ),
    ];
    final List<({String account, String owner, BigInt amount})> holders =
        <({String account, String owner, BigInt amount})>[];
    for (final c in candidates) {
      final Map<String, Object?> info = _map(_map(await _call(
        client,
        'getAccountInfo',
        <Object?>[c.account, <String, Object?>{'encoding': 'jsonParsed'}],
      ))['value']);
      final Map<String, Object?> parsed =
          _map(_map(_map(info['data'])['parsed'])['info']);
      final BigInt amount =
          BigInt.parse(_map(parsed['tokenAmount'])['amount']! as String);
      final num lamports =
          _map(await _call(client, 'getBalance', <Object?>[c.owner]))['value']!
              as num;
      final Object? ownerAccount = _map(await _call(
        client,
        'getAccountInfo',
        <Object?>[c.owner, <String, Object?>{'encoding': 'base64'}],
      ))['value'];
      final String ownerProgram =
          ownerAccount is Map ? ownerAccount['owner'] as String? ?? '' : '';
      check(
        'sender ${c.owner.substring(0, 6)}… is funded and system-owned',
        parsed['owner'] == c.owner &&
            lamports > 50000000 &&
            amount > BigInt.from(1000000) &&
            ownerProgram == '11111111111111111111111111111111',
      );
      holders.add((account: c.account, owner: c.owner, amount: amount));
    }

    final Uint8List mint = Base58.decode(_usdc)!;
    final String hash = _map(_map(
      await _call(client, 'getLatestBlockhash', <Object?>[]),
    )['value'])['blockhash']! as String;
    final Uint8List blockhash = Base58.decode(hash)!;

    Future<Map<String, Object?>> simulate(Uint8List message) async {
      final Uint8List tx = Uint8List.fromList(<int>[
        ...SolanaSigner.compactU16(1),
        ...Uint8List(64),
        ...message,
      ]);
      return _map(_map(await _call(client, 'simulateTransaction', <Object?>[
        base64Encode(tx),
        <String, Object?>{
          'encoding': 'base64',
          'sigVerify': false,
          'replaceRecentBlockhash': true,
          'commitment': 'confirmed',
        },
      ]))['value']);
    }

    final holder = holders[0];
    final Uint8List owner = Base58.decode(holder.owner)!;
    final Uint8List source = Base58.decode(holder.account)!;

    // 1. brand-new recipient → the account is created.
    final Uint8List fresh = Uint8List.fromList(
      List<int>.generate(32, (int i) => (i * 11 + DateTime.now().millisecond) % 256),
    );
    final Map<String, Object?> createRun = await simulate(
      SplTokenSigner.transferMessage(
        owner: owner,
        source: source,
        recipientOwner: fresh,
        mint: mint,
        program: SplTokenProgram.token,
        amount: BigInt.from(1000),
        decimals: 6,
        createDestination: true,
        recentBlockhash: blockhash,
      ),
    );
    check('USDC to a new wallet (creates its token account)',
        createRun['err'] == null, '${createRun['err'] ?? 'accepted'}');

    // 2. recipient with an existing USDC account → plain transfer.
    final Uint8List existing = Base58.decode(holders[1].owner)!;
    final Map<String, Object?> plainRun = await simulate(
      SplTokenSigner.transferMessage(
        owner: owner,
        source: source,
        recipientOwner: existing,
        mint: mint,
        program: SplTokenProgram.token,
        amount: BigInt.from(1000),
        decimals: 6,
        createDestination: false,
        recentBlockhash: blockhash,
      ),
    );
    check('USDC to a wallet that already has a USDC account',
        plainRun['err'] == null, '${plainRun['err'] ?? 'accepted'}');

    // 2b. the same recipient with the create instruction: idempotent no-op.
    final Map<String, Object?> idempotentRun = await simulate(
      SplTokenSigner.transferMessage(
        owner: owner,
        source: source,
        recipientOwner: existing,
        mint: mint,
        program: SplTokenProgram.token,
        amount: BigInt.from(1000),
        decimals: 6,
        createDestination: true,
        recentBlockhash: blockhash,
      ),
    );
    check('create-if-missing on an account that exists is a no-op',
        idempotentRun['err'] == null, '${idempotentRun['err'] ?? 'accepted'}');

    // 3. control: ask for more than the sender holds.
    final Map<String, Object?> tooMuch = await simulate(
      SplTokenSigner.transferMessage(
        owner: owner,
        source: source,
        recipientOwner: existing,
        mint: mint,
        program: SplTokenProgram.token,
        amount: holder.amount + BigInt.one,
        decimals: 6,
        createDestination: false,
        recentBlockhash: blockhash,
      ),
    );
    check('control: more than the balance is rejected',
        tooMuch['err'] != null, '${tooMuch['err']}');

    // 4. control: wrong decimals are caught by TransferChecked.
    final Map<String, Object?> badDecimals = await simulate(
      SplTokenSigner.transferMessage(
        owner: owner,
        source: source,
        recipientOwner: existing,
        mint: mint,
        program: SplTokenProgram.token,
        amount: BigInt.from(1000),
        decimals: 9,
        createDestination: false,
        recentBlockhash: blockhash,
      ),
    );
    check('control: wrong decimals are rejected',
        badDecimals['err'] != null, '${badDecimals['err']}');

    // Token-2022: PayPal USD (6 decimals), held by the same two wallets.
    final Uint8List pyusd =
        Base58.decode('2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo')!;
    final Uint8List pyusdSource =
        Base58.decode('FELzjYS4MXATQJNaKtKGJYizUyHkS9a7xmiJUfzaUj53')!;
    final Map<String, Object?> create22 = await simulate(
      SplTokenSigner.transferMessage(
        owner: owner,
        source: pyusdSource,
        recipientOwner: fresh,
        mint: pyusd,
        program: SplTokenProgram.token2022,
        amount: BigInt.from(1000),
        decimals: 6,
        createDestination: true,
        recentBlockhash: blockhash,
      ),
    );
    check('Token-2022 (PYUSD) to a new wallet', create22['err'] == null,
        '${create22['err'] ?? 'accepted'}');
    final Map<String, Object?> plain22 = await simulate(
      SplTokenSigner.transferMessage(
        owner: owner,
        source: pyusdSource,
        recipientOwner: existing,
        mint: pyusd,
        program: SplTokenProgram.token2022,
        amount: BigInt.from(1000),
        decimals: 6,
        createDestination: false,
        recentBlockhash: blockhash,
      ),
    );
    check('Token-2022 (PYUSD) to a wallet that has an account',
        plain22['err'] == null, '${plain22['err'] ?? 'accepted'}');
  } finally {
    client.close();
  }

  if (failures > 0) {
    print('$failures check(s) failed.');
    exit(1);
  }
  print('All checks passed. Nothing was sent.');
}
