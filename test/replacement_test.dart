import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/features/send/replace_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which replacements the activity list offers, and for what.
///
/// Offering the wrong one wastes a fee: a speed-up that changes the payload is
/// rejected by the node, and a speed-up of a token transfer can never be built
/// from the history API at all.
void main() {
  ChainTransaction pending({
    required String counterparty,
    bool incoming = false,
    bool confirmed = false,
    bool failed = false,
    int? nonce = 7,
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

  test('offers only a cancel for a token transfer', () {
    // The calldata of a token transfer is not recoverable from the history
    // API, so a replacement would carry a different payload — which EIP-1559
    // rules reject. Cancelling needs no payload and still works.
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

  test('offers nothing on a chain the wallet cannot sign for', () {
    expect(
      kindsFor(pending(counterparty: 'bc1q'), network: NetworkCatalog.bitcoin),
      isEmpty,
    );
    expect(
      kindsFor(pending(counterparty: 'So111'), network: NetworkCatalog.solana),
      isEmpty,
    );
  });
}
