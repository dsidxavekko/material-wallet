import 'chain_models.dart';

/// Folds ERC-20 transfer events into the native transaction list.
///
/// Blockscout's `/transactions` knows a token send only as a contract call
/// that moved no ETH, so on its own it reads "Sent ETH −fee" with the token
/// contract as recipient, and a token *received* is not in it at all. The
/// `/token-transfers` feed has the real amounts and peers; this joins the two
/// on the transaction hash:
///
/// * an outgoing call whose hash has an outgoing transfer gets the token
///   fields — the gas fee stays on the row and the contract stays in
///   `counterparty` (a speed-up needs it as the `to` address);
/// * every other transfer (tokens received, a swap's incoming leg, a second
///   transfer inside one call) becomes its own row with no native amount.
///
/// Pure and order-independent, so pages can be merged again after more arrive.
List<ChainTransaction> mergeTokenTransfers({
  required List<ChainTransaction> native,
  required List<TokenTransfer> transfers,
  required String address,
}) {
  final String me = address.toLowerCase();
  final Map<String, ChainTransaction> byHash = <String, ChainTransaction>{
    for (final ChainTransaction tx in native) tx.hash.toLowerCase(): tx,
  };

  final Map<String, ChainTransaction> annotated = <String, ChainTransaction>{};
  final List<ChainTransaction> extra = <ChainTransaction>[];

  for (final TokenTransfer transfer in transfers) {
    final String key = transfer.hash.toLowerCase();
    final bool outgoing = transfer.from.toLowerCase() == me;
    final ChainTransaction? call = byHash[key];

    if (call != null &&
        !call.isIncoming &&
        outgoing &&
        !annotated.containsKey(key)) {
      annotated[key] = call.withToken(
        symbol: transfer.symbol,
        decimals: transfer.decimals,
        amount: transfer.value,
        peer: transfer.to,
      );
      continue;
    }

    final String peer = outgoing ? transfer.to : transfer.from;
    extra.add(
      ChainTransaction(
        hash: transfer.hash,
        timestamp: transfer.timestamp,
        amount: BigInt.zero,
        fee: BigInt.zero,
        counterparty: peer,
        isIncoming: !outgoing,
        confirmed: true,
        tokenSymbol: transfer.symbol,
        tokenDecimals: transfer.decimals,
        tokenAmount: transfer.value,
        tokenPeer: peer,
      ),
    );
  }

  final List<ChainTransaction> rows = <ChainTransaction>[
    for (final ChainTransaction tx in native)
      annotated[tx.hash.toLowerCase()] ?? tx,
    ...extra,
  ];

  // Newest first; the original position breaks ties so the result is stable.
  final List<int> order = List<int>.generate(rows.length, (int i) => i)
    ..sort((int a, int b) {
      final int byTime = rows[b].timestamp.compareTo(rows[a].timestamp);
      return byTime != 0 ? byTime : a.compareTo(b);
    });
  return <ChainTransaction>[for (final int i in order) rows[i]];
}
