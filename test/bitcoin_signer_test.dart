import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto_wallet/core/crypto/hashing.dart';
import 'package:crypto_wallet/data/wallet/bitcoin_signer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

Uint8List bytes(String value) => Uint8List.fromList(hex.decode(value));

void main() {
  group('BIP-143 sighash', () {
    // The published BIP-143 P2WPKH example: a two-input transaction whose
    // second input is P2WPKH. The sighash for that input is an external known
    // answer, so a drift in hashPrevouts/hashSequence/hashOutputs, the preimage
    // layout or the sighash type fails here by name.
    //
    // BIP-143 prints the txids in *internal* byte order (as they sit in the raw
    // transaction); this wallet takes explorer order, so they are reversed here.
    test('matches the BIP-143 P2WPKH vector', () {
      final List<BitcoinInput> inputs = <BitcoinInput>[
        const BitcoinInput(
          txid: '9f96ade4b41d5433f4eda31e1738ec2b36f6e7d1420d94a6af99801a88f7f7ff',
          vout: 0,
          sequence: 0xffffffee,
        ),
        const BitcoinInput(
          txid: '8ac60eb9575db5b2d987e29f301b5b819ea83a5c6579d282d189cc04b8e151ef',
          vout: 1,
          sequence: 0xffffffff,
        ),
      ];
      final List<BitcoinOutput> outputs = <BitcoinOutput>[
        BitcoinOutput(
          value: BigInt.from(112340000),
          scriptPubKey: bytes('76a9148280b37df378db99f66f85c95a783a76ac7a6d5988ac'),
        ),
        BitcoinOutput(
          value: BigInt.from(223450000),
          scriptPubKey: bytes('76a9143bde42dbee7e4dbe6a21b2d50ce2f0167faa815988ac'),
        ),
      ];

      final Uint8List sighash = BitcoinSigner.bip143Sighash(
        inputs: inputs,
        outputs: outputs,
        inputIndex: 1,
        amount: BigInt.from(600000000),
        // The P2WPKH scriptCode (the P2PKH script; the length is added by the
        // signer).
        scriptCode: bytes('76a9141d0f172a0ecb48aee1be1f2687d2963ae33f71a188ac'),
        lockTime: 17,
        version: 1,
      );

      expect(
        hex.encode(sighash),
        'c37af31116d1b27caf68aae9e3ac82f1477929014d5b917657d0eb49478cb670',
      );
    });
  });

  group('signP2wpkh', () {
    // A throwaway key: bytes 1..32. Only structure and the signature are
    // checked; nothing is broadcast.
    final Uint8List privateKey =
        Uint8List.fromList(List<int>.generate(32, (int i) => i + 1));
    final Uint8List publicKey = _compressedPublicKey(privateKey);

    final List<BitcoinUtxo> utxos = <BitcoinUtxo>[
      BitcoinUtxo(
        txid: 'a' * 64,
        vout: 0,
        value: BigInt.from(100000),
      ),
    ];
    final List<BitcoinOutput> outputs = <BitcoinOutput>[
      BitcoinOutput(
        value: BigInt.from(90000),
        scriptPubKey: BitcoinSigner.p2wpkhScript(bytes('bb' * 20)),
      ),
    ];

    test('serialises a segwit transaction with a witness', () {
      final String raw = BitcoinSigner.signP2wpkh(
        privateKey: privateKey,
        publicKey: publicKey,
        utxos: utxos,
        outputs: outputs,
      );
      final Uint8List tx = bytes(raw);

      expect(tx.sublist(0, 4), <int>[0x02, 0x00, 0x00, 0x00]); // version 2
      expect(tx[4], 0x00, reason: 'segwit marker');
      expect(tx[5], 0x01, reason: 'segwit flag');
      expect(tx[6], 0x01, reason: 'one input');
      expect(tx[7 + 36], 0x00, reason: 'empty scriptSig on a witness input');
      expect(tx.sublist(tx.length - 4), <int>[0, 0, 0, 0], reason: 'locktime');
      expect(hex.encode(tx), contains(hex.encode(publicKey)));
    });

    test('signals BIP-125 replaceability on every input', () {
      final Uint8List tx = bytes(
        BitcoinSigner.signP2wpkh(
          privateKey: privateKey,
          publicKey: publicKey,
          utxos: utxos,
          outputs: outputs,
        ),
      );
      // version(4) marker/flag(2) count(1) outpoint(36) scriptSig(1) → sequence.
      final Uint8List sequence = tx.sublist(7 + 36 + 1, 7 + 36 + 1 + 4);
      expect(sequence, <int>[0xfd, 0xff, 0xff, 0xff]);
      expect(BitcoinSigner.rbfSequence, 0xfffffffd);
    });

    test('produces a canonical DER signature that verifies', () {
      final String raw = BitcoinSigner.signP2wpkh(
        privateKey: privateKey,
        publicKey: publicKey,
        utxos: utxos,
        outputs: outputs,
      );
      final _Witness witness = _firstWitness(bytes(raw));
      expect(witness.publicKey, publicKey);

      _assertCanonicalDer(witness.signature);

      // Independent check: pointycastle's verifier — not the signing code —
      // must accept the signature over the sighash it committed to.
      final ECSignature signature = _decodeDer(witness.signature);
      final ECDomainParameters params = ECCurve_secp256k1();
      final ECPoint q = params.curve.decompressPoint(
        publicKey[0] == 0x03 ? 1 : 0,
        BigInt.parse(hex.encode(publicKey.sublist(1)), radix: 16),
      );
      final ECDSASigner verifier = ECDSASigner(null, HMac(SHA256Digest(), 64))
        ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(q, params)));

      final Uint8List sighash = BitcoinSigner.bip143Sighash(
        inputs: <BitcoinInput>[
          const BitcoinInput(
            txid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            vout: 0,
          ),
        ],
        outputs: outputs,
        inputIndex: 0,
        amount: utxos.first.value,
        scriptCode: bytes('76a914${hex.encode(Hashing.hash160(publicKey))}88ac'),
        lockTime: 0,
      );
      expect(
        verifier.verifySignature(sighash, signature),
        isTrue,
      );
    });
  });

  group('planReplacement (BIP-125)', () {
    final Uint8List change = BitcoinSigner.p2wpkhScript(bytes('bb' * 20));

    BitcoinPlan plan(BitcoinTxDetail tx, int rate) =>
        BitcoinSigner.planReplacement(
          original: tx,
          ownAddress: 'bc1qown',
          changeScript: change,
          feeRate: rate,
        );

    test('keeps inputs and the recipient output, taking the fee from change', () {
      final BitcoinTxDetail original = _pendingTx(); // fee 1000 sat
      final BitcoinPlan bumped = plan(original, 20);

      expect(bumped.replacesTxid, original.txid);
      expect(bumped.originalFee, BigInt.from(1000));
      expect(bumped.inputs.single.outpoint, '${'cd' * 32}:1');
      expect(bumped.outputs, hasLength(2));
      expect(bumped.outputs.first.value, BigInt.from(60000),
          reason: 'the recipient must receive exactly what was agreed');
      expect(
        bumped.outputs.first.scriptPubKey,
        original.outputs.first.scriptPubKey,
      );
      // Value is conserved: everything not paid out is fee.
      expect(
        bumped.outputs.fold<BigInt>(BigInt.zero, (a, o) => a + o.value) +
            bumped.fee,
        BigInt.from(100000),
      );
    });

    test('pays at least the target rate and the BIP-125 minimum bump', () {
      final BitcoinTxDetail original = _pendingTx();
      final BitcoinPlan bumped = plan(original, 20);
      final int vsize = BitcoinSigner.estimateVsize(1, 2);

      expect(bumped.fee, BigInt.from(20 * vsize));
      expect(bumped.fee >= original.fee + BigInt.from(vsize), isTrue);
    });

    test('a target at or below the original still outbids it by the relay fee',
        () {
      final BitcoinTxDetail original = _pendingTx(); // 1000 sat, ~7 sat/vB
      final BitcoinPlan bumped = plan(original, 1);
      final int vsize = BitcoinSigner.estimateVsize(1, 2);

      expect(bumped.fee, original.fee + BigInt.from(vsize));
      expect(bumped.fee > original.fee, isTrue);
    });

    test('drops change that would fall below dust and folds it into the fee', () {
      // 61000 in, 60000 + 300 out: a 700 sat fee. Bumping needs 140 sat more,
      // which would leave 160 sat of change — under the 294 dust limit.
      final BitcoinTxDetail original =
          _pendingTx(outputValues: <int>[60000, 300], inputValue: 61000);
      final BitcoinPlan bumped = plan(original, 5);

      expect(bumped.outputs, hasLength(1));
      expect(bumped.change, BigInt.zero);
      expect(bumped.fee, BigInt.from(700 + 300),
          reason: 'the 700 sat fee plus all 300 sat of change');
    });

    test('refuses when the change cannot pay for the bump', () {
      final BitcoinTxDetail original =
          _pendingTx(outputValues: <int>[60000, 300], inputValue: 61000);
      expect(
        () => plan(original, 200),
        throwsA(
          isA<BitcoinSigningException>()
              .having((e) => e.message, 'message', contains('too small')),
        ),
      );
    });

    test('refuses a transfer that never signalled RBF', () {
      expect(
        () => plan(_pendingTx(sequence: 0xffffffff), 20),
        throwsA(
          isA<BitcoinSigningException>()
              .having((e) => e.message, 'message', contains('RBF')),
        ),
      );
    });

    test('refuses a confirmed transfer', () {
      expect(
        () => plan(_pendingTx(confirmed: true), 20),
        throwsA(isA<BitcoinSigningException>()),
      );
    });

    test('refuses a transfer with no change output', () {
      final BitcoinTxDetail noChange = BitcoinTxDetail(
        txid: 'ab' * 32,
        confirmed: false,
        fee: BigInt.from(1000),
        inputs: <BitcoinTxInputDetail>[
          BitcoinTxInputDetail(
            txid: 'cd' * 32,
            vout: 0,
            value: BigInt.from(61000),
            address: 'bc1qown',
            sequence: 0xfffffffd,
          ),
        ],
        outputs: <BitcoinTxOutputDetail>[
          BitcoinTxOutputDetail(
            value: BigInt.from(60000),
            scriptPubKey: BitcoinSigner.p2wpkhScript(bytes('aa' * 20)),
          ),
        ],
      );
      expect(
        () => plan(noChange, 20),
        throwsA(
          isA<BitcoinSigningException>()
              .having((e) => e.message, 'message', contains('no change')),
        ),
      );
    });

    test('refuses inputs that belong to another address', () {
      expect(
        () => plan(_pendingTx(inputAddress: 'bc1qsomeoneelse'), 20),
        throwsA(isA<BitcoinSigningException>()),
      );
    });

    test('a bumped plan signs and still signals RBF', () {
      final Uint8List privateKey =
          Uint8List.fromList(List<int>.generate(32, (int i) => i + 1));
      final BitcoinPlan bumped = plan(_pendingTx(), 20);
      final String raw = BitcoinSigner.signP2wpkh(
        privateKey: privateKey,
        publicKey: _compressedPublicKey(privateKey),
        utxos: bumped.inputs,
        outputs: bumped.outputs,
      );
      expect(raw, isNotEmpty);
      expect(bytes(raw).sublist(44, 48), <int>[0xfd, 0xff, 0xff, 0xff]);
    });
  });

  group('plan', () {
    final Uint8List recipient = BitcoinSigner.p2wpkhScript(bytes('aa' * 20));
    final Uint8List change = BitcoinSigner.p2wpkhScript(bytes('bb' * 20));

    test('selects inputs that cover amount plus fee and returns change', () {
      final List<BitcoinUtxo> utxos = <BitcoinUtxo>[
        BitcoinUtxo(txid: '11' * 32, vout: 0, value: BigInt.from(50000)),
        BitcoinUtxo(txid: '22' * 32, vout: 1, value: BigInt.from(40000)),
      ];

      final BitcoinPlan? plan = BitcoinSigner.plan(
        utxos: utxos,
        amount: BigInt.from(60000),
        recipientScript: recipient,
        changeScript: change,
        feeRate: 2,
      );

      expect(plan, isNotNull);
      // Largest first: the 50k utxo is short of 60000 + fee, so both are spent.
      expect(plan!.inputs, hasLength(2));
      expect(plan.fee, BigInt.from(BitcoinSigner.estimateVsize(2, 2) * 2));
      expect(plan.change, BigInt.from(90000 - 60000) - plan.fee);
      expect(plan.outputs, hasLength(2));
    });

    test('folds sub-dust change into the fee instead of creating change', () {
      final List<BitcoinUtxo> utxos = <BitcoinUtxo>[
        // Leaves 100 sat of change after a 1-in/2-out fee at 1 sat/vB, well
        // below the dust limit.
        BitcoinUtxo(txid: '33' * 32, vout: 0, value: BigInt.from(60240)),
      ];

      final BitcoinPlan? plan = BitcoinSigner.plan(
        utxos: utxos,
        amount: BigInt.from(60000),
        recipientScript: recipient,
        changeScript: change,
        feeRate: 1,
      );

      expect(plan, isNotNull);
      expect(plan!.change, BigInt.zero);
      expect(plan.outputs, hasLength(1), reason: 'no dust change output');
      expect(plan.fee, BigInt.from(240), reason: 'leftover joins the fee');
    });

    test('returns null when the utxos cannot cover the transfer', () {
      final List<BitcoinUtxo> utxos = <BitcoinUtxo>[
        BitcoinUtxo(txid: '44' * 32, vout: 0, value: BigInt.from(1000)),
      ];

      expect(
        BitcoinSigner.plan(
          utxos: utxos,
          amount: BigInt.from(1000),
          recipientScript: recipient,
          changeScript: change,
          feeRate: 5,
        ),
        isNull,
      );
    });

    test('maxSpendable keeps the fee back from the whole balance', () {
      final List<BitcoinUtxo> utxos = <BitcoinUtxo>[
        BitcoinUtxo(txid: '55' * 32, vout: 0, value: BigInt.from(10000)),
      ];
      final BigInt? max = BitcoinSigner.maxSpendable(utxos: utxos, feeRate: 1);
      expect(max, BigInt.from(10000 - BitcoinSigner.estimateVsize(1, 1)));
    });
  });

  group('scriptPubKeyForAddress', () {
    test('builds the v0 witness program for a mainnet address', () {
      final Uint8List script = BitcoinSigner.scriptPubKeyForAddress(
        'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
        hrp: 'bc',
      );
      expect(hex.encode(script), '0014751e76e8199196d454941c45d1b3a323f1433bd6');
    });

    test('builds a P2PKH script for a legacy address', () {
      final Uint8List script = BitcoinSigner.scriptPubKeyForAddress(
        '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2',
        hrp: 'bc',
      );
      expect(script.sublist(0, 3), <int>[0x76, 0xa9, 0x14]);
      expect(script.last, 0xac);
    });

    test('refuses an address for another network', () {
      expect(
        () => BitcoinSigner.scriptPubKeyForAddress(
          'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
          hrp: 'bc',
        ),
        throwsA(isA<BitcoinSigningException>()),
      );
    });
  });
}

BitcoinTxDetail _pendingTx({
  int sequence = 0xfffffffd,
  bool confirmed = false,
  int inputValue = 100000,
  List<int> outputValues = const <int>[60000, 39000],
  String? inputAddress = 'bc1qown',
}) =>
    BitcoinTxDetail(
      txid: 'ab' * 32,
      confirmed: confirmed,
      fee: BigInt.from(
        inputValue - outputValues.fold<int>(0, (int a, int b) => a + b),
      ),
      inputs: <BitcoinTxInputDetail>[
        BitcoinTxInputDetail(
          txid: 'cd' * 32,
          vout: 1,
          value: BigInt.from(inputValue),
          address: inputAddress,
          sequence: sequence,
        ),
      ],
      outputs: <BitcoinTxOutputDetail>[
        // First output pays someone else, the last one is our change.
        for (int i = 0; i < outputValues.length; i++)
          BitcoinTxOutputDetail(
            value: BigInt.from(outputValues[i]),
            scriptPubKey: i == outputValues.length - 1
                ? BitcoinSigner.p2wpkhScript(bytes('bb' * 20))
                : BitcoinSigner.p2wpkhScript(bytes('aa' * 20)),
          ),
      ],
    );

/// Compressed secp256k1 public key for [privateKey].
Uint8List _compressedPublicKey(Uint8List privateKey) {
  final ECDomainParameters params = ECCurve_secp256k1();
  final ECPoint point =
      (params.G * BigInt.parse(hex.encode(privateKey), radix: 16))!;
  return point.getEncoded(true);
}

class _Witness {
  const _Witness(this.signature, this.publicKey);
  final Uint8List signature;
  final Uint8List publicKey;
}

/// Extracts the first input's witness (signature, public key) from a raw segwit
/// transaction, parsing the bytes independently of the builder.
_Witness _firstWitness(Uint8List tx) {
  int cursor = 4; // version
  expect(tx[cursor], 0x00);
  expect(tx[cursor + 1], 0x01);
  cursor += 2;
  final int inputCount = tx[cursor++];
  expect(inputCount, 1);
  cursor += 41; // outpoint + empty scriptSig + sequence
  final int outputCount = tx[cursor++];
  for (int i = 0; i < outputCount; i++) {
    cursor += 8; // value
    final int scriptLength = tx[cursor++];
    cursor += scriptLength;
  }
  // Witness stack: item count, then length-prefixed items.
  expect(tx[cursor++], 2, reason: 'signature and public key');
  final int sigLength = tx[cursor++];
  final Uint8List item = tx.sublist(cursor, cursor + sigLength);
  cursor += sigLength;
  final int keyLength = tx[cursor++];
  final Uint8List publicKey = tx.sublist(cursor, cursor + keyLength);
  expect(item.last, 0x01, reason: 'sighash byte');
  // The witness item is the DER signature with the sighash type appended.
  return _Witness(item.sublist(0, item.length - 1), publicKey);
}

/// Asserts strict DER: `30 len 02 rlen r 02 slen s`, exact lengths and minimal
/// integers (BIP-66).
void _assertCanonicalDer(Uint8List der) {
  expect(der[0], 0x30);
  expect(der[1], der.length - 2, reason: 'outer length covers the body');
  expect(der[2], 0x02);
  final int rLength = der[3];
  expect(der[4 + rLength], 0x02, reason: 'second INTEGER tag');
  final int sLength = der[5 + rLength];
  expect(6 + rLength + sLength, der.length, reason: 'no trailing bytes');
  expect(der[4] & 0x80, 0, reason: 'r is positive and minimal');
  expect(der[6 + rLength] & 0x80, 0, reason: 's is positive and minimal');
}

/// Decodes a canonical DER signature back into its integers for verification.
ECSignature _decodeDer(Uint8List der) {
  final int rLength = der[3];
  final BigInt r =
      BigInt.parse(hex.encode(der.sublist(4, 4 + rLength)), radix: 16);
  final int sOffset = 4 + rLength + 2;
  final int sLength = der[5 + rLength];
  final BigInt s =
      BigInt.parse(hex.encode(der.sublist(sOffset, sOffset + sLength)), radix: 16);
  return ECSignature(r, s);
}
