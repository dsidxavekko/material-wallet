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
    this.sequence = BitcoinSigner.rbfSequence,
  });

  final String txid;
  final int vout;
  final int sequence;
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
    this.replacesTxid,
    this.originalFee,
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

  /// The pending transaction this plan replaces (RBF), or `null` for a fresh
  /// transfer. A replacement spends inputs the mempool already considers spent,
  /// so it is verified against that transaction instead of the utxo set.
  final String? replacesTxid;

  /// The fee of the transaction being replaced; with [replacesTxid] it lets the
  /// send step notice the original was already replaced or mined.
  final BigInt? originalFee;

  BigInt get total => amount + fee;
}

/// An input of an already-published transaction, as the explorer reports it.
class BitcoinTxInputDetail {
  const BitcoinTxInputDetail({
    required this.txid,
    required this.vout,
    required this.value,
    required this.address,
    required this.sequence,
  });

  final String txid;
  final int vout;

  /// Value of the output being spent, in satoshis.
  final BigInt value;

  /// Address the spent output paid, or `null` when the explorer gave none.
  final String? address;

  final int sequence;
}

/// An output of an already-published transaction.
class BitcoinTxOutputDetail {
  const BitcoinTxOutputDetail({required this.value, required this.scriptPubKey});

  final BigInt value;
  final Uint8List scriptPubKey;
}

/// A published transaction in the shape a replacement is built from.
class BitcoinTxDetail {
  const BitcoinTxDetail({
    required this.txid,
    required this.inputs,
    required this.outputs,
    required this.fee,
    required this.confirmed,
  });

  final String txid;
  final List<BitcoinTxInputDetail> inputs;
  final List<BitcoinTxOutputDetail> outputs;

  /// Absolute fee in satoshis.
  final BigInt fee;

  final bool confirmed;

  /// BIP-125: a transaction is replaceable when any input has a sequence below
  /// `0xfffffffe`.
  bool get signalsRbf =>
      inputs.any((BitcoinTxInputDetail input) => input.sequence < 0xfffffffe);
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

  /// Input sequence that signals BIP-125 replaceability (`0xfffffffd`) while
  /// still leaving the locktime enabled. Every input this wallet signs carries
  /// it, so a stuck transfer can always be fee-bumped.
  static const int rbfSequence = 0xfffffffd;

  /// BIP-125 incremental relay fee: a replacement must pay this many extra
  /// satoshis per virtual byte of its own size on top of the original's fee.
  static const int incrementalRelayFee = 1;

  static const int _sighashAll = 1;
  static const int _txVersion = 2;

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

  /// Plans a BIP-125 replacement of the pending [original] at [feeRate].
  ///
  /// The replacement spends the same inputs and keeps every recipient output
  /// byte for byte; the extra fee comes only from the output that pays
  /// [changeScript]. It pays at least `feeRate × vsize`, and at least the
  /// original's fee plus the incremental relay fee for its own size — the rule
  /// that decides whether a node accepts the bump at all.
  ///
  /// Throws [BitcoinSigningException] with a user-facing reason whenever a safe
  /// replacement is impossible: already mined, never signalled RBF, inputs the
  /// wallet cannot sign, no change to take the fee from, or change too small.
  ///
  /// ponytail: speed-up only (no cancel), and the extra fee comes from change
  /// alone — no inputs are added, so a transfer without enough change is
  /// refused rather than rebuilt with more coins.
  static BitcoinPlan planReplacement({
    required BitcoinTxDetail original,
    required String ownAddress,
    required Uint8List changeScript,
    required int feeRate,
  }) {
    if (feeRate <= 0) {
      throw const BitcoinSigningException('Invalid fee rate.');
    }
    if (original.confirmed) {
      throw const BitcoinSigningException(
        'This transfer has already confirmed, so there is nothing to speed up.',
      );
    }
    if (!original.signalsRbf) {
      throw const BitcoinSigningException(
        'This transfer did not signal Replace-By-Fee (RBF), so the network '
        'will not accept a faster copy. It has to wait to confirm.',
      );
    }
    if (original.inputs.isEmpty || original.outputs.isEmpty) {
      throw const BitcoinSigningException('Could not read the transfer.');
    }
    final String own = ownAddress.toLowerCase();
    for (final BitcoinTxInputDetail input in original.inputs) {
      if (input.address?.toLowerCase() != own) {
        throw const BitcoinSigningException(
          'This transfer spends coins from another address, which this '
          'account cannot re-sign.',
        );
      }
    }

    BigInt totalIn = BigInt.zero;
    for (final BitcoinTxInputDetail input in original.inputs) {
      totalIn += input.value;
    }
    BigInt totalOut = BigInt.zero;
    for (final BitcoinTxOutputDetail output in original.outputs) {
      totalOut += output.value;
    }
    final BigInt originalFee = totalIn - totalOut;
    if (originalFee.isNegative) {
      throw const BitcoinSigningException('Could not read the transfer.');
    }

    final String changeHex = hex.encode(changeScript);
    int changeIndex = -1;
    for (int i = 0; i < original.outputs.length; i++) {
      if (hex.encode(original.outputs[i].scriptPubKey) == changeHex) {
        changeIndex = i;
      }
    }
    if (changeIndex < 0) {
      throw const BitcoinSigningException(
        'This transfer has no change output to take the extra fee from, so it '
        'cannot be bumped without reducing what the recipient gets.',
      );
    }

    BigInt requiredFee(int vsize) {
      final BigInt target = BigInt.from(feeRate * vsize);
      final BigInt floor = originalFee + BigInt.from(incrementalRelayFee * vsize);
      return target > floor ? target : floor;
    }

    final int inputCount = original.inputs.length;
    final List<BitcoinTxOutputDetail> outs = original.outputs;
    final BitcoinTxOutputDetail change = outs[changeIndex];

    final int vsizeWithChange = estimateVsize(inputCount, outs.length);
    final BigInt extra = requiredFee(vsizeWithChange) - originalFee;

    final List<BitcoinOutput> outputs;
    final BigInt newFee;
    final BigInt remainingChange;
    final int vsize;
    if (change.value - extra >= BigInt.from(dustLimit)) {
      remainingChange = change.value - extra;
      newFee = originalFee + extra;
      vsize = vsizeWithChange;
      outputs = <BitcoinOutput>[
        for (int i = 0; i < outs.length; i++)
          BitcoinOutput(
            value: i == changeIndex ? remainingChange : outs[i].value,
            scriptPubKey: outs[i].scriptPubKey,
          ),
      ];
    } else {
      // The change cannot stay above dust: fold all of it into the fee. The
      // smaller transaction must still clear the replacement minimum.
      vsize = estimateVsize(inputCount, outs.length - 1);
      newFee = originalFee + change.value;
      remainingChange = BigInt.zero;
      if (newFee < requiredFee(vsize)) {
        throw const BitcoinSigningException(
          'The change from this transfer is too small to pay for a faster '
          'copy. It has to wait to confirm.',
        );
      }
      outputs = <BitcoinOutput>[
        for (int i = 0; i < outs.length; i++)
          if (i != changeIndex)
            BitcoinOutput(value: outs[i].value, scriptPubKey: outs[i].scriptPubKey),
      ];
    }
    if (outputs.isEmpty) {
      throw const BitcoinSigningException(
        'This transfer has nothing left to send once the fee is raised.',
      );
    }

    BigInt amount = BigInt.zero;
    for (final BitcoinOutput output in outputs) {
      amount += output.value;
    }
    amount -= remainingChange;

    return BitcoinPlan(
      amount: amount,
      inputs: <BitcoinUtxo>[
        for (final BitcoinTxInputDetail input in original.inputs)
          BitcoinUtxo(txid: input.txid, vout: input.vout, value: input.value),
      ],
      outputs: outputs,
      fee: newFee,
      change: remainingChange,
      vsize: vsize,
      feeRate: (newFee.toInt() + vsize - 1) ~/ vsize,
      replacesTxid: original.txid,
      originalFee: originalFee,
    );
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
        BitcoinInput(txid: utxo.txid, vout: utxo.vout),
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
