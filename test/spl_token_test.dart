import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto_wallet/core/crypto/base58.dart';
import 'package:crypto_wallet/data/wallet/solana_signer.dart';
import 'package:crypto_wallet/data/wallet/spl_token_signer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vectors from the reference libraries — `solders` (Message, Transaction,
/// Pubkey.find_program_address through the `spl` package's
/// `get_associated_token_address`, `transfer_checked` and
/// `create_idempotent_associated_token_account`) — for one fixed ed25519 seed.
/// Ed25519 is deterministic, so even the signed transaction must match byte for
/// byte.
void main() {
  final Uint8List seed = Uint8List.fromList(hex.decode(
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
  ));
  Uint8List key(String base58) => Base58.decode(base58)!;
  final Uint8List sender = key('FAe4sisG95oZ42w7buUn5qEE4TAnfTTFPiguZUHmhiF');
  final Uint8List recipient = key('9C6hybhQ6Aycep9jaUnP6uL9ZYvDjUp1aSkFWPUFJtpj');
  final Uint8List mint = key('EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v');
  final Uint8List blockhash = Uint8List.fromList(hex.decode('0707070707070707070707070707070707070707070707070707070707070707'));
  final BigInt amount = BigInt.from(1234567);

  group('associated token accounts', () {
    test('match get_associated_token_address for both programs', () {
      expect(
        Base58.encode(SplTokenSigner.associatedTokenAddress(
          owner: sender,
          mint: mint,
          program: SplTokenProgram.token,
        )),
        'hkcktF2Akp3vj8pbBVJuxJfk5m41i4t4TSVLx2VoNHT',
      );
      expect(
        Base58.encode(SplTokenSigner.associatedTokenAddress(
          owner: recipient,
          mint: mint,
          program: SplTokenProgram.token,
        )),
        'FjCjyojZLVYVQ2dEdDKQx76msks96TdH9xqvc8BQ9UUx',
      );
      expect(
        Base58.encode(SplTokenSigner.associatedTokenAddress(
          owner: recipient,
          mint: mint,
          program: SplTokenProgram.token2022,
        )),
        'AHWqw6UbnmBi5MtTdkijNmBFZtBRj5WYk6Jz9AHWVs6T',
      );
    });

    test('a wallet key is on the curve, a derived address is not', () {
      expect(SplTokenSigner.isOnCurve(sender), isTrue);
      expect(SplTokenSigner.isOnCurve(recipient), isTrue);
      expect(
        SplTokenSigner.isOnCurve(SplTokenSigner.associatedTokenAddress(
          owner: sender,
          mint: mint,
          program: SplTokenProgram.token,
        )),
        isFalse,
      );
    });
  });

  group('TransferChecked transactions', () {
    test('token existing: message and signed transaction match the reference', () {
      final Uint8List message = SplTokenSigner.transferMessage(
        owner: sender,
        source: key('hkcktF2Akp3vj8pbBVJuxJfk5m41i4t4TSVLx2VoNHT'),
        recipientOwner: recipient,
        mint: mint,
        program: SplTokenProgram.token,
        amount: amount,
        decimals: 6,
        createDestination: false,
        recentBlockhash: blockhash,
      );
      expect(hex.encode(message),
          '0100020503a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b80a708cb86e928c50c0ba49e96841f3950f1717770744c8e4552f6d36b5b1037edad3495c8f1709e018e1c146a630b5f80e95ade5a9d2064c9af659e21ff16b5106ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9c6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d610707070707070707070707070707070707070707070707070707070707070707010304010402000a0c87d612000000000006');
      expect(
        hex.encode(SolanaSigner.signTransaction(privateSeed: seed, message: message)),
        '01e0e00f739252e063297d4cc51d0c888878b36b53a8d63432349184b1361c1c16c66bce131d4d1430f74b9f584e9e681d236b497bde51cde968e5ea0176fcc6090100020503a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b80a708cb86e928c50c0ba49e96841f3950f1717770744c8e4552f6d36b5b1037edad3495c8f1709e018e1c146a630b5f80e95ade5a9d2064c9af659e21ff16b5106ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9c6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d610707070707070707070707070707070707070707070707070707070707070707010304010402000a0c87d612000000000006',
      );
    });

    test('token create: message and signed transaction match the reference', () {
      final Uint8List message = SplTokenSigner.transferMessage(
        owner: sender,
        source: key('hkcktF2Akp3vj8pbBVJuxJfk5m41i4t4TSVLx2VoNHT'),
        recipientOwner: recipient,
        mint: mint,
        program: SplTokenProgram.token,
        amount: amount,
        decimals: 6,
        createDestination: true,
        recentBlockhash: blockhash,
      );
      expect(hex.encode(message),
          '0100050803a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b80a708cb86e928c50c0ba49e96841f3950f1717770744c8e4552f6d36b5b1037edad3495c8f1709e018e1c146a630b5f80e95ade5a9d2064c9af659e21ff16b51000000000000000000000000000000000000000000000000000000000000000006ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a979b5562e8fe654f94078b112e8a98ba7901f853ae695bed7e0e3910bad0496648c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859c6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d61070707070707070707070707070707070707070707070707070707070707070702060600020507030401010404010702000a0c87d612000000000006');
      expect(
        hex.encode(SolanaSigner.signTransaction(privateSeed: seed, message: message)),
        '01f9f77fb85c92dd58b6127ec2fe76cb34faa556c666b8443e22ff434d8c40430cd001577bf35e8f6fda3f73bda0d4b22c47dfb0ca495a75ae716ea5e70966de050100050803a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b80a708cb86e928c50c0ba49e96841f3950f1717770744c8e4552f6d36b5b1037edad3495c8f1709e018e1c146a630b5f80e95ade5a9d2064c9af659e21ff16b51000000000000000000000000000000000000000000000000000000000000000006ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a979b5562e8fe654f94078b112e8a98ba7901f853ae695bed7e0e3910bad0496648c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859c6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d61070707070707070707070707070707070707070707070707070707070707070702060600020507030401010404010702000a0c87d612000000000006',
      );
    });

    test('token2022 existing: message and signed transaction match the reference', () {
      final Uint8List message = SplTokenSigner.transferMessage(
        owner: sender,
        source: key('EkXQtsTsR8ZCB47f3yDJA46gy6tQfQz9N85WBZBPCVQA'),
        recipientOwner: recipient,
        mint: mint,
        program: SplTokenProgram.token2022,
        amount: amount,
        decimals: 6,
        createDestination: false,
        recentBlockhash: blockhash,
      );
      expect(hex.encode(message),
          '0100020503a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b889f438394357de5498714e3736c4ef888ca753e05d019dd0771a46a8aca97eb4cc4e4ab0a58c67c4c32025db4f0538f3bcf8d69e538e4fe9336180dadb3f668706ddf6e1ee758fde18425dbce46ccddab61afc4d83b90d27febdf928d8a18bfcc6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d610707070707070707070707070707070707070707070707070707070707070707010304020401000a0c87d612000000000006');
      expect(
        hex.encode(SolanaSigner.signTransaction(privateSeed: seed, message: message)),
        '01fc03e017b5b647da7195bf670124c2aa0441601b370df7d0eda7c737aa906e53e8cc84eaa79a45fdc5b9002da8413ebcda971ec3db4e87bcb42189fbe825ce0f0100020503a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b889f438394357de5498714e3736c4ef888ca753e05d019dd0771a46a8aca97eb4cc4e4ab0a58c67c4c32025db4f0538f3bcf8d69e538e4fe9336180dadb3f668706ddf6e1ee758fde18425dbce46ccddab61afc4d83b90d27febdf928d8a18bfcc6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d610707070707070707070707070707070707070707070707070707070707070707010304020401000a0c87d612000000000006',
      );
    });

    test('token2022 create: message and signed transaction match the reference', () {
      final Uint8List message = SplTokenSigner.transferMessage(
        owner: sender,
        source: key('EkXQtsTsR8ZCB47f3yDJA46gy6tQfQz9N85WBZBPCVQA'),
        recipientOwner: recipient,
        mint: mint,
        program: SplTokenProgram.token2022,
        amount: amount,
        decimals: 6,
        createDestination: true,
        recentBlockhash: blockhash,
      );
      expect(hex.encode(message),
          '0100050803a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b889f438394357de5498714e3736c4ef888ca753e05d019dd0771a46a8aca97eb4cc4e4ab0a58c67c4c32025db4f0538f3bcf8d69e538e4fe9336180dadb3f6687000000000000000000000000000000000000000000000000000000000000000006ddf6e1ee758fde18425dbce46ccddab61afc4d83b90d27febdf928d8a18bfc79b5562e8fe654f94078b112e8a98ba7901f853ae695bed7e0e3910bad0496648c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859c6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d61070707070707070707070707070707070707070707070707070707070707070702060600010507030401010404020701000a0c87d612000000000006');
      expect(
        hex.encode(SolanaSigner.signTransaction(privateSeed: seed, message: message)),
        '013914029baac285670f4417ff33473fb25bb0042a388bd6a092a9a20a1fb565dd425043bb65bb5f42adb628a75e7a0d107ba6c65d29d5d7200228413d52b05c0d0100050803a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b889f438394357de5498714e3736c4ef888ca753e05d019dd0771a46a8aca97eb4cc4e4ab0a58c67c4c32025db4f0538f3bcf8d69e538e4fe9336180dadb3f6687000000000000000000000000000000000000000000000000000000000000000006ddf6e1ee758fde18425dbce46ccddab61afc4d83b90d27febdf928d8a18bfc79b5562e8fe654f94078b112e8a98ba7901f853ae695bed7e0e3910bad0496648c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859c6fa7af3bedbad3a3d65f36aabc97431b1bbe4c2d2f6e0e47ca60203452f5d61070707070707070707070707070707070707070707070707070707070707070702060600010507030401010404020701000a0c87d612000000000006',
      );
    });

    test('refuses a self-send, a zero amount and a bad key', () {
      Uint8List build({
        Uint8List? to,
        BigInt? amt,
        Uint8List? bh,
      }) =>
          SplTokenSigner.transferMessage(
            owner: sender,
            source: key('hkcktF2Akp3vj8pbBVJuxJfk5m41i4t4TSVLx2VoNHT'),
            recipientOwner: to ?? recipient,
            mint: mint,
            program: SplTokenProgram.token,
            amount: amt ?? amount,
            decimals: 6,
            createDestination: false,
            recentBlockhash: bh ?? blockhash,
          );
      expect(() => build(to: sender), throwsA(isA<SolanaSigningException>()));
      expect(() => build(amt: BigInt.zero), throwsA(isA<SolanaSigningException>()));
      expect(() => build(bh: Uint8List(5)), throwsA(isA<SolanaSigningException>()));
    });
  });

  test('only the two known token programs are recognised', () {
    expect(SplTokenProgram.fromAddress(SplTokenProgram.token.address),
        SplTokenProgram.token);
    expect(SplTokenProgram.fromAddress(SplTokenProgram.token2022.address),
        SplTokenProgram.token2022);
    expect(SplTokenProgram.fromAddress('11111111111111111111111111111111'), isNull);
    expect(SplTokenProgram.fromAddress(null), isNull);
  });
}
