import 'dart:typed_data';

import '../../core/crypto/base58.dart';
import '../../core/crypto/hashing.dart';
import 'solana_signer.dart';

/// Which program owns a mint (and so every token account of it).
enum SplTokenProgram {
  /// The original SPL Token program.
  token('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'),

  /// Token-2022 (token extensions).
  token2022('TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb');

  const SplTokenProgram(this.address);

  final String address;

  Uint8List get bytes => Base58.decode(address)!;

  /// The program for a mint's `owner`, or `null` for anything this wallet does
  /// not know how to move.
  static SplTokenProgram? fromAddress(String? address) {
    for (final SplTokenProgram p in SplTokenProgram.values) {
      if (p.address == address) {
        return p;
      }
    }
    return null;
  }
}

/// Builds the transaction that moves an SPL token between wallets.
///
/// A token lives in a *token account*, not in the wallet's own account. The
/// recipient receives it in their **associated token account** for that mint —
/// an address derived from (owner, token program, mint) — and if it does not
/// exist yet the sender's transaction creates it (and pays its rent). The
/// transfer itself is `TransferChecked`, which makes the program verify the
/// mint and its decimals, so a wrong mint or a mistaken decimal count fails
/// instead of moving a different amount.
///
/// Pure Dart. The account derivation and both message layouts are pinned by
/// vectors from `solders` and the `spl` Python package (the reference
/// libraries): `test/spl_token_test.dart`.
class SplTokenSigner {
  const SplTokenSigner._();

  /// The Associated Token Account program.
  static final Uint8List associatedTokenProgram =
      Base58.decode('ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL')!;

  /// The System Program (32 zero bytes).
  static final Uint8List systemProgram = Uint8List(32);

  static const String _pdaMarker = 'ProgramDerivedAddress';

  // --- program derived addresses -------------------------------------------

  /// The first bump (counting down from 255) for which the hash of the seeds is
  /// *not* a valid ed25519 point, so no private key can exist for the address.
  static ({Uint8List address, int bump}) findProgramAddress(
    List<Uint8List> seeds,
    Uint8List programId,
  ) {
    for (int bump = 255; bump >= 0; bump--) {
      final Uint8List hash = Hashing.sha256(
        Uint8List.fromList(<int>[
          for (final Uint8List s in seeds) ...s,
          bump,
          ...programId,
          ..._pdaMarker.codeUnits,
        ]),
      );
      if (!isOnCurve(hash)) {
        return (address: hash, bump: bump);
      }
    }
    throw const SolanaSigningException('Could not derive a token account.');
  }

  /// The address of [owner]'s associated token account for [mint].
  static Uint8List associatedTokenAddress({
    required Uint8List owner,
    required Uint8List mint,
    required SplTokenProgram program,
  }) =>
      findProgramAddress(
        <Uint8List>[owner, program.bytes, mint],
        associatedTokenProgram,
      ).address;

  static final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
  // d = -121665 / 121666 (mod p), the Edwards25519 curve constant.
  static final BigInt _d = (_p - BigInt.from(121665)) *
          BigInt.from(121666).modInverse(_p) %
      _p;

  /// Whether the 32 bytes decompress to a point on Ed25519 (the check
  /// `Pubkey::find_program_address` uses to reject a candidate).
  static bool isOnCurve(Uint8List bytes) {
    if (bytes.length != 32) {
      return false;
    }
    BigInt y = BigInt.zero;
    for (int i = 31; i >= 0; i--) {
      y = (y << 8) | BigInt.from(i == 31 ? bytes[i] & 0x7f : bytes[i]);
    }
    y %= _p;
    final BigInt y2 = y * y % _p;
    final BigInt u = (y2 - BigInt.one) % _p;
    final BigInt v = (_d * y2 + BigInt.one) % _p;
    if (v == BigInt.zero) {
      return false;
    }
    // x² = u / v must be a square mod p (Euler's criterion).
    final BigInt x2 = u * v.modInverse(_p) % _p;
    if (x2 == BigInt.zero) {
      return true;
    }
    return x2.modPow((_p - BigInt.one) >> 1, _p) == BigInt.one;
  }

  // --- the message ----------------------------------------------------------

  /// The message to sign: move [amount] (smallest units, of a token with
  /// [decimals]) of [mint] from the token account [source], owned and paid for
  /// by [owner], to [recipientOwner]'s associated token account.
  ///
  /// With [createDestination] the message first creates that account
  /// (idempotently: a no-op if someone made it in the meantime).
  static Uint8List transferMessage({
    required Uint8List owner,
    required Uint8List source,
    required Uint8List recipientOwner,
    required Uint8List mint,
    required SplTokenProgram program,
    required BigInt amount,
    required int decimals,
    required bool createDestination,
    required Uint8List recentBlockhash,
  }) {
    for (final Uint8List k in <Uint8List>[
      owner,
      source,
      recipientOwner,
      mint,
      recentBlockhash,
    ]) {
      if (k.length != 32) {
        throw const SolanaSigningException('Malformed key or blockhash.');
      }
    }
    if (_equal(owner, recipientOwner)) {
      throw const SolanaSigningException(
        'Sending to your own address does nothing.',
      );
    }
    if (amount <= BigInt.zero || amount >= (BigInt.one << 64)) {
      throw const SolanaSigningException('Invalid amount.');
    }
    if (decimals < 0 || decimals > 255) {
      throw const SolanaSigningException('Invalid token decimals.');
    }

    final Uint8List destination = associatedTokenAddress(
      owner: recipientOwner,
      mint: mint,
      program: program,
    );
    if (_equal(destination, source)) {
      throw const SolanaSigningException(
        'The token would go back to the account it comes from.',
      );
    }

    // TokenInstruction::TransferChecked = 12 ‖ u64 LE amount ‖ u8 decimals.
    final Uint8List data = Uint8List(10)..[0] = 12;
    for (int i = 0; i < 8; i++) {
      data[1 + i] = ((amount >> (8 * i)) & BigInt.from(0xff)).toInt();
    }
    data[9] = decimals;

    final SolanaInstruction transfer = SolanaInstruction(
      programId: program.bytes,
      accounts: <SolanaAccountMeta>[
        SolanaAccountMeta(source, writable: true),
        SolanaAccountMeta(mint),
        SolanaAccountMeta(destination, writable: true),
        SolanaAccountMeta(owner, signer: true),
      ],
      data: data,
    );
    // Associated Token Account program, instruction 1 = CreateIdempotent.
    final SolanaInstruction create = SolanaInstruction(
      programId: associatedTokenProgram,
      accounts: <SolanaAccountMeta>[
        SolanaAccountMeta(owner, signer: true, writable: true),
        SolanaAccountMeta(destination, writable: true),
        SolanaAccountMeta(recipientOwner),
        SolanaAccountMeta(mint),
        SolanaAccountMeta(systemProgram),
        SolanaAccountMeta(program.bytes),
      ],
      data: Uint8List.fromList(<int>[1]),
    );

    return SolanaSigner.compileMessage(
      payer: owner,
      instructions: <SolanaInstruction>[
        if (createDestination) create,
        transfer,
      ],
      recentBlockhash: recentBlockhash,
    );
  }

  static bool _equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
