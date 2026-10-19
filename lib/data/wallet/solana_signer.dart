import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

/// Thrown when a Solana transfer cannot be built or signed.
class SolanaSigningException implements Exception {
  const SolanaSigningException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// An account an instruction touches.
class SolanaAccountMeta {
  const SolanaAccountMeta(
    this.publicKey, {
    this.signer = false,
    this.writable = false,
  });

  final Uint8List publicKey;
  final bool signer;
  final bool writable;
}

/// One instruction: the program to run, the accounts it reads or writes, and
/// its data.
class SolanaInstruction {
  const SolanaInstruction({
    required this.programId,
    required this.accounts,
    required this.data,
  });

  final Uint8List programId;
  final List<SolanaAccountMeta> accounts;
  final Uint8List data;
}

/// Builds and signs a native SOL transfer as a legacy-format transaction.
///
/// Pure Dart, no SDK: the wire format is small and fixed, and it is pinned by
/// a vector generated with the official `solana-sdk` bindings (`solders`).
///
/// Layout of the message (what is signed):
/// * header — 1 required signature, 0 read-only signed, 1 read-only unsigned
///   (the System Program);
/// * account keys — sender, recipient, System Program;
/// * recent blockhash — 32 bytes;
/// * one instruction — program index 2, accounts `[0, 1]`, data =
///   `u32 LE 2` (System `Transfer`) ‖ `u64 LE lamports`.
///
/// The transaction is `compact-u16(1) ‖ signature(64) ‖ message`.
class SolanaSigner {
  const SolanaSigner._();

  /// The System Program id `11111111111111111111111111111111` is 32 zero bytes.
  static const int _publicKeyLength = 32;

  /// `compact-u16`: Solana's 1–3 byte little-endian varint for lengths < 2^16.
  static Uint8List compactU16(int value) {
    if (value < 0 || value > 0xffff) {
      throw ArgumentError.value(value, 'value', 'must fit in 16 bits');
    }
    final List<int> out = <int>[];
    int rest = value;
    while (true) {
      final int low = rest & 0x7f;
      rest >>= 7;
      if (rest == 0) {
        out.add(low);
        break;
      }
      out.add(low | 0x80);
    }
    return Uint8List.fromList(out);
  }

  /// The message to sign for sending [lamports] from [from] to [to], valid
  /// until [recentBlockhash] expires.
  static Uint8List transferMessage({
    required Uint8List from,
    required Uint8List to,
    required BigInt lamports,
    required Uint8List recentBlockhash,
  }) {
    if (from.length != _publicKeyLength ||
        to.length != _publicKeyLength ||
        recentBlockhash.length != 32) {
      throw const SolanaSigningException('Malformed key or blockhash.');
    }
    if (_equal(from, to)) {
      throw const SolanaSigningException(
        'Sending to your own address does nothing.',
      );
    }
    if (lamports <= BigInt.zero || lamports >= (BigInt.one << 64)) {
      throw const SolanaSigningException('Invalid amount.');
    }

    final Uint8List data = Uint8List(12);
    final ByteData view = ByteData.sublistView(data);
    view.setUint32(0, 2, Endian.little); // SystemInstruction::Transfer
    for (int i = 0; i < 8; i++) {
      data[4 + i] = ((lamports >> (8 * i)) & BigInt.from(0xff)).toInt();
    }

    return Uint8List.fromList(<int>[
      1, 0, 1, // header
      ...compactU16(3), // account count
      ...from,
      ...to,
      ...Uint8List(32), // System Program
      ...recentBlockhash,
      ...compactU16(1), // instruction count
      2, // program id index
      ...compactU16(2), 0, 1, // account indexes: sender, recipient
      ...compactU16(data.length),
      ...data,
    ]);
  }

  /// Compiles [instructions] into a legacy message paid for by [payer].
  ///
  /// The account list is ordered the way the reference compiler does it —
  /// writable signers (the payer first), read-only signers, writable others,
  /// read-only others, each group sorted by key — so a message built here is
  /// byte-identical to one from `solders` / the Rust SDK for the same
  /// instructions. A program id is an account too (read-only).
  static Uint8List compileMessage({
    required Uint8List payer,
    required List<SolanaInstruction> instructions,
    required Uint8List recentBlockhash,
  }) {
    if (payer.length != _publicKeyLength || recentBlockhash.length != 32) {
      throw const SolanaSigningException('Malformed key or blockhash.');
    }
    final Map<String, ({Uint8List key, bool signer, bool writable})> merged =
        <String, ({Uint8List key, bool signer, bool writable})>{};
    void add(Uint8List key, {bool signer = false, bool writable = false}) {
      final String id = key.join(',');
      final existing = merged[id];
      merged[id] = (
        key: key,
        signer: signer || (existing?.signer ?? false),
        writable: writable || (existing?.writable ?? false),
      );
    }

    add(payer, signer: true, writable: true);
    for (final SolanaInstruction ix in instructions) {
      for (final SolanaAccountMeta m in ix.accounts) {
        add(m.publicKey, signer: m.signer, writable: m.writable);
      }
      add(ix.programId);
    }

    int compare(Uint8List a, Uint8List b) {
      for (int i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          return a[i] - b[i];
        }
      }
      return 0;
    }

    List<Uint8List> group(bool signer, bool writable) => <Uint8List>[
          for (final v in merged.values)
            if (v.signer == signer &&
                v.writable == writable &&
                !_equal(v.key, payer))
              v.key,
        ]..sort(compare);

    final List<Uint8List> writableSigners = <Uint8List>[
      payer,
      ...group(true, true),
    ];
    final List<Uint8List> readonlySigners = group(true, false);
    final List<Uint8List> writableOthers = group(false, true);
    final List<Uint8List> readonlyOthers = group(false, false);
    final List<Uint8List> keys = <Uint8List>[
      ...writableSigners,
      ...readonlySigners,
      ...writableOthers,
      ...readonlyOthers,
    ];
    int indexOf(Uint8List key) =>
        keys.indexWhere((Uint8List k) => _equal(k, key));

    return Uint8List.fromList(<int>[
      writableSigners.length + readonlySigners.length,
      readonlySigners.length,
      readonlyOthers.length,
      ...compactU16(keys.length),
      for (final Uint8List k in keys) ...k,
      ...recentBlockhash,
      ...compactU16(instructions.length),
      for (final SolanaInstruction ix in instructions) ...<int>[
        indexOf(ix.programId),
        ...compactU16(ix.accounts.length),
        for (final SolanaAccountMeta m in ix.accounts) indexOf(m.publicKey),
        ...compactU16(ix.data.length),
        ...ix.data,
      ],
    ]);
  }

  /// Signs [message] with the ed25519 [privateSeed] and returns the full
  /// serialised transaction ready for `sendTransaction`.
  static Uint8List signTransaction({
    required Uint8List privateSeed,
    required Uint8List message,
  }) {
    final ed.PrivateKey key = ed.newKeyFromSeed(privateSeed);
    final Uint8List signature = ed.sign(key, message);
    return Uint8List.fromList(<int>[
      ...compactU16(1),
      ...signature,
      ...message,
    ]);
  }

  static bool _equal(Uint8List a, Uint8List b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
