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
}

/// Spot price of the network's native coin plus its 24h change.
class CoinPrice {
  const CoinPrice({required this.usd, required this.change24h});

  final double usd;

  /// Percentage change over the last 24 hours.
  final double change24h;
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
  });

  final NetworkConfig network;
  final String address;

  /// Native balance in the smallest unit.
  final BigInt balance;

  final List<ChainTransaction> transactions;

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

  int get pendingCount => transactions.where((t) => t.isPending).length;
}
