import '../../core/utils/formatters.dart';
import '../../core/utils/units.dart';
import 'network_config.dart';

/// A single on-chain transaction, normalised across Bitcoin and EVM.
///
/// [amount] is signed and expressed in the smallest unit of the chain
/// (satoshi or wei): negative when the wallet sent funds.
class ChainTransaction {
  const ChainTransaction({
    required this.hash,
    required this.timestamp,
    required this.amount,
    required this.fee,
    required this.counterparty,
    required this.isIncoming,
    required this.confirmed,
    this.failed = false,
    this.nonce,
    this.maxFeePerGas,
    this.maxPriorityFeePerGas,
    this.gasLimit,
    this.rawInput,
    this.tokenSymbol,
    this.tokenDecimals,
    this.tokenAmount,
    this.tokenPeer,
  });

  final String hash;
  final DateTime timestamp;
  final BigInt amount;
  final BigInt fee;

  /// The other side of the transfer (sender or recipient).
  final String counterparty;

  final bool isIncoming;
  final bool confirmed;

  /// `true` for reverted EVM transactions.
  final bool failed;

  /// Sender's transaction count for EVM transactions, when the API reports it.
  ///
  /// Needed to replace a stuck transaction with the same nonce (a cancel).
  final int? nonce;

  /// EIP-1559 fee cap of the original transaction, in wei per gas.
  ///
  /// A replacement must bid above *this*, not above the current fast preset —
  /// the node rejects anything below the original's own fee cap + 10%.
  final BigInt? maxFeePerGas;

  /// Priority tip of the original transaction, in wei per gas.
  final BigInt? maxPriorityFeePerGas;

  /// Gas limit of the original transaction.
  final BigInt? gasLimit;

  /// Calldata of the original transaction as `0x…` hex, when the API exposes
  /// it. A speed-up must carry a byte-identical payload, so this is what lets
  /// a token transfer or approval be replaced at all.
  final String? rawInput;

  /// Ticker of the ERC-20 moved by this row, when it is a token transfer.
  ///
  /// The native [amount] and [fee] stay as the chain reported them — a token
  /// transfer still costs gas — and a replacement still needs the contract in
  /// [counterparty], so the token view lives in these separate fields.
  final String? tokenSymbol;
  final int? tokenDecimals;

  /// Unsigned token amount in the token's smallest unit.
  final BigInt? tokenAmount;

  /// The other side of the *token* transfer (the recipient or the sender),
  /// as opposed to [counterparty], which is the contract for a call.
  final String? tokenPeer;

  bool get isToken =>
      tokenSymbol != null && tokenDecimals != null && tokenAmount != null;

  /// `approve(address,uint256)` calldata: a permission, not a payment.
  bool get isApproval =>
      rawInput != null && rawInput!.toLowerCase().startsWith('0x095ea7b3');

  /// Who to show as the other side: the token peer when there is one.
  String get displayCounterparty => tokenPeer ?? counterparty;

  bool get isPending => !confirmed && !failed;

  /// This row with the token transfer [symbol]/[amount] to/from [peer]
  /// attached; everything native is kept as is.
  ChainTransaction withToken({
    required String symbol,
    required int decimals,
    required BigInt amount,
    required String peer,
  }) =>
      ChainTransaction(
        hash: hash,
        timestamp: timestamp,
        amount: this.amount,
        fee: fee,
        counterparty: counterparty,
        isIncoming: isIncoming,
        confirmed: confirmed,
        failed: failed,
        nonce: nonce,
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        gasLimit: gasLimit,
        rawInput: rawInput,
        tokenSymbol: symbol,
        tokenDecimals: decimals,
        tokenAmount: amount,
        tokenPeer: peer,
      );

  /// Formatted amount including the coin ticker, e.g. `-0.015 BTC`.
  String amountLabel(NetworkConfig network) {
    if (isToken) {
      return '${isIncoming ? '+' : '−'}'
          '${Units.formatWithSymbol(tokenAmount!, tokenDecimals!, tokenSymbol!)}';
    }
    final String sign = amount.isNegative ? '−' : '+';
    return '$sign${Units.formatWithSymbol(amount.abs(), network.decimals, network.symbol)}';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'hash': hash,
        'timestamp': timestamp.toIso8601String(),
        'amount': amount.toString(),
        'fee': fee.toString(),
        'counterparty': counterparty,
        'isIncoming': isIncoming,
        'confirmed': confirmed,
        'failed': failed,
        'nonce': nonce,
        'maxFeePerGas': maxFeePerGas?.toString(),
        'maxPriorityFeePerGas': maxPriorityFeePerGas?.toString(),
        'gasLimit': gasLimit?.toString(),
        'rawInput': rawInput,
        if (tokenSymbol != null) 'tokenSymbol': tokenSymbol,
        if (tokenDecimals != null) 'tokenDecimals': tokenDecimals,
        if (tokenAmount != null) 'tokenAmount': tokenAmount.toString(),
        if (tokenPeer != null) 'tokenPeer': tokenPeer,
      };

  factory ChainTransaction.fromJson(Map<String, Object?> json) =>
      ChainTransaction(
        hash: json['hash'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        amount: BigInt.parse(json['amount'] as String),
        fee: BigInt.parse(json['fee'] as String),
        counterparty: json['counterparty'] as String,
        isIncoming: json['isIncoming'] as bool? ?? false,
        confirmed: json['confirmed'] as bool? ?? false,
        failed: json['failed'] as bool? ?? false,
        nonce: (json['nonce'] as num?)?.toInt(),
        // Optional replacement fields: an older cache simply has none.
        maxFeePerGas: BigInt.tryParse(json['maxFeePerGas'] as String? ?? ''),
        maxPriorityFeePerGas:
            BigInt.tryParse(json['maxPriorityFeePerGas'] as String? ?? ''),
        gasLimit: BigInt.tryParse(json['gasLimit'] as String? ?? ''),
        rawInput: json['rawInput'] as String?,
        // Optional token fields: a cache written before token rows has none.
        tokenSymbol: json['tokenSymbol'] as String?,
        tokenDecimals: (json['tokenDecimals'] as num?)?.toInt(),
        tokenAmount: BigInt.tryParse(json['tokenAmount'] as String? ?? ''),
        tokenPeer: json['tokenPeer'] as String?,
      );
}

/// One ERC-20 `Transfer` event involving the wallet, from Blockscout's
/// `/addresses/{a}/token-transfers`.
class TokenTransfer {
  const TokenTransfer({
    required this.hash,
    required this.timestamp,
    required this.from,
    required this.to,
    required this.value,
    required this.symbol,
    required this.decimals,
    required this.contract,
  });

  /// Hash of the transaction that carried the event.
  final String hash;
  final DateTime timestamp;
  final String from;
  final String to;

  /// Amount in the token's smallest unit.
  final BigInt value;
  final String symbol;
  final int decimals;
  final String contract;
}

/// Where the next, older page of activity starts.
///
/// Opaque to callers: each chain fills the parts it paginates with. On
/// Blockscout the native list and the token-transfer list page independently,
/// so each keeps its own `next_page_params` (`null` once that side is
/// exhausted).
class ActivityCursor {
  const ActivityCursor({this.native, this.transfers});

  final Map<String, String>? native;
  final Map<String, String>? transfers;
}

/// One page of history as the API returned it, before token transfers are
/// folded into the native rows.
class ActivityPage {
  const ActivityPage({
    this.native = const <ChainTransaction>[],
    this.transfers = const <TokenTransfer>[],
    this.next,
  });

  final List<ChainTransaction> native;
  final List<TokenTransfer> transfers;

  /// Cursor for the following page, or `null` when this was the last.
  final ActivityCursor? next;
}

/// mempool.space's ready-made confirmation targets, in sat/vB.
///
/// The API publishes real tiers; multiplying one of them by 0.5 or 2 (as the
/// wallet used to) invents rates the network did not ask for. Each preset maps
/// to a tier directly: Slow → [hourFee], Normal → [halfHourFee],
/// Fast → [fastestFee].
class BitcoinFeeTiers {
  const BitcoinFeeTiers({
    required this.fastestFee,
    required this.halfHourFee,
    required this.hourFee,
  });

  /// Fee for the next block, ~10 minutes.
  final int fastestFee;

  /// Fee for ~30 minutes.
  final int halfHourFee;

  /// Fee for ~1 hour.
  final int hourFee;

  /// All three tiers from the `/v1/fees/recommended` JSON, or `null` when a
  /// tier is missing or nonsensical — the caller must not guess a fee.
  static BitcoinFeeTiers? fromJson(Map<String, Object?> json) {
    final int? fastest = _tier(json['fastestFee']);
    final int? halfHour = _tier(json['halfHourFee']);
    final int? hour = _tier(json['hourFee']);
    if (fastest == null || halfHour == null || hour == null) {
      return null;
    }
    return BitcoinFeeTiers(
      fastestFee: fastest,
      halfHourFee: halfHour,
      hourFee: hour,
    );
  }

  static int? _tier(Object? raw) {
    if (raw is num && raw > 0) {
      return raw.ceil();
    }
    return null;
  }
}

/// Spot price of the network's native coin plus its 24h change.
class CoinPrice {
  const CoinPrice({
    required this.usd,
    required this.change24h,
    this.eur,
    this.uah,
  });

  final double usd;

  /// Percentage change over the last 24 hours.
  final double change24h;

  /// Optional EUR and UAH spot prices from the same quote, used to derive live
  /// FX rates without a separate endpoint.
  final double? eur;
  final double? uah;

  /// Applies [eur] and [uah] to [AppCurrency] when both [usd] and the target
  /// quote are positive.
  void applyFxRates() {
    if (usd <= 0) {
      return;
    }
    AppCurrency.updateUsdRates(
      eur: eur != null ? eur! / usd : null,
      uah: uah != null ? uah! / usd : null,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'usd': usd,
        'change24h': change24h,
        if (eur != null) 'eur': eur,
        if (uah != null) 'uah': uah,
      };

  factory CoinPrice.fromJson(Map<String, Object?> json) {
    final CoinPrice price = CoinPrice(
      usd: (json['usd'] as num).toDouble(),
      change24h: (json['change24h'] as num?)?.toDouble() ?? 0,
      eur: (json['eur'] as num?)?.toDouble(),
      uah: (json['uah'] as num?)?.toDouble(),
    );
    price.applyFxRates();
    return price;
  }
}

/// An ERC-20 token balance returned by Blockscout.
class TokenBalance {
  const TokenBalance({
    required this.symbol,
    required this.name,
    required this.decimals,
    required this.balance,
    required this.contractAddress,
    this.usdRate,
  });

  final String symbol;
  final String name;
  final int decimals;

  /// Raw balance in the token's smallest unit.
  final BigInt balance;

  final String contractAddress;

  /// USD price per whole token, when Blockscout knows one.
  final double? usdRate;

  /// Whole-token amount as a `double`.
  double get amount => Units.toDouble(balance, decimals);

  /// Human readable amount, capped at six decimals.
  String get amountLabel => Units.format(
        balance,
        decimals,
        maxDecimals: decimals > 6 ? 6 : decimals,
      );

  /// USD value of the holding, or `null` without a rate.
  double? get usdValue => usdRate == null ? null : amount * usdRate!;

  Map<String, Object?> toJson() => <String, Object?>{
        'symbol': symbol,
        'name': name,
        'decimals': decimals,
        'balance': balance.toString(),
        'contractAddress': contractAddress,
        'usdRate': usdRate,
      };

  factory TokenBalance.fromJson(Map<String, Object?> json) => TokenBalance(
        symbol: json['symbol'] as String? ?? '?',
        name: json['name'] as String? ?? '',
        decimals: (json['decimals'] as num?)?.toInt() ?? 0,
        balance: BigInt.tryParse(json['balance'] as String? ?? '0') ?? BigInt.zero,
        contractAddress: json['contractAddress'] as String? ?? '',
        usdRate: (json['usdRate'] as num?)?.toDouble(),
      );
}

/// An ERC-20 approval this account has granted to a spender contract.
///
/// An approval lets [spender] move tokens out of the account at any time,
/// without asking again. It is the mechanism behind most "I approved a scam
/// contract and my balance is gone" losses, and the only in-wallet remedy is to
/// overwrite the allowance with zero.
class TokenApproval {
  const TokenApproval({
    required this.symbol,
    required this.tokenAddress,
    required this.spender,
    required this.amount,
    required this.decimals,
  });

  final String symbol;
  final String tokenAddress;
  final String spender;

  /// Approved amount in the token's smallest unit.
  final BigInt amount;

  final int decimals;

  /// `2^256 - 1`: the "infinite approval" that wallets still request, and the
  /// one that turns a single compromised contract into a full drain.
  static final BigInt unlimited = (BigInt.one << 256) - BigInt.one;

  bool get isUnlimited => amount >= unlimited;

  /// Human readable allowance, capped the same way token balances are.
  String get amountLabel => isUnlimited
      ? 'Unlimited'
      : Units.format(amount, decimals, maxDecimals: 4);
}

/// What the explorer knows about an address, fetched just before signing.
///
/// The signals that matter most: `is_scam` and whether the address *is* a
/// token contract — funds sent to a token contract are, with rare exceptions,
/// unrecoverable, and no amount of UI polish after the fact brings them back.
class AddressInfo {
  const AddressInfo({
    required this.isContract,
    required this.isScam,
    this.tokenSymbol,
    this.ensDomain,
  });

  factory AddressInfo.fromJson(Map<String, Object?> json) {
    final Object? token = json['token'];
    return AddressInfo(
      isContract: json['is_contract'] as bool? ?? false,
      isScam: json['is_scam'] as bool? ?? false,
      tokenSymbol: token is Map<String, Object?> ? token['symbol'] as String? : null,
      ensDomain: json['ens_domain_name'] as String?,
    );
  }

  /// A contract (Safe, exchange wallet, app) rather than a person.
  final bool isContract;

  /// Flagged by the explorer as a scam address.
  final bool isScam;

  /// Ticker of the token this address is the contract of, or `null` when it is
  /// not a token contract.
  final String? tokenSymbol;

  /// ENS name (`vitalik.eth`), when the explorer knows one.
  final String? ensDomain;

  bool get isTokenContract => tokenSymbol != null;
}

/// Everything the UI needs to render the account for the selected network.
class AccountSnapshot {
  const AccountSnapshot({
    required this.network,
    required this.address,
    required this.balance,
    required this.transactions,
    required this.chart,
    required this.fetchedAt,
    this.price,
    this.tokens = const <TokenBalance>[],
  });

  final NetworkConfig network;
  final String address;

  /// Native balance in the smallest unit.
  final BigInt balance;

  final List<ChainTransaction> transactions;

  /// ERC-20 holdings (empty on networks without token support).
  final List<TokenBalance> tokens;

  /// Normalised price series for the 24h chart (may be empty).
  final List<double> chart;

  final DateTime fetchedAt;
  final CoinPrice? price;

  /// Balance expressed in whole coins.
  double get nativeBalance => Units.toDouble(balance, network.decimals);

  /// Balance in USD, or `null` when the network has no market price.
  double? get fiatBalance =>
      price == null ? null : nativeBalance * price!.usd;

  /// Human readable native balance, e.g. `0.842`.
  String get nativeLabel => Units.format(balance, network.decimals);

  Map<String, Object?> toJson() => <String, Object?>{
        'networkId': network.id,
        'address': address,
        'balance': balance.toString(),
        'transactions':
            transactions.map((ChainTransaction t) => t.toJson()).toList(),
        'tokens': tokens.map((TokenBalance t) => t.toJson()).toList(),
        'chart': chart,
        'fetchedAt': fetchedAt.toIso8601String(),
        'price': price?.toJson(),
      };

  /// Rebuilds a snapshot from [toJson], or returns `null` when the payload is
  /// malformed or names a network this build does not know. Callers treat a
  /// `null` result as a cache miss.
  static AccountSnapshot? fromJson(Map<String, Object?> json) {
    try {
      final String networkId = json['networkId'] as String;
      final NetworkConfig network = NetworkCatalog.byId(networkId);
      if (network.id != networkId) {
        return null;
      }
      final List<Object?> transactions =
          json['transactions'] as List<Object?>? ?? const <Object?>[];
      final List<Object?> chart =
          json['chart'] as List<Object?>? ?? const <Object?>[];
      final List<Object?> tokens =
          json['tokens'] as List<Object?>? ?? const <Object?>[];
      final Object? price = json['price'];
      return AccountSnapshot(
        network: network,
        address: json['address'] as String,
        balance: BigInt.parse(json['balance'] as String),
        transactions: <ChainTransaction>[
          for (final Object? item in transactions)
            ChainTransaction.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
        ],
        tokens: <TokenBalance>[
          for (final Object? item in tokens)
            TokenBalance.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
        ],
        chart: <double>[
          for (final Object? value in chart) (value! as num).toDouble(),
        ],
        fetchedAt: DateTime.parse(json['fetchedAt'] as String),
        price: price == null
            ? null
            : CoinPrice.fromJson(
                (price as Map<Object?, Object?>).cast<String, Object?>(),
              ),
      );
    } catch (_) {
      // A corrupt cache is a cache miss, never a crash.
      return null;
    }
  }
}
