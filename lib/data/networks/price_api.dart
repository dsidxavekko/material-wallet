import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/utils/app_log.dart';
import 'chain_models.dart';

/// Fetches market prices from the public CoinGecko API.
///
/// The free tier needs no API key and sends CORS headers, so it works from the
/// web build too. Failures are swallowed — a missing price must never break the
/// wallet screen.
///
/// Because the free tier rate-limits aggressively (HTTP 429), successful
/// responses are cached for [cacheTtl] so that re-renders and quick network
/// switches do not spam the API. Use [invalidateCache] to force a fresh fetch,
/// e.g. from an explicit refresh.
class PriceApi {
  PriceApi({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.cacheTtl = const Duration(seconds: 60),
    DateTime Function()? now,
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  final http.Client _client;
  final Duration timeout;

  /// How long a successful price/chart response stays fresh.
  final Duration cacheTtl;

  /// Injectable clock so the cache TTL can be tested without real time.
  final DateTime Function() _now;

  static const String _base = 'https://api.coingecko.com/api/v3';

  final Map<String, _CacheEntry<CoinPrice>> _priceCache =
      <String, _CacheEntry<CoinPrice>>{};
  final Map<String, _CacheEntry<List<double>>> _chartCache =
      <String, _CacheEntry<List<double>>>{};

  void dispose() => _client.close();

  /// Drops every cached response so the next call hits the network.
  void invalidateCache() {
    _priceCache.clear();
    _chartCache.clear();
  }

  /// Spot price plus 24h change for [coinGeckoId], or `null` on failure.
  ///
  /// A cached value younger than [cacheTtl] is returned without a request.
  Future<CoinPrice?> fetchPrice(String coinGeckoId) async {
    final _CacheEntry<CoinPrice>? cached = _priceCache[coinGeckoId];
    if (cached != null && _isFresh(cached.fetchedAt)) {
      return cached.value;
    }
    try {
      final String url = '$_base/simple/price?ids=$coinGeckoId'
          '&vs_currencies=usd&include_24hr_change=true';
      final Map<String, Object?>? json = await _getJson(url);
      final Map<String, Object?>? coin =
          json?[coinGeckoId] as Map<String, Object?>?;
      if (coin == null) {
        return null;
      }
      final num? usd = coin['usd'] as num?;
      if (usd == null) {
        return null;
      }
      final CoinPrice price = CoinPrice(
        usd: usd.toDouble(),
        change24h: (coin['usd_24h_change'] as num?)?.toDouble() ?? 0,
      );
      _priceCache[coinGeckoId] =
          _CacheEntry<CoinPrice>(price, _now());
      return price;
    } catch (error) {
      // Expected under CoinGecko rate limits (HTTP 429); the caller falls back
      // to a previously cached price.
      AppLog.warning('Price fetch failed for $coinGeckoId', error);
      return null;
    }
  }

  /// Normalised 24h price series used for the chart, or an empty list.
  ///
  /// A cached value younger than [cacheTtl] is returned without a request.
  Future<List<double>> fetchChart(String coinGeckoId) async {
    final _CacheEntry<List<double>>? cached = _chartCache[coinGeckoId];
    if (cached != null && _isFresh(cached.fetchedAt)) {
      return cached.value;
    }
    try {
      final String url =
          '$_base/coins/$coinGeckoId/market_chart?vs_currency=usd&days=1';
      final Map<String, Object?>? json = await _getJson(url);
      final List<Object?> points =
          (json?['prices'] as List<Object?>?) ?? const <Object?>[];
      final List<double> raw = <double>[
        for (final Object? point in points)
          if (point is List && point.length > 1)
            (point[1] as num?)?.toDouble() ?? 0,
      ];
      // Normalise so the sparkline renders correctly on any scale.
      if (raw.isEmpty) {
        return const <double>[];
      }
      final double min = raw.reduce((a, b) => a < b ? a : b);
      final List<double> chart =
          raw.map((value) => value - min + 1).toList(growable: false);
      _chartCache[coinGeckoId] = _CacheEntry<List<double>>(chart, _now());
      return chart;
    } catch (error) {
      AppLog.warning('Chart fetch failed for $coinGeckoId', error);
      return const <double>[];
    }
  }

  /// Whether an entry fetched at [fetchedAt] is still within [cacheTtl].
  bool _isFresh(DateTime fetchedAt) =>
      _now().difference(fetchedAt) < cacheTtl;

  Future<Map<String, Object?>?> _getJson(String url) async {
    final http.Response response = await _client
        .get(
          Uri.parse(url),
          headers: const <String, String>{'Accept': 'application/json'},
        )
        .timeout(timeout);
    if (response.statusCode >= 400) {
      return null;
    }
    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, Object?> ? decoded : null;
  }
}

/// A cached API response together with the time it was fetched.
class _CacheEntry<T> {
  const _CacheEntry(this.value, this.fetchedAt);

  final T value;
  final DateTime fetchedAt;
}

