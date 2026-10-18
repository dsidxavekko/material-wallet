import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/bitcoin_signer.dart';
import 'package:crypto_wallet/data/wallet/secure_pin_store.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/state/send_controller.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWalletStorage extends WalletStorage {
  String? vault;

  @override
  Future<String?> readVault() async => vault;

  @override
  Future<void> writeVault(String payload, DateTime createdAt) async {
    vault = payload;
  }

  @override
  Future<void> clear() async {
    vault = null;
  }
}

class _FakePinStore extends SecurePinStore {
  String? pin;

  @override
  Future<void> write(String value) async => pin = value;

  @override
  Future<String?> read() async => pin;

  @override
  Future<void> clear() async => pin = null;

  @override
  Future<bool> get hasPin async => pin != null;
}

/// Serves one original transaction (which can flip to confirmed) and counts
/// broadcasts.
class _FakeChainApi extends ChainApi {
  _FakeChainApi(this.original);

  BitcoinPriorTx? original;
  int broadcasts = 0;
  String? lastRaw;

  @override
  Future<BitcoinPriorTx?> fetchBitcoinTransaction(
    NetworkConfig network,
    String txid,
  ) async =>
      original;

  @override
  Future<BitcoinFeeTiers> fetchBitcoinFeeTiers(NetworkConfig network) async =>
      const BitcoinFeeTiers(fastestFee: 20, halfHourFee: 10, hourFee: 5);

  @override
  Future<String> broadcastBitcoinTransaction(
    NetworkConfig network,
    String rawTransaction,
  ) async {
    broadcasts++;
    lastRaw = rawTransaction;
    return 'c' * 64;
  }

  @override
  Future<bool?> waitForBitcoinConfirmation(
    NetworkConfig network,
    String txid, {
    int attempts = 12,
  }) async =>
      true;

  @override
  void dispose() {}
}

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';
  const String recipient = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
  const NetworkConfig network = NetworkCatalog.bitcoin;
  const String own = 'bc1qown0000000000000000000000000000000000';

  final Uint8List recipientScript =
      BitcoinSigner.scriptPubKeyForAddress(recipient, hrp: 'bc');
  final Uint8List ownScript = Uint8List.fromList(
    <int>[0x00, 0x14, ...List<int>.filled(20, 7)],
  );

  BitcoinPriorInput input({
    int value = 100000,
    int sequence = BitcoinSigner.rbfSequence,
    String? address = own,
    String type = 'v0_p2wpkh',
    String txid = 'a',
  }) =>
      BitcoinPriorInput(
        utxo: BitcoinUtxo(
          txid: txid * 64,
          vout: 0,
          value: BigInt.from(value),
        ),
        sequence: sequence,
        address: address,
        scriptType: type,
      );

  BitcoinPriorOutput out(int value, Uint8List script, String address) =>
      BitcoinPriorOutput(
        output: BitcoinOutput(value: BigInt.from(value), scriptPubKey: script),
        address: address,
      );

  /// 100 000 in, 50 000 to the recipient, 49 000 change, 1 000 fee.
  BitcoinPriorTx original({
    List<BitcoinPriorInput>? inputs,
    List<BitcoinPriorOutput>? outputs,
    bool confirmed = false,
  }) =>
      BitcoinPriorTx(
        txid: 'f' * 64,
        confirmed: confirmed,
        inputs: inputs ?? <BitcoinPriorInput>[input()],
        outputs: outputs ??
            <BitcoinPriorOutput>[
              out(50000, recipientScript, recipient),
              out(49000, ownScript, own),
            ],
      );

  BitcoinPlan plan(BitcoinPriorTx tx, {int rate = 20}) =>
      BitcoinSigner.planReplacement(
        original: tx,
        ownAddress: own,
        targetFeeRate: rate,
      );

  group('RBF signalling', () {
    test('every input is signed with the BIP-125 sequence', () {
      final ({Uint8List privateKey, Uint8List publicKey}) keys = (
        privateKey: Uint8List.fromList(List<int>.filled(32, 1)),
        publicKey: Uint8List.fromList(hex.decode(
          '031b84c5567b126440995d3ed5aaba0565d71e1834604819ff9c17f5e9d5dd078f',
        )),
      );
      final String raw = BitcoinSigner.signP2wpkh(
        privateKey: keys.privateKey,
        publicKey: keys.publicKey,
        utxos: <BitcoinUtxo>[
          BitcoinUtxo(txid: 'aa' * 32, vout: 1, value: BigInt.from(100000)),
        ],
        outputs: <BitcoinOutput>[
          BitcoinOutput(value: BigInt.from(90000), scriptPubKey: recipientScript),
        ],
      );

      // version(4) marker+flag(2) incount(1) txid(32) vout(4) scriptSig(1)
      final String sequence = raw.substring((4 + 2 + 1 + 32 + 4 + 1) * 2).substring(0, 8);
      expect(sequence, 'fdffffff');
    });
  });

  group('planReplacement', () {
    test('keeps inputs and recipients, takes the extra fee from the change', () {
      final BitcoinPlan p = plan(original());

      expect(p.inputs.single.outpoint, 'a' * 64 + ':0');
      expect(p.outputs.first.value, BigInt.from(50000));
      expect(p.outputs.first.scriptPubKey, recipientScript);
      expect(p.amount, BigInt.from(50000));
      // 1 input, 2 outputs → 140 vB at 20 sat/vB.
      expect(p.vsize, 140);
      expect(p.fee, BigInt.from(140 * 20));
      expect(p.outputs.last.value, BigInt.from(100000 - 50000) - p.fee);
      expect(p.change, p.outputs.last.value);
    });

    test('pays more than the original plus the relay increment (BIP-125)', () {
      // A target below the original's own rate still has to outbid it.
      final BitcoinPlan p = plan(original(), rate: 1);

      expect(p.fee, greaterThan(BigInt.from(1000)));
      expect(p.fee, greaterThanOrEqualTo(BigInt.from(1000 + p.vsize)));
    });

    test('folds sub-dust change into the fee and drops the output', () {
      // 100 000 in, 99 700 to the recipient, 200 change (dust), 100 fee.
      final BitcoinPlan p = plan(
        original(
          outputs: <BitcoinPriorOutput>[
            out(99700, recipientScript, recipient),
            out(200, ownScript, own),
          ],
        ),
      );

      expect(p.outputs, hasLength(1));
      expect(p.change, BigInt.zero);
      expect(p.fee, BigInt.from(300));
      expect(p.fee, greaterThanOrEqualTo(BigInt.from(100 + p.vsize)));
    });

    test('refuses honestly when the change cannot pay for the bump', () {
      expect(
        () => plan(
          original(
            outputs: <BitcoinPriorOutput>[
              out(99990, recipientScript, recipient),
              out(10, ownScript, own),
            ],
          ),
        ),
        throwsA(
          isA<BitcoinSigningException>().having(
            (BitcoinSigningException e) => e.message,
            'message',
            contains('change is too small'),
          ),
        ),
      );
    });

    test('refuses a transfer that did not signal RBF', () {
      expect(
        () => plan(
          original(
            inputs: <BitcoinPriorInput>[
              input(sequence: BitcoinSigner.finalSequence),
            ],
          ),
        ),
        throwsA(
          isA<BitcoinSigningException>().having(
            (BitcoinSigningException e) => e.message,
            'message',
            contains('without replace-by-fee'),
          ),
        ),
      );
    });

    test('refuses a confirmed transfer, a foreign input and a sweep', () {
      expect(
        () => plan(original(confirmed: true)),
        throwsA(isA<BitcoinSigningException>()),
      );
      expect(
        () => plan(
          original(
            inputs: <BitcoinPriorInput>[
              input(),
              input(address: 'bc1qsomeoneelse', txid: 'b'),
            ],
          ),
        ),
        throwsA(isA<BitcoinSigningException>()),
      );
      expect(
        () => plan(
          original(
            outputs: <BitcoinPriorOutput>[
              out(99000, recipientScript, recipient),
            ],
          ),
        ),
        throwsA(isA<BitcoinSigningException>()),
      );
    });
  });

  group('explorer parsing', () {
    test('reads inputs with their coins and outputs with their scripts',
        () async {
      final ChainApi api = ChainApi(
        client: MockClient((http.Request request) async {
          expect(request.url.path, endsWith('/tx/${'f' * 64}'));
          return http.Response(
            '''
{"txid":"${'f' * 64}","status":{"confirmed":false},
 "vin":[{"txid":"${'a' * 64}","vout":2,"sequence":4294967293,
   "prevout":{"scriptpubkey_address":"$own","scriptpubkey_type":"v0_p2wpkh","value":100000}}],
 "vout":[{"scriptpubkey":"${hex.encode(recipientScript)}","scriptpubkey_address":"$recipient","value":50000}]}
''',
            200,
          );
        }),
      );

      final BitcoinPriorTx? tx =
          await api.fetchBitcoinTransaction(network, 'f' * 64);

      expect(tx!.confirmed, isFalse);
      expect(tx.inputs.single.sequence, BitcoinSigner.rbfSequence);
      expect(tx.inputs.single.utxo.vout, 2);
      expect(tx.inputs.single.address, own);
      expect(tx.outputs.single.output.scriptPubKey, recipientScript);
    });
  });

  group('SendController', () {
    Future<(SendController, _FakeChainApi, String)> wallet(
      BitcoinPriorTx Function(String ownAddress) build,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final WalletIdentityController identity = WalletIdentityController(
        storage: _FakeWalletStorage(),
        pinStore: _FakePinStore(),
        kdfRounds: 1000,
      );
      await identity.load();
      await identity.createWallet(mnemonic: mnemonic, pin: pin);
      final String address = identity.addressFor(network)!;
      final _FakeChainApi api = _FakeChainApi(build(address));
      return (
        SendController(
          identity: identity,
          network: network,
          address: address,
          chainApi: api,
        ),
        api,
        address,
      );
    }

    BitcoinPriorTx ownedTx(String address) => original(
          inputs: <BitcoinPriorInput>[input(address: address)],
          outputs: <BitcoinPriorOutput>[
            out(50000, recipientScript, recipient),
            out(
              49000,
              BitcoinSigner.scriptPubKeyForAddress(address, hrp: 'bc'),
              address,
            ),
          ],
        );

    test('speed-up plans from the live fastest tier and broadcasts once',
        () async {
      final (SendController send, _FakeChainApi api, _) =
          await wallet(ownedTx);

      final prepared = await send.prepareBitcoinSpeedUp('f' * 64);
      expect(prepared.reason, isNull);
      expect(prepared.oldFee, BigInt.from(1000));
      expect(prepared.plan!.fee, BigInt.from(140 * 20));

      final bool ok = await send.sendBitcoinReplacement(
        originalTxid: 'f' * 64,
        plan: prepared.plan!,
      );

      expect(ok, isTrue);
      expect(api.broadcasts, 1);
      // The broadcast transaction signals RBF itself, so it can be bumped again.
      expect(
        api.lastRaw!.substring((4 + 2 + 1 + 32 + 4 + 1) * 2).substring(0, 8),
        'fdffffff',
      );
      send.dispose();
    });

    test('refuses to sign when the original confirmed in the meantime',
        () async {
      final (SendController send, _FakeChainApi api, address) =
          await wallet(ownedTx);
      final prepared = await send.prepareBitcoinSpeedUp('f' * 64);

      api.original = BitcoinPriorTx(
        txid: 'f' * 64,
        confirmed: true,
        inputs: ownedTx(address).inputs,
        outputs: ownedTx(address).outputs,
      );
      final bool ok = await send.sendBitcoinReplacement(
        originalTxid: 'f' * 64,
        plan: prepared.plan!,
      );

      expect(ok, isFalse);
      expect(api.broadcasts, 0);
      expect(send.error, contains('Nothing was sent'));
      send.dispose();
    });

    test('refuses when the original no longer has the planned inputs',
        () async {
      final (SendController send, _FakeChainApi api, address) =
          await wallet(ownedTx);
      final prepared = await send.prepareBitcoinSpeedUp('f' * 64);

      api.original = original(
        inputs: <BitcoinPriorInput>[input(address: address, txid: 'c')],
        outputs: ownedTx(address).outputs,
      );
      final bool ok = await send.sendBitcoinReplacement(
        originalTxid: 'f' * 64,
        plan: prepared.plan!,
      );

      expect(ok, isFalse);
      expect(api.broadcasts, 0);
      send.dispose();
    });

    test('says why a transfer without RBF cannot be sped up', () async {
      final (SendController send, _, _) = await wallet(
        (String address) => original(
          inputs: <BitcoinPriorInput>[
            input(address: address, sequence: BitcoinSigner.finalSequence),
          ],
          outputs: ownedTx(address).outputs,
        ),
      );

      final prepared = await send.prepareBitcoinSpeedUp('f' * 64);
      expect(prepared.plan, isNull);
      expect(prepared.reason, contains('without replace-by-fee'));
      send.dispose();
    });
  });
}
