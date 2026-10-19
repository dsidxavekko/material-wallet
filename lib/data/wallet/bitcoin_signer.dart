import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/export.dart';

import '../../core/crypto/base58.dart';
import '../../core/crypto/bech32.dart';
import '../../core/crypto/hashing.dart';

/// Thrown when a Bitcoin transfer cannot be built or signed.
class BitcoinSigningException implements Exception {
  const BitcoinSigningException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A spendable unspent output.
class BitcoinUtxo {
  const BitcoinUtxo({
    required this.txid,
    required this.vout,
    required this.value,
    this.confirmed = true,
  });

  /// Transaction id the output lives in, big-endian hex as explorers show it.
  final String txid;

  final int vout;

  /// Output value in satoshis.
  final BigInt value;

  final bool confirmed;

  String get outpoint => '$txid:$vout';
}

/// One transaction input (an outpoint plus its sequence).
class BitcoinInput {
  const BitcoinInput({
    required this.txid,
    required this.vout,
    this.sequence = 0xffffffff,
  });

  final String txid;
  final int vout;
  final int sequence;
}

/// A transaction that is already on the network, as the explorer reports it —
/// the raw material for replacing it.
class BitcoinPriorTx {
  const BitcoinPriorTx({
    required this.txid,
    required this.confirmed,
    required this.inputs,
    required this.outputs,
  });

  final String txid;
  final bool confirmed;
  final List<BitcoinPriorInput> inputs;
  final List<BitcoinPriorOutput> outputs;
}

class BitcoinPriorInput {
  const BitcoinPriorInput({
    required this.utxo,
    required this.sequence,
    required this.address,
    required this.scriptType,
  });

  /// The coin this input spends, with the value it carried.
  final BitcoinUtxo utxo;
  final int sequence;

  /// Address that owned the spent coin, when the explorer knows it.
  final String? address;

  /// Explorer's script type, e.g. `v0_p2wpkh`.
  final String? scriptType;
}

class BitcoinPriorOutput {
  const BitcoinPriorOutput({required this.output, required this.address});

  final BitcoinOutput output;
  final String? address;
}

/// One transaction output: a value and the raw script that locks it.
class BitcoinOutput {
  const BitcoinOutput({required this.value, required this.scriptPubKey});

  final BigInt value;
  final Uint8List scriptPubKey;
}

/// A ready-to-sign transfer: the inputs to spend, the outputs to create and the
/// exact fee in satoshis.
class BitcoinPlan {
  const BitcoinPlan({
    required this.amount,
    required this.inputs,
    required this.outputs,
    required this.fee,
    required this.change,
    required this.vsize,
    required this.feeRate,
  });

  /// How much the recipient receives, in satoshis.
  final BigInt amount;

  final List<BitcoinUtxo> inputs;

  /// Recipient output, plus a change output when the remainder was worth
  /// keeping.
  final List<BitcoinOutput> outputs;

  final BigInt fee;

  /// Change returned to the wallet; zero when it fell below the dust limit.
  final BigInt change;

  /// Estimated virtual size the fee was priced on.
  final int vsize;

  /// satoshis per virtual byte.
  final int feeRate;

  BigInt get total => amount + fee;
}

/// Builds and signs native SegWit (P2WPKH, BIP-84) Bitcoin transactions.
///
/// Everything runs on-device in pure Dart: the sighash follows
/// [BIP-143](https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki),
/// signatures are deterministic (RFC 6979) and normalised to the lower half
/// (BIP-62), exactly as a node requires. Like the EVM path, the private key is
/// held only for the duration of the call.
class BitcoinSigner {
  const BitcoinSigner._();

  /// A P2WPKH output below this is not relayable; the leftover is folded into
  /// the fee instead of creating change nobody can spend.
  ///
  /// ponytail: a fixed 294 sat threshold (Bitcoin Core's P2WPKH dust limit at
  /// the default 3 sat/vB). Wallets that price in a much higher fee rate use a
  /// scaled threshold; raise this if that ever matters.
  static const int dustLimit = 294;

  static const int _sighashAll = 1;
  static const int _txVersion = 2;

  /// Input sequence that signals replace-by-fee (BIP-125: anything below
  /// `0xfffffffe`). Also keeps `nLockTime` enforceable like the final value
  /// does, so nothing else about the transaction changes.
  static const int rbfSequence = 0xfffffffd;

  /// Opt-out sequence of transactions signed before RBF signalling existed.
  static const int finalSequence = 0xffffffff;

  /// P2WPKH scriptPubKey (`OP_0 <20-byte hash160>`) for [publicKey].
  static Uint8List p2wpkhScript(Uint8List publicKey) =>
      Uint8List.fromList(<int>[0x00, 0x14, ...Hashing.hash160(publicKey)]);

  /// The script that locks funds sent to [address] on the [hrp] network.
  ///
  /// Supports native SegWit (`bc1q…` / `tb1q…`, v0 and v1) and legacy P2PKH /
  /// P2SH addresses. Throws [BitcoinSigningException] for anything else or for
  /// an address belonging to another Bitcoin network.
  static Uint8List scriptPubKeyForAddress(
    String address, {
    required String hrp,
  }) {
    final Bech32Data? decoded = Bech32.decode(address);
    if (decoded != null) {
      if (decoded.hrp != hrp) {
        throw const BitcoinSigningException(
          'The recipient address is for a different Bitcoin network.',
        );
      }
      final SegwitAddress? segwit = Bech32.decodeSegwit(decoded);
      if (segwit == null) {
        throw const BitcoinSigningException(
          'The recipient is not a valid SegWit address.',
        );
      }
      final int opcode = segwit.version == 0 ? 0x00 : 0x50 + segwit.version;
      return Uint8List.fromList(
        <int>[opcode, segwit.program.length, ...segwit.program],
      );
    }

    final Uint8List? payload = Base58.decodeCheck(address);
    if (payload == null || payload.length != 21) {
      throw const BitcoinSigningException('Invalid Bitcoin address.');
    }
    final bool mainnet = hrp == 'bc';
    final int version = payload[0];
    final Uint8List hash = payload.sublist(1);
    // Version bytes encode the network: 0/5 mainnet, 111/196 testnet.
    final bool rightNetwork = mainnet
        ? version == 0x00 || version == 0x05
        : version == 0x6f || version == 0xc4;
    if (!rightNetwork) {
      throw const BitcoinSigningException(
        'The recipient address is for a different Bitcoin network.',
      );
    }
    if (version == 0x00 || version == 0x6f) {
      return Uint8List.fromList(<int>[0x76, 0xa9, 0x14, ...hash, 0x88, 0xac]);
    }
    return Uint8List.fromList(<int>[0xa9, 0x14, ...hash, 0x87]);
  }

  /// Virtual size estimate for a transaction with [inputs] P2WPKH inputs and
  /// [outputs] standard outputs.
  ///
  /// The widely used P2WPKH approximation: ~10 vB overhead, 68 vB per input
  /// (outpoint, sequence and witness) and 31 vB per P2WPKH/P2PKH output.
  static int estimateVsize(int inputs, int outputs) => 10 + 68 * inputs + 31 * outputs;

  /// Selects the fewest (largest-first) inputs that cover [amount] plus the
  /// fee, and builds the recipient and change outputs.
  ///
  /// Returns `null` when the utxos cannot cover the transfer, so callers can
  /// refuse rather than sign an underfunded transaction.
  static BitcoinPlan? plan({
    required List<BitcoinUtxo> utxos,
    required BigInt amount,
    required Uint8List recipientScript,
    required Uint8List changeScript,
    required int feeRate,
  }) {
    if (amount <= BigInt.zero || feeRate <= 0) {
      return null;
    }
    final List<BitcoinUtxo> sorted = List<BitcoinUtxo>.of(utxos)
      ..sort((BitcoinUtxo a, BitcoinUtxo b) => b.value.compareTo(a.value));

    final List<BitcoinUtxo> selected = <BitcoinUtxo>[];
    BigInt total = BigInt.zero;
    for (final BitcoinUtxo utxo in sorted) {
      selected.add(utxo);
      total += utxo.value;

      final int withChange = estimateVsize(selected.length, 2);
      final BigInt changeFee = BigInt.from(withChange * feeRate);
      if (total >= amount + changeFee) {
        final BigInt change = total - amount - changeFee;
        if (change >= BigInt.from(dustLimit)) {
          return BitcoinPlan(
            amount: amount,
            inputs: List<BitcoinUtxo>.of(selected),
            outputs: <BitcoinOutput>[
              BitcoinOutput(value: amount, scriptPubKey: recipientScript),
              BitcoinOutput(value: change, scriptPubKey: changeScript),
            ],
            fee: changeFee,
            change: change,
            vsize: withChange,
            feeRate: feeRate,
          );
        }
      }

      // No viable change output: fold every remaining satoshi into the fee.
      final int withoutChange = estimateVsize(selected.length, 1);
      final BigInt minimalFee = BigInt.from(withoutChange * feeRate);
      if (total >= amount + minimalFee) {
        return BitcoinPlan(
          amount: amount,
          inputs: List<BitcoinUtxo>.of(selected),
          outputs: <BitcoinOutput>[
            BitcoinOutput(value: amount, scriptPubKey: recipientScript),
          ],
          fee: total - amount,
          change: BigInt.zero,
          vsize: withoutChange,
          feeRate: feeRate,
        );
      }
    }
    return null;
  }

  /// ponytail: BIP-125 also requires paying for any unconfirmed *descendants*
  /// of the original (for example a later transfer spending its change). They
  /// are not looked up here; the node rejects an underpaying replacement and
  /// the message is shown to the user.
  ///
  /// Plans a replace-by-fee version of the unconfirmed [original]: same
  /// inputs, same recipients, a larger fee paid out of the change output.
  ///
  /// Follows [BIP-125](https://github.com/bitcoin/bips/blob/master/bip-0125.mediawiki):
  /// the replacement pays a higher absolute fee than the original, plus at
  /// least 1 sat/vB for its own size. The new fee targets [targetFeeRate]
  /// sat/vB but is never below that floor. Only the change shrinks — a
  /// recipient is never asked to pay more, and no new input is pulled in, so
  /// the replacement cannot depend on anything unconfirmed.
  ///
  /// Throws [BitcoinSigningException] with a plain-language reason whenever the
  /// transaction cannot honestly be replaced (already confirmed, not ours,
  /// sent without RBF signalling, or too little change to pay for the bump).
  static BitcoinPlan planReplacement({
    required BitcoinPriorTx original,
    required String ownAddress,
    required int targetFeeRate,
    int dust = dustLimit,
  }) {
    if (original.confirmed) {
      throw const BitcoinSigningException(
        'This transfer is already confirmed — there is nothing to speed up.',
      );
    }
    final String own = ownAddress.toLowerCase();
    for (final BitcoinPriorInput input in original.inputs) {
      if (input.address?.toLowerCase() != own) {
        throw const BitcoinSigningException(
          'This transfer spends coins that are not all yours, so it cannot '
          'be replaced from this wallet.',
        );
      }
      if (input.scriptType != 'v0_p2wpkh') {
        throw const BitcoinSigningException(
          'Only native SegWit transfers can be replaced.',
        );
      }
    }
    if (!original.inputs
        .any((BitcoinPriorInput i) => i.sequence < 0xfffffffe)) {
      throw const BitcoinSigningException(
        'This transfer was sent without replace-by-fee, so the network will '
        'not accept a faster version of it.',
      );
    }

    final List<int> changeAt = <int>[
      for (int i = 0; i < original.outputs.length; i++)
        if (original.outputs[i].address?.toLowerCase() == own) i,
    ];
    if (changeAt.length != 1 || original.outputs.length < 2) {
      throw const BitcoinSigningException(
        'This transfer has no change to take the extra fee from.',
      );
    }
    final int changeIndex = changeAt.single;

    BigInt inputTotal = BigInt.zero;
    for (final BitcoinPriorInput input in original.inputs) {
      inputTotal += input.utxo.value;
    }
    BigInt outputTotal = BigInt.zero;
    for (final BitcoinPriorOutput out in original.outputs) {
      outputTotal += out.output.value;
    }
    final BigInt oldFee = inputTotal - outputTotal;
    if (oldFee < BigInt.zero) {
      throw const BitcoinSigningException(
        'The transfer\'s amounts do not add up. Nothing was changed.',
      );
    }

    final BigInt change = original.outputs[changeIndex].output.value;
    final int inputCount = original.inputs.length;

    // Keep the change output first; fall back to folding it into the fee.
    final int sizeWithChange =
        estimateVsize(inputCount, original.outputs.length);
    BigInt newFee = BigInt.from(sizeWithChange * targetFeeRate);
    final BigInt floorFee = oldFee + BigInt.from(sizeWithChange);
    if (newFee < floorFee) {
      newFee = floorFee;
    }
    final BigInt newChange = change - (newFee - oldFee);

    final List<BitcoinOutput> outputs;
    final BigInt finalFee;
    final BigInt finalChange;
    final int vsize;
    if (newChange >= BigInt.from(dust)) {
      outputs = <BitcoinOutput>[
        for (int i = 0; i < original.outputs.length; i++)
          i == changeIndex
              ? BitcoinOutput(
                  value: newChange,
                  scriptPubKey: original.outputs[i].output.scriptPubKey,
                )
              : original.outputs[i].output,
      ];
      finalFee = newFee;
      finalChange = newChange;
      vsize = sizeWithChange;
    } else {
      // Not enough change to stay above dust: it all goes to the fee, which
      // must still beat the original by the relay increment.
      final int sizeWithout =
          estimateVsize(inputCount, original.outputs.length - 1);
      final BigInt swept = oldFee + change;
      if (swept < oldFee + BigInt.from(sizeWithout) || change <= BigInt.zero) {
        throw const BitcoinSigningException(
          'The change is too small to pay for a faster version. '
          'Nothing was changed.',
        );
      }
      outputs = <BitcoinOutput>[
        for (int i = 0; i < original.outputs.length; i++)
          if (i != changeIndex) original.outputs[i].output,
      ];
      finalFee = swept;
      finalChange = BigInt.zero;
      vsize = sizeWithout;
    }

    BigInt recipients = BigInt.zero;
    for (int i = 0; i < original.outputs.length; i++) {
      if (i != changeIndex) {
        recipients += original.outputs[i].output.value;
      }
    }

    return BitcoinPlan(
      amount: recipients,
      inputs: <BitcoinUtxo>[
        for (final BitcoinPriorInput i in original.inputs) i.utxo,
      ],
      outputs: outputs,
      fee: finalFee,
      change: finalChange,
      vsize: vsize,
      feeRate: (finalFee ~/ BigInt.from(vsize)).toInt(),
    );
  }

  /// The most that can be sent in one transaction from [utxos] at [feeRate],
  /// sweeping every input into a single output.
  static BigInt? maxSpendable({
    required List<BitcoinUtxo> utxos,
    required int feeRate,
  }) {
    if (utxos.isEmpty || feeRate <= 0) {
      return null;
    }
    BigInt total = BigInt.zero;
    for (final BitcoinUtxo utxo in utxos) {
      total += utxo.value;
    }
    final BigInt fee = BigInt.from(estimateVsize(utxos.length, 1) * feeRate);
    return total > fee ? total - fee : null;
  }

  /// The BIP-143 modified sighash for one P2WPKH input.
  ///
  /// Exposed so it can be checked against the published BIP-143 vector; the
  /// signing path calls it per input.
  static Uint8List bip143Sighash({
    required List<BitcoinInput> inputs,
    required List<BitcoinOutput> outputs,
    required int inputIndex,
    required BigInt amount,
    required Uint8List scriptCode,
    required int lockTime,
    int version = _txVersion,
    int sighashType = _sighashAll,
  }) {
    final BytesBuilder prevouts = BytesBuilder();
    final BytesBuilder sequences = BytesBuilder();
    for (final BitcoinInput input in inputs) {
      prevouts.add(_reversed(hex.decode(input.txid)));
      prevouts.add(_le32(input.vout));
      sequences.add(_le32(input.sequence));
    }

    final BytesBuilder outs = BytesBuilder();
    for (final BitcoinOutput output in outputs) {
      outs.add(_le64(output.value));
      outs.add(_varint(output.scriptPubKey.length));
      outs.add(output.scriptPubKey);
    }

    final BitcoinInput input = inputs[inputIndex];
    final BytesBuilder preimage = BytesBuilder()
      ..add(_le32(version))
      ..add(_dsha256(prevouts.takeBytes()))
      ..add(_dsha256(sequences.takeBytes()))
      ..add(_reversed(hex.decode(input.txid)))
      ..add(_le32(input.vout))
      ..add(_varint(scriptCode.length))
      ..add(scriptCode)
      ..add(_le64(amount))
      ..add(_le32(input.sequence))
      ..add(_dsha256(outs.takeBytes()))
      ..add(_le32(lockTime))
      ..add(_le32(sighashType));

    return _dsha256(preimage.takeBytes());
  }

  /// Builds, signs and serialises a P2WPKH transaction spending every [utxos]
  /// entry into [outputs], returning the raw hex to broadcast.
  ///
  /// [publicKey] is the compressed key matching [privateKey]; its hash160 is the
  /// witness program every input is assumed to pay to.
  static String signP2wpkh({
    required Uint8List privateKey,
    required Uint8List publicKey,
    required List<BitcoinUtxo> utxos,
    required List<BitcoinOutput> outputs,
    int lockTime = 0,
  }) {
    if (utxos.isEmpty) {
      throw const BitcoinSigningException('Nothing to spend.');
    }
    final Uint8List program = Hashing.hash160(publicKey);
    // BIP-143 scriptCode for P2WPKH: the P2PKH script. It is passed *without*
    // its length prefix — [bip143Sighash] serialises it with one.
    final Uint8List scriptCode =
        Uint8List.fromList(<int>[0x76, 0xa9, 0x14, ...program, 0x88, 0xac]);

    final List<BitcoinInput> inputs = <BitcoinInput>[
      for (final BitcoinUtxo utxo in utxos)
        BitcoinInput(
          txid: utxo.txid,
          vout: utxo.vout,
          sequence: rbfSequence,
        ),
    ];

    final BytesBuilder witness = BytesBuilder();
    for (int i = 0; i < utxos.length; i++) {
      final Uint8List sighash = bip143Sighash(
        inputs: inputs,
        outputs: outputs,
        inputIndex: i,
        amount: utxos[i].value,
        scriptCode: scriptCode,
        lockTime: lockTime,
      );
      final Uint8List signature = _sign(sighash, privateKey);
      witness
        ..add(_varint(2))
        ..add(_varint(signature.length + 1))
        ..add(signature)
        ..addByte(_sighashAll)
        ..add(_varint(publicKey.length))
        ..add(publicKey);
    }

    final BytesBuilder tx = BytesBuilder()
      ..add(_le32(_txVersion))
      ..addByte(0x00) // segwit marker
      ..addByte(0x01) // segwit flag
      ..add(_varint(inputs.length));
    for (final BitcoinInput input in inputs) {
      tx
        ..add(_reversed(hex.decode(input.txid)))
        ..add(_le32(input.vout))
        ..addByte(0x00) // empty scriptSig for a witness input
        ..add(_le32(input.sequence));
    }
    tx.add(_varint(outputs.length));
    for (final BitcoinOutput output in outputs) {
      tx
        ..add(_le64(output.value))
        ..add(_varint(output.scriptPubKey.length))
        ..add(output.scriptPubKey);
    }
    tx
      ..add(witness.takeBytes())
      ..add(_le32(lockTime));

    return hex.encode(tx.takeBytes());
  }

  /// Deterministic (RFC 6979) low-S ECDSA signature of [hash], DER-encoded.
  static Uint8List _sign(Uint8List hash, Uint8List privateKey) {
    final ECDomainParameters params = ECCurve_secp256k1();
    final ECDSASigner signer = ECDSASigner(null, HMac(SHA256Digest(), 64))
      ..init(
        true,
        PrivateKeyParameter(
          ECPrivateKey(BigInt.parse(hex.encode(privateKey), radix: 16), params),
        ),
      );
    // No digest: [hash] is the BIP-143 sighash and is signed directly.
    final ECSignature raw = signer.generateSignature(hash) as ECSignature;
    final ECSignature signature =
        raw.isNormalized(params) ? raw : raw.normalize(params);
    return _derEncode(signature.r, signature.s);
  }

  /// ASN.1 DER encoding of an ECDSA signature, as Bitcoin expects it.
  static Uint8List _derEncode(BigInt r, BigInt s) {
    final Uint8List rb = _derInteger(r);
    final Uint8List sb = _derInteger(s);
    final Uint8List body = Uint8List.fromList(<int>[
      0x02,
      rb.length,
      ...rb,
      0x02,
      sb.length,
      ...sb,
    ]);
    return Uint8List.fromList(<int>[0x30, body.length, ...body]);
  }

  /// Minimal big-endian bytes, with a leading zero when the top bit is set so
  /// the value is read as positive.
  static Uint8List _derInteger(BigInt value) {
    final Uint8List bytes = _bigEndian(value);
    if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) {
      return Uint8List.fromList(<int>[0x00, ...bytes]);
    }
    return bytes;
  }

  static Uint8List _bigEndian(BigInt value) {
    final int length = (value.bitLength + 7) ~/ 8;
    final Uint8List out = Uint8List(length);
    BigInt remaining = value;
    for (int i = length - 1; i >= 0; i--) {
      out[i] = (remaining & BigInt.from(0xff)).toInt();
      remaining = remaining >> 8;
    }
    return out;
  }

  static Uint8List _dsha256(Uint8List data) =>
      Hashing.sha256(Hashing.sha256(data));

  static Uint8List _reversed(List<int> bytes) =>
      Uint8List.fromList(bytes.reversed.toList(growable: false));

  static Uint8List _le32(int value) => Uint8List.fromList(<int>[
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ]);

  static Uint8List _le64(BigInt value) {
    final Uint8List out = Uint8List(8);
    BigInt remaining = value;
    for (int i = 0; i < 8; i++) {
      out[i] = (remaining & BigInt.from(0xff)).toInt();
      remaining = remaining >> 8;
    }
    return out;
  }

  static Uint8List _varint(int value) {
    if (value < 0xfd) {
      return Uint8List.fromList(<int>[value]);
    }
    if (value <= 0xffff) {
      return Uint8List.fromList(<int>[0xfd, value & 0xff, (value >> 8) & 0xff]);
    }
    return Uint8List.fromList(<int>[0xfe, ..._le32(value)]);
  }
}
