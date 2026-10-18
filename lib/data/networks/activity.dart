import 'chain_models.dart';

/// One ERC-20 transfer as the explorer lists it, before it is folded into the
/// activity feed.
class TokenTransfer {
  const TokenTransfer({
    required this.hash,
    required this.timestamp,
    required this.from,
    required this.to,
    required this.symbol,
    required this.contract,
    required this.decimals,
    required this.amount,
  });

  /// Hash of the transaction that carried the transfer.
  final String hash;
  final DateTime timestamp;
  final String from;
  final String to;
  final String symbol;
  final String contract;
  final int decimals;

  /// Raw amount in the token's smallest unit.
  final BigInt amount;

  /// The transfer as the wallet at [wallet] sees it: the other party is the
  /// recipient when the wallet sent it and the sender when it received it.
  TokenTransferInfo info(String wallet) => TokenTransferInfo(
        symbol: symbol,
        contract: contract,
        decimals: decimals,
        amount: amount,
        counterparty: from.toLowerCase() == wallet.toLowerCase() ? to : from,
      );
}

/// Where the next "Load more" continues, plus everything loaded so far.
///
/// The native list and the token-transfer list page independently, so the
/// cursor keeps both raw lists and re-merges them on every page: a transfer on
/// page 2 may belong to a transaction already shown on page 1.
class ActivityCursor {
  const ActivityCursor({
    required this.nativeRows,
    required this.transferRows,
    this.nativeNext,
    this.transferNext,
    this.lastConfirmedTxid,
  });

  /// Everything loaded from the native history so far.
  final List<ChainTransaction> nativeRows;

  /// Everything loaded from the token-transfer history so far.
  final List<TokenTransfer> transferRows;

  /// Blockscout `next_page_params` for each list; `null` once exhausted.
  final Map<String, Object?>? nativeNext;
  final Map<String, Object?>? transferNext;

  /// Bitcoin: the oldest confirmed txid seen, the cursor for the next page.
  final String? lastConfirmedTxid;

  bool get hasMore =>
      nativeNext != null || transferNext != null || lastConfirmedTxid != null;
}

/// A merged page of activity and the cursor to continue it, if any.
class ActivityPage {
  const ActivityPage({required this.transactions, this.next});

  final List<ChainTransaction> transactions;

  /// `null` when there is nothing older to load.
  final ActivityCursor? next;
}

/// Folds [transfers] into [natives], newest first.
///
/// * An outgoing transaction that carried an outgoing token transfer becomes
///   one row — "Sent 100 USDC" — that still holds the native fee.
/// * Every other transfer (an incoming one, a second leg of a swap, one whose
///   transaction the wallet did not send) is its own row with no fee: the
///   wallet did not pay for it.
///
/// The two lists page independently, so while either has older entries left,
/// anything older than the newest of their "oldest loaded" timestamps is held
/// back: past that point one list is complete and the other is not, and a row
/// shown there could still be split or merged by the next page.
List<ChainTransaction> mergeTokenTransfers({
  required List<ChainTransaction> natives,
  required List<TokenTransfer> transfers,
  required String address,
  bool nativeHasMore = false,
  bool transfersHasMore = false,
}) {
  final String wallet = address.toLowerCase();

  DateTime? windowStart;
  void narrow(DateTime? oldest) {
    if (oldest != null && (windowStart == null || oldest.isAfter(windowStart!))) {
      windowStart = oldest;
    }
  }

  if (nativeHasMore) {
    narrow(_oldest(<DateTime>[
      for (final ChainTransaction tx in natives)
        if (tx.confirmed) tx.timestamp,
    ]));
  }
  if (transfersHasMore) {
    narrow(_oldest(<DateTime>[
      for (final TokenTransfer transfer in transfers) transfer.timestamp,
    ]));
  }

  bool inWindow(DateTime timestamp) =>
      windowStart == null || !timestamp.isBefore(windowStart!);

  final Map<String, List<TokenTransfer>> byHash = <String, List<TokenTransfer>>{};
  for (final TokenTransfer transfer in transfers) {
    if (!inWindow(transfer.timestamp)) {
      continue;
    }
    if (transfer.from.toLowerCase() != wallet &&
        transfer.to.toLowerCase() != wallet) {
      continue;
    }
    byHash.putIfAbsent(transfer.hash.toLowerCase(), () => <TokenTransfer>[]).add(transfer);
  }

  final List<ChainTransaction> rows = <ChainTransaction>[];
  for (final ChainTransaction native in natives) {
    // A pending row has no real timestamp yet; it is always the newest.
    if (native.confirmed && !inWindow(native.timestamp)) {
      continue;
    }
    final List<TokenTransfer> own =
        byHash.remove(native.hash.toLowerCase()) ?? const <TokenTransfer>[];

    TokenTransfer? merged;
    if (!native.isIncoming) {
      for (final TokenTransfer transfer in own) {
        if (transfer.from.toLowerCase() == wallet) {
          merged = transfer;
          break;
        }
      }
    }
    rows.add(
      merged == null ? native : _withToken(native, merged.info(wallet)),
    );
    for (final TokenTransfer transfer in own) {
      if (!identical(transfer, merged)) {
        rows.add(_standalone(transfer, wallet));
      }
    }
  }

  // Transfers whose transaction is not in the native list (someone else sent
  // them, or it is outside the loaded window).
  for (final List<TokenTransfer> rest in byHash.values) {
    for (final TokenTransfer transfer in rest) {
      rows.add(_standalone(transfer, wallet));
    }
  }

  rows.sort(
    (ChainTransaction a, ChainTransaction b) => b.timestamp.compareTo(a.timestamp),
  );
  return rows;
}

DateTime? _oldest(List<DateTime> timestamps) {
  DateTime? oldest;
  for (final DateTime timestamp in timestamps) {
    if (oldest == null || timestamp.isBefore(oldest)) {
      oldest = timestamp;
    }
  }
  return oldest;
}

ChainTransaction _withToken(ChainTransaction native, TokenTransferInfo info) =>
    ChainTransaction(
      hash: native.hash,
      timestamp: native.timestamp,
      amount: native.amount,
      fee: native.fee,
      counterparty: native.counterparty,
      isIncoming: native.isIncoming,
      confirmed: native.confirmed,
      failed: native.failed,
      nonce: native.nonce,
      maxFeePerGas: native.maxFeePerGas,
      maxPriorityFeePerGas: native.maxPriorityFeePerGas,
      gasLimit: native.gasLimit,
      rawInput: native.rawInput,
      replaceable: native.replaceable,
      token: info,
    );

ChainTransaction _standalone(TokenTransfer transfer, String wallet) {
  final bool incoming =
      transfer.to.toLowerCase() == wallet && transfer.from.toLowerCase() != wallet;
  return ChainTransaction(
    hash: transfer.hash,
    timestamp: transfer.timestamp,
    amount: BigInt.zero,
    fee: BigInt.zero,
    counterparty: incoming ? transfer.from : transfer.to,
    isIncoming: incoming,
    confirmed: true,
    token: transfer.info(wallet),
  );
}
