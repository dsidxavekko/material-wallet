import 'dart:convert';

import 'package:crypto_wallet/data/networks/price_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  http.Response json(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );

  /// PriceApi whose clock can be advanced manually so TTL is deterministic.
  ({PriceApi api, List<int> calls, void Function(Duration) advance}) build({
    Duration ttl = const Duration(seconds: 60),
  }) {
    DateTime now = DateTime(2026, 1, 1);
    final List<int> calls = <int>[];
    final MockClient client = MockClient((request) async {
      calls.add(1);
      if (request.url.toString().contains('simple/price')) {
        return json(<String, Object>{
          'bitcoin': <String, Object>{'usd': 60000.0, 'usd_24h_change': 1.5},
        });
      }
      return json(<String, Object>{
        'prices': <Object>[
          <Object>[1, 100.0],
          <Object>[2, 110.0],
        ],
      });
    });
    final PriceApi api = PriceApi(
      client: client,
      cacheTtl: ttl,
      now: () => now,
    );
    return (
      api: api,
      calls: calls,
      advance: (Duration d) => now = now.add(d),
    );
  }

  test('serves a cached price without a second request', () async {
    final b = build();
    final p1 = await b.api.fetchPrice('bitcoin');
    final p2 = await b.api.fetchPrice('bitcoin');

    expect(p1?.usd, 60000);
    expect(p2?.usd, 60000);
    expect(b.calls.length, 1);
    b.api.dispose();
  });

  test('re-fetches once the cache TTL expires', () async {
    final b = build(ttl: const Duration(seconds: 30));
    await b.api.fetchPrice('bitcoin');
    b.advance(const Duration(seconds: 31));
    await b.api.fetchPrice('bitcoin');

    expect(b.calls.length, 2);
    b.api.dispose();
  });

  test('invalidateCache forces the next fetch to hit the network', () async {
    final b = build();
    await b.api.fetchPrice('bitcoin');
    b.api.invalidateCache();
    await b.api.fetchPrice('bitcoin');

    expect(b.calls.length, 2);
    b.api.dispose();
  });

  test('a failed fetch does not overwrite a fresh cached price', () async {
    DateTime now = DateTime(2026, 1, 1);
    int calls = 0;
    int status = 200;
    final MockClient client = MockClient((request) async {
      calls++;
      if (request.url.toString().contains('simple/price')) {
        if (status >= 400) {
          return http.Response('rate limited', status);
        }
        return json(<String, Object>{
          'bitcoin': <String, Object>{'usd': 60000.0, 'usd_24h_change': 1.5},
        });
      }
      return json(<String, Object>{'prices': <Object>[]});
    });
    final PriceApi api = PriceApi(
      client: client,
      cacheTtl: const Duration(seconds: 60),
      now: () => now,
    );

    // Prime the cache from a good response.
    expect((await api.fetchPrice('bitcoin'))?.usd, 60000);
    expect(calls, 1);

    // The endpoint starts failing, and the cache entry expires. The failed
    // fetch returns null but must not cache that null...
    status = 429;
    now = now.add(const Duration(seconds: 61));
    expect(await api.fetchPrice('bitcoin'), isNull);
    expect(calls, 2);

    // ...so a later call retries the network rather than serving a cached null.
    status = 200;
    expect((await api.fetchPrice('bitcoin'))?.usd, 60000);
    expect(calls, 3);

    api.dispose();
  });

  test('chart responses are cached too', () async {
    final b = build();
    final c1 = await b.api.fetchChart('bitcoin');
    final c2 = await b.api.fetchChart('bitcoin');

    expect(c1, isNotEmpty);
    expect(c2, c1);
    expect(b.calls.length, 1);
    b.api.dispose();
  });
}
