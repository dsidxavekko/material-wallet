import 'dart:typed_data';

import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/features/send/replace_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which replacements the activity list offers, and for what.
///
/// Offering the wrong one wastes a fee: a speed-up that changes the payload is
/// rejected by the node, and a speed-up priced below the original's own cap is
/// rejected as underpriced.
void main() {
  ChainTransaction pending({
    required String counterparty,
    bool incoming = false,
    bool confirmed = false,
    bool failed = false,
    int? nonce = 7,
    BigInt? maxFeePerGas,
    BigInt? maxPriorityFeePerGas,
    String? rawInput,
  }) =>
      ChainTransaction(
        hash: '0xabc',
        timestamp: DateTime.utc(2026),
        amount: -BigInt.from(1000),
        fee: BigInt.from(21),
        counterparty: counterparty,
        isIncoming: incoming,
        confirmed: confirmed,
        failed: failed,
        nonce: nonce,
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        rawInput: rawInput,
      );

  List<ReplacementKind> kindsFor(
    ChainTransaction tx, {
    NetworkConfig network = NetworkCatalog.sepolia,
    List<TokenBalance> tokens = const <TokenBalance>[],
  }) =>
      replacementKindsFor(original: tx, network: network, tokens: tokens);

  test('offers both replacements for a pending native transfer', () {
    expect(
      kindsFor(pending(counterparty: '0xabc')),
      <ReplacementKind>[ReplacementKind.speedUp, ReplacementKind.cancel],
    );
  });

  test('offers only a cancel for a token transfer without exposed calldata',
      () {
    // A replacement must carry a byte-identical payload. When the history API
    // did not expose `raw_input` the calldata is not recoverable, so a
    // speed-up would be rejected. Cancelling needs no payload and still works.
    final List<TokenBalance> tokens = <TokenBalance>[
      TokenBalance(
        symbol: 'USDT',
        name: 'Tether',
        decimals: 6,
        balance: BigInt.from(1000000),
        contractAddress: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
      ),
    ];

    expect(
      kindsFor(
        pending(counterparty: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48'),
        tokens: tokens,
      ),
      <ReplacementKind>[ReplacementKind.cancel],
    );
  });

  test('offers a speed-up for a token transfer whose calldata is exposed', () {
    final List<TokenBalance> tokens = <TokenBalance>[
      TokenBalance(
        symbol: 'USDT',
        name: 'Tether',
        decimals: 6,
        balance: BigInt.from(1000000),
        contractAddress: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
      ),
    ];

    expect(
      kindsFor(
        pending(
          counterparty: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
          // ERC-20 transfer(selector + recipient + amount).
          rawInput: '0xa9059cbb'
              '0000000000000000000000003535353535353535353535353535353535353535'
              '000000000000000000000000000000000000000000000000000000000de0b6b3a'
              '7640000',
        ),
        tokens: tokens,
      ),
      <ReplacementKind>[ReplacementKind.speedUp, ReplacementKind.cancel],
    );
  });

  test('offers nothing for a settled, failed or incoming transaction', () {
    expect(kindsFor(pending(counterparty: '0xabc', confirmed: true)), isEmpty);
    expect(kindsFor(pending(counterparty: '0xabc', failed: true)), isEmpty);
    expect(
      kindsFor(pending(counterparty: '0xabc', incoming: true)),
      isEmpty,
    );
  });

  test('offers nothing without a nonce — a replacement needs one', () {
    expect(kindsFor(pending(counterparty: '0xabc', nonce: null)), isEmpty);
  });

  test('offers only a speed-up on Bitcoin, and nothing where it cannot sign', () {
    // Bitcoin replaces by rebuilding the transfer (RBF); there is no cancel.
    expect(
      kindsFor(pending(counterparty: 'bc1q'), network: NetworkCatalog.bitcoin),
      <ReplacementKind>[ReplacementKind.speedUp],
    );
    expect(
      kindsFor(pending(counterparty: 'So111'), network: NetworkCatalog.solana),
      isEmpty,
    );
  });

  group('replacementFeeFor', () {
    // A node applies the geth rule: both the cap and the tip of the
    // replacement must be at least 110% of the original's own values.
    final ({BigInt baseFee, BigInt maxPriorityFeePerGas, BigInt gasLimit})
        quote = (
      baseFee: BigInt.from(10),
      maxPriorityFeePerGas: BigInt.from(10),
      gasLimit: BigInt.from(21000),
    );

    test('prices a replacement at ≥110% of the original when caps are known',
        () {
      final ChainTransaction original = pending(
        counterparty: '0xabc',
        maxFeePerGas: BigInt.from(1000),
        maxPriorityFeePerGas: BigInt.from(100),
      );

      final ({BigInt maxFeePerGas, BigInt maxPriorityFeePerGas}) fee =
          replacementFeeFor(original: original, quote: quote);

      // 110% of 1000 = 1100, +1 wei so the node never sees "not enough".
      expect(fee.maxFeePerGas, greaterThanOrEqualTo(BigInt.from(1100)));
      expect(fee.maxPriorityFeePerGas, greaterThanOrEqualTo(BigInt.from(110)));
    });

    test('never prices below the fast preset when the original was cheaper',
        () {
      final ChainTransaction original = pending(
        counterparty: '0xabc',
        maxFeePerGas: BigInt.from(1),
        maxPriorityFeePerGas: BigInt.from(1),
      );

      final ({BigInt maxFeePerGas, BigInt maxPriorityFeePerGas}) fee =
          replacementFeeFor(original: original, quote: quote);

      // fast preset: cap = 2×baseFee + 2×tip = 40, tip = 20.
      expect(fee.maxFeePerGas, BigInt.from(40));
      expect(fee.maxPriorityFeePerGas, BigInt.from(20));
    });

    test('falls back to the fast preset when the original caps are unknown',
        () {
      final ChainTransaction original = pending(counterparty: '0xabc');

      final ({BigInt maxFeePerGas, BigInt maxPriorityFeePerGas}) fee =
          replacementFeeFor(original: original, quote: quote);

      expect(fee.maxFeePerGas, BigInt.from(40));
      expect(fee.maxPriorityFeePerGas, BigInt.from(20));
    });
  });

  group('speedUpCalldata', () {
    test('reproduces the original raw_input byte for byte', () {
      const String raw =
          '0xa9059cbb'
          '0000000000000000000000003535353535353535353535353535353535353535'
          '000000000000000000000000000000000000000000000000000000000de0b6b3a'
          '7640000';

      final Uint8List? bytes = speedUpCalldata(
        pending(counterparty: '0xabc', rawInput: raw),
      );

      expect(bytes, isNotNull);
      expect(bytes!.length, (raw.length - 2) ~/ 2);
      // The selector must survive the round trip intact.
      expect(bytes.sublist(0, 4), <int>[0xa9, 0x05, 0x9c, 0xbb]);
    });

    test('is null for a plain native transfer (empty calldata)', () {
      expect(
        speedUpCalldata(pending(counterparty: '0xabc', rawInput: '0x')),
        isNull,
      );
      expect(speedUpCalldata(pending(counterparty: '0xabc')), isNull);
    });

    test('is null for malformed hex instead of throwing', () {
      expect(
        speedUpCalldata(pending(counterparty: '0xabc', rawInput: '0xzz')),
        isNull,
      );
    });
  });
}
