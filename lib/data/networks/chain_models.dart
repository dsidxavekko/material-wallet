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

  bool get isPending => !confirmed && !failed;

  /// Formatted amount including the coin ticker, e.g. `-0.015 BTC`.
  String amountLabel(NetworkConfig network) {
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
      );
}

/// Spot price of the network's native coin plus its 24h change.
class CoinPrice {
  const CoinPrice({required this.usd, required this.change24h});

  final double usd;

  /// Percentage change over the last 24 hours.
  final double change24h;

  Map<String, Object?> toJson() => <String, Object?>{
        'usd': usd,
        'change24h': change24h,
      };

  factory CoinPrice.fromJson(Map<String, Object?> json) => CoinPrice(
        usd: (json['usd'] as num).toDouble(),
        change24h: (json['change24h'] as num?)?.toDouble() ?? 0,
      );
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
