import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/utils/app_log.dart';
import '../data/networks/chain_api.dart';
import '../data/networks/chain_models.dart';
import '../data/networks/network_config.dart';
import '../data/networks/price_api.dart';
import '../data/wallet/snapshot_cache.dart';
import 'settings_controller.dart';
import 'wallet_identity_controller.dart';

/// Loads live balance, history and price data for the selected network.
///
/// Watches [WalletIdentityController] (for the address) and
/// [SettingsController] (for the active network) and re-queries whenever
/// either changes in a way that affects the result.
class WalletController extends ChangeNotifier {
  WalletController({
    required this.identity,
    required this.settings,
    ChainApi? chainApi,
    PriceApi? priceApi,
    SnapshotCache? cache,
  })  : _chainApi = chainApi ?? ChainApi(),
        _priceApi = priceApi ?? PriceApi(),
        _cache = cache ?? const SnapshotCache() {
    identity.addListener(_onDependencyChanged);
    settings.addListener(_onDependencyChanged);
    // Deferred so the very first notify happens after the first build.
    unawaited(Future<void>.microtask(_onDependencyChanged));
  }

  final WalletIdentityController identity;
  final SettingsController settings;
  final ChainApi _chainApi;
  final PriceApi _priceApi;
  final SnapshotCache _cache;

  AccountSnapshot? _snapshot;
  bool _loading = false;
  String? _error;
  bool _errorRetryable = true;
  String? _lastKey;
  int _requestToken = 0;
  bool _disposed = false;

  NetworkConfig get network => settings.network;

  AccountSnapshot? get snapshot => _snapshot;

  bool get loading => _loading;

  String? get error => _error;

  /// Whether the last [error] is worth retrying (network hiccups are, a
  /// malformed response is not).
  bool get errorRetryable => _errorRetryable;

  /// Receive address for the active network, or `null` while locked.
  String? get address => identity.addressFor(network);

  bool get hasData => _snapshot != null;

  /// Forces a re-fetch, e.g. from pull-to-refresh or the app bar button.
  ///
  /// Bypasses the price cache so the user actually sees a fresh value.
  Future<void> refresh() => _load(force: true);

  /// Network fee estimate for a simple transfer on the active network.
  ///
  /// Returns `null` when the estimate is unavailable.
  Future<BigInt?> estimateFee() => _chainApi.fetchFeeEstimate(network);

  @override
  void dispose() {
    _disposed = true;
    identity.removeListener(_onDependencyChanged);
    settings.removeListener(_onDependencyChanged);
    _chainApi.dispose();
    _priceApi.dispose();
    super.dispose();
  }

  /// [notifyListeners] that is safe to call from an async continuation that may
  /// outlive the widget tree.
  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Reloads only when the (network, address) pair actually changed.
  void _onDependencyChanged() {
    if (_disposed) {
      return;
    }
    final NetworkConfig network = settings.network;
    final String key = '${network.id}|${identity.addressFor(network) ?? ''}';
    if (key == _lastKey) {
      return;
    }
    _lastKey = key;
    unawaited(_load());
  }

  /// Fetches balance, history and price for the active network.
  ///
  /// A request token guards against out-of-order responses when the user
  /// switches networks quickly. When [force] is set the price cache is cleared
  /// first, so an explicit refresh always hits the network.
  Future<void> _load({bool force = false}) async {
    final NetworkConfig network = settings.network;
    final String? address = identity.addressFor(network);
    final int token = ++_requestToken;

    if (address == null) {
      _snapshot = null;
      _loading = false;
      _error = null;
      _errorRetryable = true;
      _safeNotify();
      return;
    }

    // Show the last persisted snapshot for this network straight away, so the
    // screen is useful before the network answers and while offline. A snapshot
    // from a different network or address is never shown.
    if (_snapshot?.network.id != network.id || _snapshot?.address != address) {
      final AccountSnapshot? cached = await _cache.read(network.id);
      if (token != _requestToken) {
        return;
      }
      _snapshot = cached != null &&
              cached.network.id == network.id &&
              cached.address == address
          ? cached
          : null;
      _safeNotify();
    }

    if (force) {
      _priceApi.invalidateCache();
    }

    _loading = true;
    _error = null;
    _errorRetryable = true;
    _safeNotify();

    try {
      // Run every request concurrently. `Future.wait` attaches listeners to all
      // of them immediately, so a failure in one never leaves the others as
      // unhandled async errors.
      final List<Object?> results =
          await Future.wait<Object?>(<Future<Object?>>[
        _chainApi.fetchBalance(network, address),
        _chainApi.fetchTransactions(network, address),
        _chainApi.fetchTokenBalances(network, address),
        network.priceId == null
            ? Future<Object?>.value()
            : _priceApi.fetchPrice(network.priceId!),
        network.priceId == null
            ? Future<Object?>.value(const <double>[])
            : _priceApi.fetchChart(network.priceId!),
      ]);

      if (token != _requestToken) {
        return;
      }

      final BigInt balance = results[0]! as BigInt;
      final List<ChainTransaction> transactions =
          results[1]! as List<ChainTransaction>;
      final List<TokenBalance> tokens = results[2]! as List<TokenBalance>;
      final CoinPrice? fetchedPrice = results[3] as CoinPrice?;
      final List<double> fetchedChart = results[4]! as List<double>;

      // CoinGecko's free tier rate-limits aggressively (HTTP 429), so a price
      // request can fail even though the balance loaded fine. When that happens
      // for a network we already had a price for, keep the previous value
      // instead of blanking it — otherwise every reload would make a mainnet
      // look like a testnet with "no market price".
      final AccountSnapshot? previous = _snapshot;
      final bool sameNetwork = previous?.network.id == network.id;
      final CoinPrice? price =
          fetchedPrice ?? (sameNetwork ? previous?.price : null);
      final List<double> chart = fetchedChart.isNotEmpty
          ? fetchedChart
          : (sameNetwork ? previous?.chart ?? const <double>[] : fetchedChart);

      _snapshot = AccountSnapshot(
        network: network,
        address: address,
        balance: balance,
        transactions: transactions,
        chart: chart,
        price: price,
        tokens: tokens,
        fetchedAt: DateTime.now(),
      );
      unawaited(_cache.write(_snapshot!));
    } on ChainApiException catch (error) {
      if (token != _requestToken) {
        return;
      }
      _error = error.message;
      _errorRetryable = error.retryable;
      AppLog.warning('Failed to load ${network.name}', error);
    } catch (error, stackTrace) {
      if (token != _requestToken) {
        return;
      }
      _error = 'Something went wrong while loading ${network.name}.';
      _errorRetryable = true;
      AppLog.error(
        'Unexpected failure loading ${network.name}',
        error,
        stackTrace,
      );
    } finally {
      if (token == _requestToken) {
        _loading = false;
        _safeNotify();
      }
    }
  }
}
