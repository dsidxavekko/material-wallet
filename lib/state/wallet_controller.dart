import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/utils/app_log.dart';
import '../data/models/chain_kind.dart';
import '../data/networks/activity_merge.dart';
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
    Duration? pendingPollInterval,
  })  : _chainApi = chainApi ?? ChainApi(),
        _priceApi = priceApi ?? PriceApi(),
        _cache = cache ?? const SnapshotCache(),
        _pendingPollOverride = pendingPollInterval {
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

  /// Test seam: replaces the per-chain pending-poll cadence.
  final Duration? _pendingPollOverride;

  AccountSnapshot? _snapshot;
  bool _loading = false;
  String? _error;
  bool _errorRetryable = true;
  String? _lastKey;
  int _requestToken = 0;
  bool _disposed = false;

  /// Re-reads the network while an outgoing transfer is waiting to confirm.
  ///
  /// Without it "Transfer confirmed" only arrives on the next manual refresh —
  /// the success screen gives up waiting long before an average Bitcoin block.
  /// Runs only while the visible snapshot holds a pending outgoing transfer,
  /// and stops on lock (no address → no snapshot), dispose and network change
  /// (the reload after a change re-evaluates the condition itself).
  Timer? _pendingPoll;

  /// Poll cadence per chain: EVM blocks are ~12 s, Bitcoin ~10 minutes.
  static const Duration _evmPollInterval = Duration(seconds: 20);
  static const Duration _bitcoinPollInterval = Duration(seconds: 60);

  /// History accumulated across pages for the active (network, address).
  ///
  /// Kept raw — native rows and token transfers apart — and merged again on
  /// every change, because a token transfer and its call can arrive on
  /// different pages.
  List<ChainTransaction> _nativeRows = const <ChainTransaction>[];
  List<TokenTransfer> _transferRows = const <TokenTransfer>[];
  ActivityCursor? _activityCursor;
  String? _activityKey;
  bool _olderLoaded = false;
  bool _loadingMore = false;
  String? _loadMoreError;

  /// Total USD value of the last cached snapshot of every network, when known.
  double? _portfolioFiat;

  NetworkConfig get network => settings.network;

  AccountSnapshot? get snapshot => _snapshot;

  bool get loading => _loading;

  /// Sum of the account's value across every network with cached data.
  ///
  /// `null` until at least one network has a known price; it is a best-effort
  /// figure built from the last snapshot of each chain, refreshed whenever the
  /// active network reloads.
  double? get portfolioFiat => _portfolioFiat;

  String? get error => _error;

  /// Whether older history can still be fetched for the active account.
  bool get canLoadMore => _activityCursor != null;

  bool get loadingMore => _loadingMore;

  /// Why the last "load more" failed, or `null`.
  String? get loadMoreError => _loadMoreError;

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

  /// What the explorer knows about [address] on the active network, for the
  /// pre-signature recipient check. `null` when the chain has no address
  /// index; throws [ChainApiException] when the lookup itself failed.
  Future<AddressInfo?> fetchAddressInfo(String address) =>
      _chainApi.fetchAddressInfo(network, address);

  /// Resolves an ENS name for the recipient field; see
  /// [ChainApi.resolveEnsName].
  Future<String?> resolveEns(String name) => _chainApi.resolveEnsName(name);

  @override
  void dispose() {
    _disposed = true;
    _pendingPoll?.cancel();
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

  /// Recomputes the cross-network total **for the active account**, using the
  /// freshest in-memory value for the active network.
  Future<void> _refreshPortfolio() async {
    double total = 0;
    bool any = false;
    for (final NetworkConfig n in NetworkCatalog.all) {
      final String? address = identity.addressFor(n);
      if (address == null) {
        continue;
      }
      final AccountSnapshot? cached =
          n.id == network.id ? _snapshot : await _cache.read(n.id, address);
      final double? fiat = cached?.fiatBalance;
      if (fiat != null) {
        total += fiat;
        any = true;
      }
      if (cached != null) {
        for (final TokenBalance token in cached.tokens) {
          final double? tokenUsd = token.usdValue;
          if (tokenUsd != null) {
            total += tokenUsd;
            any = true;
          }
        }
      }
    }
    if (_disposed) {
      return;
    }
    final double? next = any ? total : null;
    if (next != _portfolioFiat) {
      _portfolioFiat = next;
      _safeNotify();
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
      _syncPendingPoll();
      _safeNotify();
      return;
    }

    // Show the last persisted snapshot for this network straight away, so the
    // screen is useful before the network answers and while offline. A snapshot
    // from a different network or address is never shown.
    if (_snapshot?.network.id != network.id || _snapshot?.address != address) {
      final AccountSnapshot? cached = await _cache.read(network.id, address);
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
        _chainApi.fetchActivityPage(network, address),
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
      final ActivityPage page = results[1]! as ActivityPage;
      List<TokenBalance> tokens = results[2]! as List<TokenBalance>;
      if (network.chain == ChainKind.solana && tokens.isNotEmpty) {
        // The chain knows mints only; tickers and prices come from CoinGecko.
        tokens = await _priceApi.enrichSplTokens(tokens);
        if (token != _requestToken) {
          return;
        }
      }
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

      // Older pages already loaded stay put across a reload (a poll tick must
      // not throw away what the user scrolled to); the fresh first page
      // replaces its own rows, and anything still pending is re-read from it.
      final String activityKey = '${network.id}|$address';
      final bool keepOlder = _activityKey == activityKey && _olderLoaded;
      _nativeRows = keepOlder
          ? _dedupe<ChainTransaction>(
              <ChainTransaction>[
                ...page.native,
                ..._nativeRows.where((ChainTransaction t) => t.confirmed),
              ],
              (ChainTransaction t) => t.hash.toLowerCase(),
            )
          : page.native;
      _transferRows = keepOlder
          ? _dedupe<TokenTransfer>(
              <TokenTransfer>[...page.transfers, ..._transferRows],
              _transferKey,
            )
          : page.transfers;
      if (!keepOlder) {
        _activityCursor = page.next;
        _olderLoaded = false;
      }
      _activityKey = activityKey;
      _loadMoreError = null;

      _snapshot = AccountSnapshot(
        network: network,
        address: address,
        balance: balance,
        transactions: mergeTokenTransfers(
          native: _nativeRows,
          transfers: _transferRows,
          address: address,
        ),
        chart: chart,
        price: price,
        tokens: tokens,
        fetchedAt: DateTime.now(),
      );
      // Only the first page is persisted: the cache exists to paint the screen
      // before the network answers, not to archive history.
      unawaited(
        _cache.write(
          AccountSnapshot(
            network: network,
            address: address,
            balance: balance,
            transactions: mergeTokenTransfers(
              native: page.native,
              transfers: page.transfers,
              address: address,
            ),
            chart: chart,
            price: price,
            tokens: tokens,
            fetchedAt: _snapshot!.fetchedAt,
          ),
        ),
      );
      unawaited(_refreshPortfolio());
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
        _syncPendingPoll();
        _safeNotify();
      }
    }
  }

  /// Fetches the next, older page of history and appends it.
  ///
  /// A failure keeps the cursor, so the same button can simply be tapped again.
  Future<void> loadMoreActivity() async {
    final ActivityCursor? cursor = _activityCursor;
    final AccountSnapshot? current = _snapshot;
    if (cursor == null || current == null || _loadingMore) {
      return;
    }
    final String key = '${current.network.id}|${current.address}';
    _loadingMore = true;
    _loadMoreError = null;
    _safeNotify();
    try {
      final ActivityPage page = await _chainApi.fetchActivityPage(
        current.network,
        current.address,
        after: cursor,
      );
      if (_disposed || _activityKey != key) {
        return;
      }
      _nativeRows = _dedupe<ChainTransaction>(
        <ChainTransaction>[..._nativeRows, ...page.native],
        (ChainTransaction t) => t.hash.toLowerCase(),
      );
      _transferRows = _dedupe<TokenTransfer>(
        <TokenTransfer>[..._transferRows, ...page.transfers],
        _transferKey,
      );
      _activityCursor = page.next;
      _olderLoaded = true;
      final AccountSnapshot base = _snapshot ?? current;
      _snapshot = AccountSnapshot(
        network: base.network,
        address: base.address,
        balance: base.balance,
        transactions: mergeTokenTransfers(
          native: _nativeRows,
          transfers: _transferRows,
          address: base.address,
        ),
        chart: base.chart,
        price: base.price,
        tokens: base.tokens,
        fetchedAt: base.fetchedAt,
      );
    } on ChainApiException catch (error) {
      _loadMoreError = error.message;
    } catch (error, stackTrace) {
      AppLog.error('Could not load more activity', error, stackTrace);
      _loadMoreError = 'Could not load more activity.';
    } finally {
      _loadingMore = false;
      _safeNotify();
    }
  }

  /// First occurrence wins, order is kept.
  static List<T> _dedupe<T>(List<T> items, String Function(T) keyOf) {
    final Set<String> seen = <String>{};
    return <T>[
      for (final T item in items)
        if (seen.add(keyOf(item))) item,
    ];
  }

  static String _transferKey(TokenTransfer t) =>
      '${t.hash}|${t.contract}|${t.from}|${t.to}|${t.value}'.toLowerCase();

  /// Starts or stops [_pendingPoll] to match the current snapshot.
  ///
  /// A poll tick is a normal reload, so a confirmed transfer also refreshes the
  /// balance, the history and the notification (via [ConfirmationWatcher]) and
  /// the next sync sees no pending transfer and stops the timer by itself.
  void _syncPendingPoll() {
    final bool pending = _snapshot?.transactions.any(
          (ChainTransaction tx) => tx.isIncoming == false && tx.isPending,
        ) ??
        false;
    if (!pending) {
      _pendingPoll?.cancel();
      _pendingPoll = null;
      return;
    }
    if (_pendingPoll != null) {
      return;
    }
    final Duration interval = _pendingPollOverride ??
        (_snapshot!.network.chain == ChainKind.bitcoin
            ? _bitcoinPollInterval
            : _evmPollInterval);
    _pendingPoll = Timer.periodic(interval, (_) => unawaited(_load()));
  }
}
