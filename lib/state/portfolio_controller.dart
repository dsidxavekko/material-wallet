import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/utils/app_log.dart';
import '../core/utils/units.dart';
import '../data/networks/chain_api.dart';
import '../data/networks/chain_models.dart';
import '../data/networks/network_config.dart';
import '../data/networks/price_api.dart';

/// What the account holds on one network.
class PortfolioEntry {
  const PortfolioEntry({
    required this.network,
    required this.address,
    this.balance,
    this.tokens = const <TokenBalance>[],
    this.price,
    this.error,
  });

  final NetworkConfig network;
  final String address;

  /// Native balance, or `null` when it could not be read.
  final BigInt? balance;
  final List<TokenBalance> tokens;
  final CoinPrice? price;

  /// Why [balance] is missing, when it is.
  final String? error;

  bool get failed => balance == null;

  double? get nativeUsd => balance == null || price == null
      ? null
      : Units.toDouble(balance!, network.decimals) * price!.usd;

  double get tokensUsd => tokens.fold<double>(
        0,
        (double sum, TokenBalance t) => sum + (t.usdValue ?? 0),
      );

  /// Value in USD of everything priced on this network, or `null` when nothing
  /// here has a price (a testnet, or a coin CoinGecko did not answer for).
  double? get totalUsd {
    final double? native = nativeUsd;
    final bool anyToken = tokens.any((TokenBalance t) => t.usdValue != null);
    if (native == null && !anyToken) {
      return null;
    }
    return (native ?? 0) + tokensUsd;
  }

  bool get isEmpty =>
      (balance ?? BigInt.zero) == BigInt.zero && tokens.isEmpty;
}

/// Loads the account's holdings on **every** mainnet at once: one price
/// request for all coins, balances and tokens in parallel.
///
/// Replaces visiting each network in turn to add up the total. A network that
/// fails shows as unavailable — it is never silently counted as empty.
class PortfolioController extends ChangeNotifier {
  PortfolioController({
    required this.addressFor,
    ChainApi? chainApi,
    PriceApi? priceApi,
    Iterable<NetworkConfig>? networks,
  })  : _chainApi = chainApi ?? ChainApi(),
        _priceApi = priceApi ?? PriceApi(),
        networks = List<NetworkConfig>.unmodifiable(
          networks ?? NetworkCatalog.mainnets,
        );

  /// The active account's address on a network, or `null` while locked.
  final String? Function(NetworkConfig network) addressFor;

  final List<NetworkConfig> networks;
  final ChainApi _chainApi;
  final PriceApi _priceApi;

  List<PortfolioEntry> _entries = const <PortfolioEntry>[];
  bool _loading = false;
  bool _disposed = false;
  int _generation = 0;

  /// Entries sorted by value, largest first; unpriced and unreadable last.
  List<PortfolioEntry> get entries => _entries;

  bool get loading => _loading;

  /// Sum of everything priced, in USD; `null` until something is priced.
  double? get totalUsd {
    double total = 0;
    bool any = false;
    for (final PortfolioEntry e in _entries) {
      final double? value = e.totalUsd;
      if (value != null) {
        total += value;
        any = true;
      }
    }
    return any ? total : null;
  }

  /// Whether some network could not be read, so the total is a lower bound.
  bool get incomplete => _entries.any((PortfolioEntry e) => e.failed);

  Future<void> load({bool force = false}) async {
    final int generation = ++_generation;
    _loading = true;
    _safeNotify();

    if (force) {
      _priceApi.invalidateCache();
    }

    final List<NetworkConfig> active = <NetworkConfig>[
      for (final NetworkConfig n in networks)
        if (addressFor(n) != null) n,
    ];

    final Future<Map<String, CoinPrice>> prices = _priceApi.fetchPrices(
      <String>{
        for (final NetworkConfig n in active)
          if (n.priceId != null) n.priceId!,
      },
    );

    final List<PortfolioEntry> loaded = await Future.wait(
      <Future<PortfolioEntry>>[
        for (final NetworkConfig n in active) _loadOne(n, addressFor(n)!),
      ],
    );
    final Map<String, CoinPrice> priceById = await prices;

    if (_disposed || generation != _generation) {
      return;
    }

    final List<PortfolioEntry> priced = <PortfolioEntry>[
      for (final PortfolioEntry e in loaded)
        PortfolioEntry(
          network: e.network,
          address: e.address,
          balance: e.balance,
          tokens: e.tokens,
          error: e.error,
          price: e.network.priceId == null ? null : priceById[e.network.priceId],
        ),
    ];

    // Largest value first; among the unpriced, readable ones before failures.
    priced.sort((PortfolioEntry a, PortfolioEntry b) {
      final double? av = a.totalUsd;
      final double? bv = b.totalUsd;
      if (av != null && bv != null) {
        return bv.compareTo(av);
      }
      if (av != null) {
        return -1;
      }
      if (bv != null) {
        return 1;
      }
      if (a.failed != b.failed) {
        return a.failed ? 1 : -1;
      }
      return 0;
    });

    _entries = priced;
    _loading = false;
    _safeNotify();
  }

  Future<PortfolioEntry> _loadOne(NetworkConfig network, String address) async {
    try {
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        _chainApi.fetchBalance(network, address),
        _chainApi.fetchTokenBalances(network, address),
      ]);
      return PortfolioEntry(
        network: network,
        address: address,
        balance: results[0] as BigInt,
        tokens: results[1] as List<TokenBalance>,
      );
    } on ChainApiException catch (error) {
      AppLog.warning('Portfolio: ${network.name} unavailable', error);
      return PortfolioEntry(
        network: network,
        address: address,
        error: error.message,
      );
    } catch (error, stackTrace) {
      AppLog.warning('Portfolio: ${network.name} failed', error, stackTrace);
      return PortfolioEntry(
        network: network,
        address: address,
        error: 'Could not load ${network.name}.',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _chainApi.dispose();
    _priceApi.dispose();
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}
