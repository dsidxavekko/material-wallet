import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chain_kind.dart';
import 'chain_models.dart';
import 'network_config.dart';

/// Coarse categories for a [ChainApiException], so callers and logs can tell a
/// transient network problem from a response the app simply cannot use.
class ChainApiErrorCode {
  const ChainApiErrorCode._();

  static const String timeout = 'timeout';
  static const String network = 'network';
  static const String http = 'http';
  static const String parse = 'parse';
  static const String node = 'node';
  static const String unknown = 'unknown';
}

/// Raised when a blockchain API cannot be reached or returns an error.
class ChainApiException implements Exception {
  const ChainApiException(
    this.message, {
    this.code = ChainApiErrorCode.unknown,
    this.retryable = true,
  });

  final String message;

  /// One of the [ChainApiErrorCode] values.
  final String code;

  /// Whether trying again could plausibly succeed.
  final bool retryable;

  @override
  String toString() => message;
}

/// Reads live account data from free, key-less public APIs.
///
/// * **Bitcoin** — [mempool.space](https://mempool.space/docs/api/rest)
/// * **EVM** — public Blockscout instances (`/api/v2`)
///
/// Every endpoint sends `Access-Control-Allow-Origin: *`, so the exact same
/// code also works in the browser build.
class ChainApi {
  ChainApi({http.Client? client, this.timeout = const Duration(seconds: 25)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  void dispose() => _client.close();

  /// Native balance in the smallest unit.
  Future<BigInt> fetchBalance(NetworkConfig network, String address) async {
    if (network.chain == ChainKind.aptos) {
      // The REST API answers with a bare number of octas (or 404 when the
      // account has never been funded).
      final Object? octas = await _get(
        '${network.apiBase}/accounts/$address/balance/$_aptosCoinType',
      );
      return BigInt.from((octas as num?)?.toInt() ?? 0);
    }

    if (network.chain == ChainKind.solana) {
      final Object? result =
          await _rpc(network.apiBase, 'getBalance', <Object?>[address]);
      return _parseSolanaBalance(result);
    }

    if (network.rpcUrl != null) {
      final Object? result = await _rpc(
        network.rpcUrl!,
        'eth_getBalance',
        <Object?>[address, 'latest'],
      );
      return _hexToBigInt(result);
    }

    if (network.chain == ChainKind.bitcoin) {
      final Object? json = await _get('${network.apiBase}/address/$address');
      return _parseBitcoinBalance(json);
    }

    final Object? json = await _get('${network.apiBase}/addresses/$address');
    return _parseEvmBalance(json);
  }

  /// Most recent transactions for [address], newest first.
  Future<List<ChainTransaction>> fetchTransactions(
    NetworkConfig network,
    String address,
  ) async {
    if (network.chain == ChainKind.aptos) {
      final Object? json = await _get(
        '${network.apiBase}/accounts/$address/transactions'
        '?limit=$_aptosHistoryLimit',
      );
      return _parseAptosTransactions(json, address);
    }

    if (network.chain == ChainKind.solana) {
      return _fetchSolanaTransactions(network, address);
    }

    if (network.rpcUrl != null) {
      // JSON-RPC has no address-history index, so this chain shows a balance
      // but no activity list (adding one needs an API key).
      return const <ChainTransaction>[];
    }

    if (network.chain == ChainKind.bitcoin) {
      final Object? json =
          await _get('${network.apiBase}/address/$address/txs');
      return _parseBitcoinTransactions(json, address);
    }

    final Object? json =
        await _get('${network.apiBase}/addresses/$address/transactions');
    return _parseEvmTransactions(json, address);
  }

  /// Rough network fee for a simple transfer, in the smallest unit.
  ///
  /// Returns `null` when no estimate is available, so the UI can say "unknown"
  /// instead of showing a made-up number.
  Future<BigInt?> fetchFeeEstimate(NetworkConfig network) async {
    try {
      if (network.chain == ChainKind.solana) {
        // A plain SOL transfer costs a flat 5,000 lamports.
        return BigInt.from(5000);
      }

      if (network.chain == ChainKind.aptos) {
        final Object? json = await _get('${network.apiBase}/estimate_gas_price');
        final int unitPrice =
            ((json as Map<String, Object?>?)?['gas_estimate'] as num?)
                    ?.toInt() ??
                100;
        // A simple transfer uses on the order of 1,000 gas units; erring high
        // keeps the MAX button from overspending.
        return BigInt.from(unitPrice) * BigInt.from(1000);
      }

      if (network.rpcUrl != null) {
        final Object? result =
            await _rpc(network.rpcUrl!, 'eth_gasPrice', const <Object?>[]);
        // 21,000 gas is the cost of a plain value transfer.
        return _hexToBigInt(result) * BigInt.from(21000);
      }

      if (network.chain == ChainKind.bitcoin) {
        final Object? json =
            await _get('${network.apiBase}/v1/fees/recommended');
        final int? satPerVb =
            (json as Map<String, Object?>?)?['halfHourFee'] as int?;
        if (satPerVb == null) {
          return null;
        }
        // ~140 vB is a typical native SegWit (P2WPKH) transfer.
        return BigInt.from(satPerVb) * BigInt.from(140);
      }

      final Object? json = await _get('${network.apiBase}/stats');
      final String? gasPriceWei =
          (json as Map<String, Object?>?)?['gas_price'] as String?;
      if (gasPriceWei == null) {
        return null;
      }
      // 21,000 gas is the cost of a plain value transfer.
      return (BigInt.tryParse(gasPriceWei) ?? BigInt.zero) * BigInt.from(21000);
    } catch (_) {
      return null;
    }
  }

  // --- HTTP ----------------------------------------------------------------

  Future<Object?> _get(String url) async {
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse(url),
        headers: const <String, String>{'Accept': 'application/json'},
      ).timeout(timeout);
    } on TimeoutException {
      throw const ChainApiException(
        'The network request timed out.',
        code: ChainApiErrorCode.timeout,
      );
    } catch (_) {
      throw const ChainApiException(
        'Could not reach the blockchain API. Check your connection.',
        code: ChainApiErrorCode.network,
      );
    }

    if (response.statusCode == 404) {
      // An address with no history yet is not an error.
      return null;
    }
    if (response.statusCode >= 400) {
      throw ChainApiException(
        'The API rejected the request (HTTP ${response.statusCode}).',
        code: ChainApiErrorCode.http,
        retryable: response.statusCode >= 500 || response.statusCode == 429,
      );
    }

    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const ChainApiException(
        'Unexpected response from the API.',
        code: ChainApiErrorCode.parse,
        retryable: false,
      );
    }
  }

  /// Minimal JSON-RPC over HTTP, used by BNB Chain and Solana.
  Future<Object?> _rpc(
    String url,
    String method,
    List<Object?> params,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(url),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 1,
              'method': method,
              'params': params,
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ChainApiException(
        'The network request timed out.',
        code: ChainApiErrorCode.timeout,
      );
    } catch (_) {
      throw const ChainApiException(
        'Could not reach the blockchain API. Check your connection.',
        code: ChainApiErrorCode.network,
      );
    }

    if (response.statusCode >= 400) {
      throw ChainApiException(
        'The API rejected the request (HTTP ${response.statusCode}).',
        code: ChainApiErrorCode.http,
        retryable: response.statusCode >= 500 || response.statusCode == 429,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const ChainApiException(
        'Unexpected response from the API.',
        code: ChainApiErrorCode.parse,
        retryable: false,
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw const ChainApiException(
        'Unexpected response from the API.',
        code: ChainApiErrorCode.parse,
        retryable: false,
      );
    }

    final Object? error = decoded['error'];
    if (error is Map<String, Object?>) {
      throw ChainApiException(
        error['message'] as String? ?? 'The node rejected the request.',
        code: ChainApiErrorCode.node,
        retryable: false,
      );
    }

    return decoded['result'];
  }

  // --- Bitcoin parsing -----------------------------------------------------

  BigInt _parseBitcoinBalance(Object? json) {
    if (json is! Map<String, Object?>) {
      return BigInt.zero;
    }

    int stat(String bucket, String field) {
      final Map<String, Object?> stats =
          (json[bucket] as Map<String, Object?>?) ?? const <String, Object?>{};
      return (stats[field] as num?)?.toInt() ?? 0;
    }

    final int confirmed = stat('chain_stats', 'funded_txo_sum') -
        stat('chain_stats', 'spent_txo_sum');
    final int pending = stat('mempool_stats', 'funded_txo_sum') -
        stat('mempool_stats', 'spent_txo_sum');
    return BigInt.from(confirmed + pending);
  }

  List<ChainTransaction> _parseBitcoinTransactions(
    Object? json,
    String address,
  ) {
    if (json is! List) {
      return const <ChainTransaction>[];
    }

    final String needle = address.toLowerCase();
    final List<ChainTransaction> result = <ChainTransaction>[];

    for (final Object? raw in json) {
      if (raw is! Map<String, Object?>) {
        continue;
      }
      final Map<String, Object?> status =
          (raw['status'] as Map<String, Object?>?) ?? const <String, Object?>{};
      final bool confirmed = status['confirmed'] == true;
      final int blockTime = (status['block_time'] as num?)?.toInt() ?? 0;

      final List<Object?> vins =
          (raw['vin'] as List<Object?>?) ?? const <Object?>[];
      final List<Object?> vouts =
          (raw['vout'] as List<Object?>?) ?? const <Object?>[];

      int received = 0;
      int sent = 0;
      for (final Object? out in vouts) {
        final Map<String, Object?>? output = out as Map<String, Object?>?;
        if ((output?['scriptpubkey_address'] as String?)?.toLowerCase() ==
            needle) {
          received += (output?['value'] as num?)?.toInt() ?? 0;
        }
      }
      for (final Object? input in vins) {
        final Map<String, Object?> prev =
            ((input as Map<String, Object?>?)?['prevout']
                    as Map<String, Object?>?) ??
                const <String, Object?>{};
        if ((prev['scriptpubkey_address'] as String?)?.toLowerCase() == needle) {
          sent += (prev['value'] as num?)?.toInt() ?? 0;
        }
      }

      final int net = received - sent;
      final bool incoming = net >= 0;

      result.add(
        ChainTransaction(
          hash: raw['txid'] as String? ?? '',
          timestamp: blockTime == 0
              ? DateTime.now()
              : DateTime.fromMillisecondsSinceEpoch(blockTime * 1000),
          amount: BigInt.from(net),
          fee: BigInt.from((raw['fee'] as num?)?.toInt() ?? 0),
          counterparty: _bitcoinCounterparty(vins, vouts, needle, incoming),
          isIncoming: incoming,
          confirmed: confirmed,
        ),
      );
    }

    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }

  String _bitcoinCounterparty(
    List<Object?> vins,
    List<Object?> vouts,
    String needle,
    bool incoming,
  ) {
    if (incoming) {
      for (final Object? input in vins) {
        final Map<String, Object?> prev =
            ((input as Map<String, Object?>?)?['prevout']
                    as Map<String, Object?>?) ??
                const <String, Object?>{};
        final String? from = prev['scriptpubkey_address'] as String?;
        if (from != null && from.toLowerCase() != needle) {
          return from;
        }
      }
      return 'Coinbase';
    }

    for (final Object? out in vouts) {
      final String? to =
          (out as Map<String, Object?>?)?['scriptpubkey_address'] as String?;
      if (to != null && to.toLowerCase() != needle) {
        return to;
      }
    }
    return 'Unknown';
  }

  // --- EVM parsing ---------------------------------------------------------

  BigInt _parseEvmBalance(Object? json) {
    if (json is! Map<String, Object?>) {
      return BigInt.zero;
    }
    final String? wei = json['coin_balance'] as String?;
    return wei == null ? BigInt.zero : (BigInt.tryParse(wei) ?? BigInt.zero);
  }

  List<ChainTransaction> _parseEvmTransactions(Object? json, String address) {
    if (json is! Map<String, Object?>) {
      return const <ChainTransaction>[];
    }
    final List<Object?> items =
        (json['items'] as List<Object?>?) ?? const <Object?>[];
    final String needle = address.toLowerCase();
    final List<ChainTransaction> result = <ChainTransaction>[];

    for (final Object? raw in items) {
      if (raw is! Map<String, Object?>) {
        continue;
      }
      final String? from =
          (raw['from'] as Map<String, Object?>?)?['hash'] as String?;
      final String? to =
          (raw['to'] as Map<String, Object?>?)?['hash'] as String?;
      final bool incoming = to?.toLowerCase() == needle;

      final BigInt value =
          BigInt.tryParse(raw['value'] as String? ?? '0') ?? BigInt.zero;
      final BigInt fee = BigInt.tryParse(
            (raw['fee'] as Map<String, Object?>?)?['value'] as String? ?? '0',
          ) ??
          BigInt.zero;

      // The sender pays the fee, so outgoing transfers cost value + fee while
      // incoming ones only add value.
      final BigInt signed = incoming ? value + fee : -(value + fee);

      result.add(
        ChainTransaction(
          hash: raw['hash'] as String? ?? '',
          timestamp:
              DateTime.tryParse(raw['timestamp'] as String? ?? '')?.toLocal() ??
                  DateTime.now(),
          amount: signed,
          fee: fee,
          counterparty: (incoming ? from : to) ?? 'Contract creation',
          isIncoming: incoming,
          confirmed: raw['block'] != null,
          failed: raw['status'] == 'error',
        ),
      );
    }

    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }

  // --- Solana parsing ------------------------------------------------------

  /// How many recent signatures are turned into transactions. Each one costs an
  /// extra `getTransaction` round trip, so the list is deliberately short to
  /// stay inside the public RPC rate limits.
  static const int _solanaHistoryLimit = 6;

  /// Well-known Solana programs that never make sense as a counterparty.
  static const Set<String> _solanaPrograms = <String>{
    '11111111111111111111111111111111',
    'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
    'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL',
    'ComputeBudget111111111111111111111111111111',
  };

  Future<List<ChainTransaction>> _fetchSolanaTransactions(
    NetworkConfig network,
    String address,
  ) async {
    final Object? signatures = await _rpc(
      network.apiBase,
      'getSignaturesForAddress',
      <Object?>[
        address,
        <String, Object?>{'limit': _solanaHistoryLimit},
      ],
    );
    if (signatures is! List) {
      return const <ChainTransaction>[];
    }

    final List<ChainTransaction> result = <ChainTransaction>[];
    for (final Object? entry in signatures.take(_solanaHistoryLimit)) {
      if (entry is! Map<String, Object?>) {
        continue;
      }
      final String? signature = entry['signature'] as String?;
      if (signature == null) {
        continue;
      }
      try {
        final Object? tx = await _rpc(
          network.apiBase,
          'getTransaction',
          <Object?>[
            signature,
            <String, Object?>{
              'encoding': 'jsonParsed',
              'maxSupportedTransactionVersion': 0,
            },
          ],
        );
        final ChainTransaction? parsed = _parseSolanaTransaction(
          tx is Map<String, Object?> ? tx : null,
          address,
          signature,
          entry,
        );
        if (parsed != null) {
          result.add(parsed);
        }
      } catch (_) {
        // Skip anything the node refuses to serve.
      }
    }

    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }

  BigInt _parseSolanaBalance(Object? result) {
    if (result is! Map<String, Object?>) {
      return BigInt.zero;
    }
    return BigInt.from((result['value'] as num?)?.toInt() ?? 0);
  }

  /// Converts a `0x…` hex quantity from an EVM JSON-RPC node into a [BigInt].
  BigInt _hexToBigInt(Object? value) {
    if (value is! String || value.isEmpty) {
      return BigInt.zero;
    }
    final String hex = value.startsWith('0x') ? value.substring(2) : value;
    if (hex.isEmpty) {
      return BigInt.zero;
    }
    return BigInt.tryParse(hex, radix: 16) ?? BigInt.zero;
  }

  ChainTransaction? _parseSolanaTransaction(
    Map<String, Object?>? tx,
    String address,
    String signature,
    Map<String, Object?> signatureInfo,
  ) {
    if (tx == null) {
      return null;
    }
    final Map<String, Object?> meta =
        (tx['meta'] as Map<String, Object?>?) ?? const <String, Object?>{};
    final Map<String, Object?> message = (((tx['transaction']
                as Map<String, Object?>?)?['message'])
        as Map<String, Object?>?)??
        const <String, Object?>{}; 

    final List<String> keys = <String>[];
    for (final Object? key
        in (message['accountKeys'] as List<Object?>?) ?? const <Object?>[]) {
      if (key is String) {
        keys.add(key);
      } else if (key is Map<String, Object?>) {
        final String? pubkey = key['pubkey'] as String?;
        if (pubkey != null) {
          keys.add(pubkey);
        }
      }
    }

    final int index = keys.indexOf(address);
    if (index < 0) {
      return null;
    }

    final List<Object?> pre =
        (meta['preBalances'] as List<Object?>?) ?? const <Object?>[];
    final List<Object?> post =
        (meta['postBalances'] as List<Object?>?) ?? const <Object?>[];
    if (index >= pre.length || index >= post.length) {
      return null;
    }

    // The balance delta is already net of the fee when this wallet paid it.
    final int delta = ((post[index] as num?)?.toInt() ?? 0) -
        ((pre[index] as num?)?.toInt() ?? 0);
    final bool incoming = delta > 0;
    final int fee = (meta['fee'] as num?)?.toInt() ?? 0;
    final int blockTime = (tx['blockTime'] as num?)?.toInt() ??
        (signatureInfo['blockTime'] as num?)?.toInt() ??
        0;

    return ChainTransaction(
      hash: signature,
      timestamp: blockTime == 0
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(blockTime * 1000),
      amount: BigInt.from(delta),
      fee: BigInt.from(index == 0 ? fee : 0),
      counterparty: _solanaCounterparty(keys, address),
      isIncoming: incoming,
      confirmed: true,
      failed: meta['err'] != null,
    );
  }

  String _solanaCounterparty(List<String> keys, String address) {
    for (final String key in keys) {
      if (key != address && !_solanaPrograms.contains(key)) {
        return key;
      }
    }
    return 'Unknown';
  }

  // --- Aptos parsing -------------------------------------------------------

  /// APT is the chain's native coin, identified by this fully-qualified type.
  static const String _aptosCoinType = '0x1::aptos_coin::AptosCoin';

  static const int _aptosHistoryLimit = 15;

  /// Aptos abbreviates addresses (`0x1`), so compare the canonical form.
  String _canonicalAptos(String address) {
    final String lower = address.toLowerCase();
    final String hex = lower.startsWith('0x') ? lower.substring(2) : lower;
    final String trimmed = hex.replaceFirst(RegExp(r'^0+'), '');
    return trimmed.isEmpty ? '0' : trimmed;
  }

  List<ChainTransaction> _parseAptosTransactions(
    Object? json,
    String address,
  ) {
    if (json is! List) {
      return const <ChainTransaction>[];
    }

    final String needle = _canonicalAptos(address);
    final List<ChainTransaction> result = <ChainTransaction>[];

    for (final Object? raw in json) {
      // Skip block metadata / state checkpoint entries.
      if (raw is! Map<String, Object?> || raw['type'] != 'user_transaction') {
        continue;
      }

      final Map<String, Object?> payload =
          (raw['payload'] as Map<String, Object?>?) ??
              const <String, Object?>{};
      final List<Object?> arguments =
          (payload['arguments'] as List<Object?>?) ?? const <Object?>[];
      final String function = payload['function'] as String? ?? '';

      final bool isTransfer = function == '0x1::aptos_account::transfer' ||
          function == '0x1::aptos_account::transfer_coins' ||
          function == '0x1::coin::transfer';

      final bool outgoing = _canonicalAptos(raw['sender'] as String? ?? '') ==
          needle;
      final bool incoming = isTransfer &&
          arguments.isNotEmpty &&
          _canonicalAptos('${arguments.first}') == needle;
      if (!outgoing && !incoming) {
        continue;
      }

      // Only plain transfers carry a meaningful amount; other calls still show
      // up with a zero amount.
      final BigInt amount = isTransfer && arguments.length > 1
          ? BigInt.tryParse('${arguments[1]}') ?? BigInt.zero
          : BigInt.zero;

      final int gasUsed = int.tryParse('${raw['gas_used'] ?? '0'}') ?? 0;
      final int gasUnitPrice =
          int.tryParse('${raw['gas_unit_price'] ?? '0'}') ?? 0;
      final BigInt fee = BigInt.from(gasUsed * gasUnitPrice);
      final int timestampMicros =
          int.tryParse('${raw['timestamp'] ?? '0'}') ?? 0;

      result.add(
        ChainTransaction(
          hash: raw['hash'] as String? ?? '',
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(timestampMicros ~/ 1000),
          // The sender pays the fee, so outgoing transfers cost amount + fee.
          amount: incoming ? amount : -(amount + fee),
          fee: outgoing ? fee : BigInt.zero,
          counterparty: incoming
              ? raw['sender'] as String? ?? 'Unknown'
              : isTransfer && arguments.isNotEmpty
                  ? '${arguments.first}'
                  : _aptosFunctionName(function),
          isIncoming: incoming,
          confirmed: true,
          failed: raw['success'] != true,
        ),
      );
    }

    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }

  /// `0x1::aptos_account::transfer` → `transfer`.
  String _aptosFunctionName(String function) {
    final int index = function.lastIndexOf('::');
    return index == -1 ? function : function.substring(index + 2);
  }
}
