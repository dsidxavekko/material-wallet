import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:http/http.dart' as http;

import '../../core/crypto/ens.dart';
import '../../core/crypto/hashing.dart';
import '../../core/utils/app_log.dart';
import '../models/chain_kind.dart';
import '../wallet/bitcoin_signer.dart';
import '../wallet/evm_signer.dart';
import 'activity_merge.dart';
import 'chain_models.dart';
import 'network_config.dart';

/// Raised when a blockchain API cannot be reached or returns an error.
class ChainApiException implements Exception {
  const ChainApiException(this.message, {this.retryable = true});

  final String message;

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

  /// Most recent transactions for [address], newest first, with ERC-20
  /// transfers already folded in (see [mergeTokenTransfers]).
  Future<List<ChainTransaction>> fetchTransactions(
    NetworkConfig network,
    String address,
  ) async {
    final ActivityPage page = await fetchActivityPage(network, address);
    return mergeTokenTransfers(
      native: page.native,
      transfers: page.transfers,
      address: address,
    );
  }

  /// One page of history: the first when [after] is `null`, otherwise the page
  /// that follows the cursor of an earlier one.
  ///
  /// Returned unmerged so the caller can keep accumulating pages and merge the
  /// whole set again — a token transfer and its call can land on different
  /// pages.
  Future<ActivityPage> fetchActivityPage(
    NetworkConfig network,
    String address, {
    ActivityCursor? after,
  }) async {
    if (network.chain == ChainKind.aptos) {
      return _fetchAptosPage(network, address, after);
    }

    if (network.chain == ChainKind.solana) {
      return _fetchSolanaPage(network, address, after);
    }

    if (network.rpcUrl != null) {
      // JSON-RPC has no address-history index, so this chain shows a balance
      // but no activity list (adding one needs an API key).
      return const ActivityPage();
    }

    if (network.chain == ChainKind.bitcoin) {
      final String? last = after?.native?['last_seen'];
      if (after != null && last == null) {
        return const ActivityPage();
      }
      final Object? json = await _get(
        last == null
            ? '${network.apiBase}/address/$address/txs'
            : '${network.apiBase}/address/$address/txs/chain/$last',
      );
      final List<ChainTransaction> items =
          _parseBitcoinTransactions(json, address);
      // mempool.space serves confirmed history 25 at a time: a full page means
      // there may be more, anchored on the oldest confirmed txid seen.
      final List<ChainTransaction> confirmed =
          items.where((ChainTransaction t) => t.confirmed).toList();
      return ActivityPage(
        native: items,
        next: confirmed.length >= _bitcoinPageSize
            ? ActivityCursor(
                native: <String, String>{'last_seen': confirmed.last.hash},
              )
            : null,
      );
    }

    // Blockscout: the native list and the token-transfer feed page on their
    // own cursors; a side that is exhausted is simply not asked again.
    final bool wantNative = after == null || after.native != null;
    final bool wantTransfers = after == null || after.transfers != null;

    final Future<Map<String, Object?>?> nativeJson = wantNative
        ? _blockscoutPage(
            '${network.apiBase}/addresses/$address/transactions',
            after?.native,
          )
        : Future<Map<String, Object?>?>.value();
    final Future<Map<String, Object?>?> transferJson = wantTransfers
        ? _blockscoutPage(
            '${network.apiBase}/addresses/$address/token-transfers',
            after?.transfers,
            base: const <String, String>{'type': 'ERC-20'},
          ).then<Map<String, Object?>?>(
            (Map<String, Object?>? json) => json,
            onError: (Object error) {
              // Token rows are an enrichment; the native list must survive
              // the feed being down.
              AppLog.warning(
                'Token transfers unavailable for ${network.name}',
                error,
              );
              return null;
            },
          )
        : Future<Map<String, Object?>?>.value();

    final Map<String, Object?>? nativeBody = await nativeJson;
    final Map<String, Object?>? transferBody = await transferJson;

    final Map<String, String>? nextNative = _nextPageParams(nativeBody);
    final Map<String, String>? nextTransfers = _nextPageParams(transferBody);
    return ActivityPage(
      native: _parseEvmTransactions(nativeBody, address),
      transfers: _parseTokenTransfers(transferBody),
      next: nextNative == null && nextTransfers == null
          ? null
          : ActivityCursor(native: nextNative, transfers: nextTransfers),
    );
  }

  Future<Map<String, Object?>?> _blockscoutPage(
    String url,
    Map<String, String>? cursor, {
    Map<String, String> base = const <String, String>{},
  }) async {
    final Map<String, String> query = <String, String>{...base, ...?cursor};
    final String full = query.isEmpty
        ? url
        : Uri.parse(url).replace(queryParameters: query).toString();
    final Object? json = await _get(full);
    return json is Map<String, Object?> ? json : null;
  }

  /// Blockscout's `next_page_params` object as query parameters, or `null`
  /// when the response was the last page.
  static Map<String, String>? _nextPageParams(Map<String, Object?>? body) {
    final Object? raw = body?['next_page_params'];
    if (raw is! Map) {
      return null;
    }
    final Map<String, String> params = <String, String>{
      for (final MapEntry<Object?, Object?> entry in raw.entries)
        if (entry.value != null) '${entry.key}': '${entry.value}',
    };
    return params.isEmpty ? null : params;
  }

  static List<TokenTransfer> _parseTokenTransfers(Map<String, Object?>? json) {
    final Object? items = json?['items'];
    if (items is! List) {
      return const <TokenTransfer>[];
    }
    final List<TokenTransfer> result = <TokenTransfer>[];
    for (final Object? item in items) {
      if (item is! Map) {
        continue;
      }
      final Object? total = item['total'];
      final Object? token = item['token'];
      final Object? from = item['from'];
      final Object? to = item['to'];
      if (total is! Map || token is! Map || from is! Map || to is! Map) {
        continue;
      }
      // NFT transfers carry a token id instead of a fungible `value`.
      final BigInt? value = BigInt.tryParse('${total['value']}');
      final String? hash = item['transaction_hash'] as String?;
      final String? fromHash = from['hash'] as String?;
      final String? toHash = to['hash'] as String?;
      if (value == null ||
          hash == null ||
          fromHash == null ||
          toHash == null) {
        continue;
      }
      final Object? decimals = total['decimals'] ?? token['decimals'];
      final String symbol = (token['symbol'] as String? ?? '').trim();
      result.add(
        TokenTransfer(
          hash: hash,
          timestamp:
              DateTime.tryParse(item['timestamp'] as String? ?? '')?.toLocal() ??
                  DateTime.now(),
          from: fromHash,
          to: toHash,
          value: value,
          symbol: symbol.isEmpty ? '?' : symbol,
          decimals: decimals is num
              ? decimals.toInt()
              : int.tryParse('$decimals') ?? 0,
          contract: token['address_hash'] as String? ?? '',
        ),
      );
    }
    return result;
  }

  /// Resolves an ENS [name] (`alice.eth`) to its Ethereum address through the
  /// Universal Resolver, or `null` when the name points nowhere.
  ///
  /// Always asked of Ethereum mainnet — that is where ENS lives, and an EVM
  /// address is the same on every EVM chain. Throws [ChainApiException] when
  /// the lookup fails (including a name that needs an off-chain gateway, which
  /// is not supported): the caller must show the failure, never fall back to
  /// treating the text as an address.
  Future<String?> resolveEnsName(String name) async {
    final String? normal = Ens.normalize(name);
    if (normal == null) {
      throw const ChainApiException(
        'This name uses characters the wallet cannot resolve safely.',
        retryable: false,
      );
    }
    final Object? result;
    try {
      result = await _evmRpc(
        NetworkCatalog.ethereum,
        'eth_call',
        <Object?>[
          <String, Object?>{
            'to': Ens.universalResolver,
            'data': Ens.resolveCallData(normal),
          },
          'latest',
        ],
      );
    } on ChainApiException catch (error) {
      if (!error.retryable) {
        // A revert: the name has no resolver, or needs an off-chain lookup.
        return null;
      }
      rethrow;
    }
    return result is String ? Ens.decodeResolveResult(result) : null;
  }

  /// What the explorer knows about [address], for the pre-signature recipient
  /// check: a scam flag, a token contract, an ENS name.
  ///
  /// Only Blockscout-backed EVM networks answer this; every other chain
  /// returns `null` and the caller skips the check rather than guessing.
  /// Throws [ChainApiException] when the lookup fails — the caller must show
  /// "could not verify", never treat silence as a pass.
  Future<AddressInfo?> fetchAddressInfo(
    NetworkConfig network,
    String address,
  ) async {
    if (network.chain != ChainKind.evm || network.rpcUrl != null) {
      return null;
    }

    final Object? json = await _get('${network.apiBase}/addresses/$address');
    if (json is! Map<String, Object?>) {
      // 404: a fresh address with no history. Nothing to warn about.
      return null;
    }
    return AddressInfo.fromJson(json);
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
        // The API returns whole sat/vB today, but Bitcoin Core's minimum relay
        // fee is fractional, so a `num` cast keeps a future 0.1 sat/vB answer
        // from turning the whole estimate into "unknown".
        final num? satPerVb =
            (json as Map<String, Object?>?)?['halfHourFee'] as num?;
        if (satPerVb == null || satPerVb <= 0) {
          return null;
        }
        // ~140 vB is a typical native SegWit (P2WPKH) transfer.
        return BigInt.from(satPerVb.ceil()) * BigInt.from(140);
      }

      final Object? json = await _get('${network.apiBase}/stats');
      if (json is! Map<String, Object?>) {
        return null;
      }
      // Blockscout v2 reports floating-point gwei under `gas_prices`; the old
      // `gas_price` wei string is kept as a fallback for other deployments.
      final Object? prices = json['gas_prices'];
      if (prices is Map<String, Object?>) {
        final num? gwei =
            (prices['average'] ?? prices['fast'] ?? prices['slow']) as num?;
        if (gwei != null && gwei > 0) {
          // 21,000 gas is the cost of a plain value transfer.
          return BigInt.from((gwei * 1e9).round()) * BigInt.from(21000);
        }
      }
      final String? gasPriceWei = json['gas_price'] as String?;
      if (gasPriceWei == null) {
        return null;
      }
      // 21,000 gas is the cost of a plain value transfer.
      return (BigInt.tryParse(gasPriceWei) ?? BigInt.zero) * BigInt.from(21000);
    } catch (_) {
      return null;
    }
  }

  // --- EVM transaction submission -------------------------------------------

  /// Number of transactions already sent from [address] — the next transaction
  /// must use this as its nonce.
  Future<int> getTransactionCount(
    NetworkConfig network,
    String address,
  ) async {
    final Object? result = await _evmRpc(
      network,
      'eth_getTransactionCount',
      <Object?>[address, 'pending'],
    );
    return _hexToBigInt(result).toInt();
  }

  /// EIP-1559 fee parameters in wei per gas: the current base fee and the tip
  /// the node suggests.
  ///
  /// The tip is returned separately from the base fee so the UI can offer
  /// Low/Normal/High presets by scaling only the tip; the fee cap is built on
  /// top as `baseFee * 2 + tip`. On a node that does not report a base fee (or
  /// rejects the tip query) this falls back to the legacy gas price, so a
  /// type-2 transfer is never blocked by a missing fee.
  Future<({BigInt baseFee, BigInt maxPriorityFeePerGas})> fetchFeeData(
    NetworkConfig network,
  ) async {
    BigInt priority = BigInt.zero;
    try {
      priority = _hexToBigInt(
        await _evmRpc(network, 'eth_maxPriorityFeePerGas', const <Object?>[]),
      );
    } catch (_) {
      // Older nodes and some non-Ethereum chains lack the method.
    }

    BigInt baseFee = BigInt.zero;
    try {
      final Object? block = await _evmRpc(
        network,
        'eth_getBlockByNumber',
        <Object?>['latest', false],
      );
      if (block is Map<String, Object?>) {
        baseFee = _hexToBigInt(block['baseFeePerGas']);
      }
    } catch (_) {
      // Pre-London chain, or a node that will not serve the block.
    }

    if (priority == BigInt.zero && baseFee == BigInt.zero) {
      // No 1559 data at all: use the legacy gas price as the whole fee.
      priority =
          _hexToBigInt(await _evmRpc(network, 'eth_gasPrice', const <Object?>[]));
    }

    return (baseFee: baseFee, maxPriorityFeePerGas: priority);
  }

  /// Gas units a transfer to [to] of [value] wei (optionally carrying [data])
  /// would use.
  ///
  /// Falls back to 21,000 (the exact cost of a plain value transfer) when the
  /// node cannot estimate, so a transfer is never blocked by an estimator that
  /// dislikes an unfunded account.
  Future<BigInt> estimateTransferGas({
    required NetworkConfig network,
    required String from,
    required String to,
    required BigInt value,
    Uint8List? data,
  }) async {
    try {
      final Object? result = await _evmRpc(
        network,
        'eth_estimateGas',
        <Object?>[
          <String, Object?>{
            'from': from,
            'to': to,
            'value': _quantity(value),
            if (data != null && data.isNotEmpty) 'data': '0x${hex.encode(data)}',
          },
        ],
      );
      final BigInt gas = _hexToBigInt(result);
      return gas > BigInt.zero ? gas : BigInt.from(21000);
    } catch (_) {
      return BigInt.from(21000);
    }
  }

  /// Broadcasts a signed transaction and returns its hash.
  ///
  /// Walks the network's nodes in order, moving on only when one cannot be
  /// reached. The signed bytes are identical on every node, so a node that
  /// answers "already known" (the transaction reached it through an earlier
  /// attempt or gossip) is a success, and the hash is the keccak of the bytes.
  Future<String> sendRawTransaction(
    NetworkConfig network,
    String rawTransaction,
  ) async {
    final Object? result;
    try {
      result = await _evmRpc(
        network,
        'eth_sendRawTransaction',
        <Object?>[rawTransaction],
      );
    } on ChainApiException catch (error) {
      if (_isAlreadyKnown(error.message)) {
        return _rawTransactionHash(rawTransaction);
      }
      rethrow;
    }
    if (result is! String || result.isEmpty) {
      throw const ChainApiException(
        'The node accepted the transaction but returned no hash.',
        retryable: false,
      );
    }
    return result;
  }

  static bool _isAlreadyKnown(String message) {
    final String lower = message.toLowerCase();
    return lower.contains('already known') ||
        lower.contains('known transaction') ||
        lower.contains('already exists');
  }

  /// `keccak256(rawTransaction)` as `0x…` — the hash every node derives.
  static String _rawTransactionHash(String rawTransaction) {
    final String body = rawTransaction.startsWith('0x')
        ? rawTransaction.substring(2)
        : rawTransaction;
    final Uint8List bytes = Uint8List.fromList(hex.decode(body));
    return '0x${hex.encode(Hashing.keccak256(bytes))}';
  }

  /// Waits until [hash] is mined, returning whether it succeeded.
  ///
  /// [attempts] polls with a growing delay; giving up returns `null` rather than
  /// claiming failure, because the transaction may still confirm later.
  Future<bool?> waitForReceipt(
    NetworkConfig network,
    String hash, {
    int attempts = 12,
  }) async {
    for (int i = 0; i < attempts; i++) {
      await Future<void>.delayed(Duration(seconds: 2 + i));
      final Object? result = await _evmRpc(
        network,
        'eth_getTransactionReceipt',
        <Object?>[hash],
      );
      if (result is! Map<String, Object?>) {
        continue; // still in the mempool
      }
      return result['status'] == '0x1';
    }
    return null;
  }

  // --- Bitcoin transaction submission --------------------------------------

  /// Unspent outputs paying [address], newest chain tip first.
  ///
  /// Used to build a spend; the caller decides which to select.
  Future<List<BitcoinUtxo>> fetchBitcoinUtxos(
    NetworkConfig network,
    String address,
  ) async {
    if (network.chain != ChainKind.bitcoin) {
      return const <BitcoinUtxo>[];
    }
    final Object? json = await _get('${network.apiBase}/address/$address/utxo');
    return _parseBitcoinUtxos(json);
  }

  static List<BitcoinUtxo> _parseBitcoinUtxos(Object? json) {
    if (json is! List) {
      return const <BitcoinUtxo>[];
    }
    final List<BitcoinUtxo> utxos = <BitcoinUtxo>[];
    for (final Object? raw in json) {
      if (raw is! Map<String, Object?>) {
        continue;
      }
      final String? txid = raw['txid'] as String?;
      final int? vout = (raw['vout'] as num?)?.toInt();
      final num? value = raw['value'] as num?;
      if (txid == null || vout == null || value == null || value <= 0) {
        continue;
      }
      final Object? status = raw['status'];
      final bool confirmed =
          status is Map<String, Object?> && status['confirmed'] == true;
      utxos.add(
        BitcoinUtxo(
          txid: txid,
          vout: vout,
          value: BigInt.from(value.toInt()),
          confirmed: confirmed,
        ),
      );
    }
    return utxos;
  }

  /// A Bitcoin transaction as the explorer reports it, or `null` when the
  /// explorer does not know the txid.
  ///
  /// The whole transaction is read — every input with the coin it spent and
  /// every output with its script — because replacing it means rebuilding the
  /// same transfer with a larger fee.
  Future<BitcoinPriorTx?> fetchBitcoinTransaction(
    NetworkConfig network,
    String txid,
  ) async {
    if (network.chain != ChainKind.bitcoin) {
      return null;
    }
    final Object? json = await _get('${network.apiBase}/tx/$txid');
    return json is Map<String, Object?> ? _parseBitcoinPriorTx(json) : null;
  }

  static BitcoinPriorTx? _parseBitcoinPriorTx(Map<String, Object?> json) {
    final String? txid = json['txid'] as String?;
    final Object? vin = json['vin'];
    final Object? vout = json['vout'];
    if (txid == null || vin is! List || vout is! List) {
      return null;
    }

    final List<BitcoinPriorInput> inputs = <BitcoinPriorInput>[];
    for (final Object? raw in vin) {
      if (raw is! Map<String, Object?> || raw['is_coinbase'] == true) {
        return null;
      }
      final Object? prevout = raw['prevout'];
      final String? prevTxid = raw['txid'] as String?;
      final int? prevVout = (raw['vout'] as num?)?.toInt();
      if (prevout is! Map<String, Object?> ||
          prevTxid == null ||
          prevVout == null) {
        return null;
      }
      final num? value = prevout['value'] as num?;
      if (value == null) {
        return null;
      }
      inputs.add(
        BitcoinPriorInput(
          utxo: BitcoinUtxo(
            txid: prevTxid,
            vout: prevVout,
            value: BigInt.from(value.toInt()),
          ),
          sequence: (raw['sequence'] as num?)?.toInt() ?? 0xffffffff,
          address: prevout['scriptpubkey_address'] as String?,
          scriptType: prevout['scriptpubkey_type'] as String?,
        ),
      );
    }

    final List<BitcoinPriorOutput> outputs = <BitcoinPriorOutput>[];
    for (final Object? raw in vout) {
      if (raw is! Map<String, Object?>) {
        return null;
      }
      final String? script = raw['scriptpubkey'] as String?;
      final num? value = raw['value'] as num?;
      if (script == null || value == null) {
        return null;
      }
      outputs.add(
        BitcoinPriorOutput(
          output: BitcoinOutput(
            value: BigInt.from(value.toInt()),
            scriptPubKey: Uint8List.fromList(hex.decode(script)),
          ),
          address: raw['scriptpubkey_address'] as String?,
        ),
      );
    }

    final Object? status = json['status'];
    return BitcoinPriorTx(
      txid: txid,
      confirmed: status is Map<String, Object?> && status['confirmed'] == true,
      inputs: inputs,
      outputs: outputs,
    );
  }

  /// The network's ready-made confirmation tiers from mempool.space.
  ///
  /// Throws rather than guessing, so a transfer is never signed with a fee the
  /// user did not see.
  Future<BitcoinFeeTiers> fetchBitcoinFeeTiers(NetworkConfig network) async {
    final Object? json = await _get('${network.apiBase}/v1/fees/recommended');
    final BitcoinFeeTiers? tiers =
        json is Map<String, Object?> ? BitcoinFeeTiers.fromJson(json) : null;
    if (tiers == null) {
      throw const ChainApiException(
        'The node returned no fee estimate.',
      );
    }
    return tiers;
  }

  /// Recommended satoshis-per-vbyte for a ~30 minute confirmation target.
  ///
  /// Throws rather than guessing, so a transfer is never signed with a fee the
  /// user did not see.
  Future<int> fetchBitcoinFeeRate(NetworkConfig network) async =>
      (await fetchBitcoinFeeTiers(network)).halfHourFee;

  /// Broadcasts a raw Bitcoin transaction and returns its txid.
  Future<String> broadcastBitcoinTransaction(
    NetworkConfig network,
    String rawTransaction,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('${network.apiBase}/tx'),
            headers: const <String, String>{'Content-Type': 'text/plain'},
            body: rawTransaction,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ChainApiException('The network request timed out.');
    } catch (_) {
      throw const ChainApiException(
        'Could not reach the blockchain API. Check your connection.',
      );
    }

    final String body = utf8.decode(response.bodyBytes).trim();
    if (response.statusCode >= 400) {
      // mempool.space answers a rejected transaction with the reason in the
      // body — surface it, the user needs to know *why* it was refused.
      throw ChainApiException(
        body.isEmpty
            ? 'The node rejected the transaction (HTTP ${response.statusCode}).'
            : body,
        retryable: false,
      );
    }
    if (body.isEmpty) {
      throw const ChainApiException(
        'The node accepted the transaction but returned no txid.',
        retryable: false,
      );
    }
    return body;
  }

  /// Waits until [txid] is mined, returning whether it confirmed.
  ///
  /// Gives up with `null` rather than claiming failure, since a slow block may
  /// still include it.
  Future<bool?> waitForBitcoinConfirmation(
    NetworkConfig network,
    String txid, {
    int attempts = 12,
  }) async {
    for (int i = 0; i < attempts; i++) {
      await Future<void>.delayed(Duration(seconds: 5 + i * 2));
      try {
        final Object? json = await _get('${network.apiBase}/tx/$txid/status');
        if (json is Map<String, Object?> && json['confirmed'] == true) {
          return true;
        }
      } catch (_) {
        // A transient error is not a verdict; keep waiting.
      }
    }
    return null;
  }

  /// JSON-RPC call against the network's signing-side nodes, in order.
  ///
  /// Falls through to the next node only when the failure is a transport
  /// problem (unreachable, timeout, 5xx, 429, garbled body). A JSON-RPC error
  /// is the node's real answer — the same request would get the same answer
  /// elsewhere, and retrying could double-submit — so it is surfaced as is.
  /// Throws on chains the wallet cannot sign for.
  Future<Object?> _evmRpc(
    NetworkConfig network,
    String method,
    List<Object?> params,
  ) async {
    final List<String> urls = network.sendRpcUrls;
    if (network.chain != ChainKind.evm || urls.isEmpty) {
      throw ChainApiException(
        '${network.name} does not support sending yet.',
        retryable: false,
      );
    }
    ChainApiException? last;
    for (final String url in urls) {
      try {
        return await _rpc(url, method, params);
      } on ChainApiException catch (error) {
        if (!error.retryable) {
          rethrow;
        }
        last = error;
        AppLog.warning('RPC node $url unavailable for ${network.name}', error);
      }
    }
    throw last!;
  }

  /// `0x`-prefixed minimal hex quantity for a [BigInt].
  static String _quantity(BigInt value) =>
      '0x${value == BigInt.zero ? '0' : value.toRadixString(16)}';

  // --- HTTP ----------------------------------------------------------------

  /// ERC-20 balances for [address], largest USD value first.
  ///
  /// Returns an empty list on chains without a token index (Bitcoin, Solana,
  /// Aptos, and the JSON-RPC-only BNB Chain) and whenever the request fails:
  /// token data is a bonus and must never break the balance screen.
  Future<List<TokenBalance>> fetchTokenBalances(
    NetworkConfig network,
    String address,
  ) async {
    if (network.chain != ChainKind.evm || network.rpcUrl != null) {
      return const <TokenBalance>[];
    }
    try {
      final Object? json = await _get(
        '${network.apiBase}/addresses/$address/tokens?type=ERC-20',
      );
      return _parseTokenBalances(json);
    } catch (error) {
      AppLog.warning('Token balances unavailable for ${network.name}', error);
      return const <TokenBalance>[];
    }
  }

  /// Approvals this account has granted, largest allowance first.
  ///
  /// Returns an empty list on chains without a token index (Bitcoin, Solana,
  /// Aptos, and the JSON-RPC-only BNB Chain) and whenever the request fails:
  /// approvals are a safety net and must never break a screen.
  Future<List<TokenApproval>> fetchTokenApprovals(
    NetworkConfig network,
    String address,
  ) async {
    if (network.chain != ChainKind.evm || network.rpcUrl != null) {
      return const <TokenApproval>[];
    }
    try {
      final Object? json = await _get(
        '${network.apiBase}/addresses/$address/token-approvals',
      );
      return _parseTokenApprovals(json);
    } catch (error) {
      AppLog.warning('Token approvals unavailable for ${network.name}', error);
      return const <TokenApproval>[];
    }
  }

  static List<TokenApproval> _parseTokenApprovals(Object? json) {
    if (json is! Map<String, Object?>) {
      return const <TokenApproval>[];
    }
    final Object? items = json['items'];
    if (items is! List) {
      return const <TokenApproval>[];
    }

    final List<TokenApproval> approvals = <TokenApproval>[];
    for (final Object? item in items) {
      if (item is! Map) {
        continue;
      }
      final Object? token = item['token'];
      final Object? spender = item['spender'];
      if (token is! Map || spender is! Map) {
        continue;
      }

      // Blockscout v2 exposes the spender as `{hash}`; some deployments answer
      // with a bare hash string instead, so accept both.
      final String? spenderAddress =
          spender['hash'] as String? ?? spender['address'] as String?;
      final String? tokenAddress = token['address_hash'] as String?;
      if (spenderAddress == null || tokenAddress == null) {
        continue;
      }

      final BigInt amount =
          BigInt.tryParse('${item['value']}') ?? BigInt.zero;
      if (amount <= BigInt.zero) {
        continue;
      }

      final Object? decimals = token['decimals'];
      final String symbol = (token['symbol'] as String? ?? '').trim();

      approvals.add(
        TokenApproval(
          symbol: symbol.isEmpty ? '?' : symbol,
          tokenAddress: tokenAddress,
          spender: spenderAddress,
          amount: amount,
          decimals: decimals is num
              ? decimals.toInt()
              : int.tryParse('$decimals') ?? 0,
        ),
      );
    }

    // An unlimited allowance first: revoking those is what actually protects
    // the balance, so it must not hide below a row of dust allowances.
    approvals.sort((TokenApproval a, TokenApproval b) {
      if (a.isUnlimited != b.isUnlimited) {
        return a.isUnlimited ? -1 : 1;
      }
      return b.amount.compareTo(a.amount);
    });
    return approvals;
  }

  /// Live ERC-20 balance of [owner] for the [token] contract.
  ///
  /// A read-only `eth_call` of `balanceOf(address)` — the same call a token
  /// explorer makes. Used right before signing so a transfer is never signed
  /// against a holding that has already been spent elsewhere.
  ///
  /// Throws [ChainApiException] on a chain the wallet cannot sign for, or when
  /// the node is unreachable: a token send must refuse rather than sign blind.
  Future<BigInt> fetchTokenBalance({
    required NetworkConfig network,
    required String token,
    required String owner,
  }) async {
    final Object? result = await _evmRpc(
      network,
      'eth_call',
      <Object?>[
        <String, Object?>{
          'to': token,
          'data': '0x${hex.encode(EvmSigner.erc20BalanceOfData(owner))}',
        },
        'latest',
      ],
    );
    if (result is! String) {
      throw const ChainApiException(
        'The node returned no token balance.',
        retryable: false,
      );
    }
    final String body = result.startsWith('0x') ? result.substring(2) : result;
    if (body.length < 64) {
      throw const ChainApiException(
        'The node returned a malformed token balance.',
        retryable: false,
      );
    }
    return _hexToBigInt('0x${body.substring(0, 64)}');
  }

  static List<TokenBalance> _parseTokenBalances(Object? json) {
    if (json is! Map<String, Object?>) {
      return const <TokenBalance>[];
    }
    final Object? items = json['items'];
    if (items is! List) {
      return const <TokenBalance>[];
    }

    final List<TokenBalance> tokens = <TokenBalance>[];
    for (final Object? item in items) {
      if (item is! Map) {
        continue;
      }
      final Object? token = item['token'];
      if (token is! Map) {
        continue;
      }
      final Object? value = item['value'];
      final BigInt balance = BigInt.tryParse('$value') ?? BigInt.zero;
      if (balance <= BigInt.zero) {
        continue;
      }

      final Object? decimals = token['decimals'];
      final int decimalsValue = decimals is num
          ? decimals.toInt()
          : int.tryParse('$decimals') ?? 0;
      final String symbol = (token['symbol'] as String? ?? '').trim();

      tokens.add(TokenBalance(
        symbol: symbol.isEmpty ? '?' : symbol,
        name: token['name'] as String? ?? '',
        decimals: decimalsValue,
        balance: balance,
        contractAddress: token['address_hash'] as String? ?? '',
        usdRate: double.tryParse('${token['exchange_rate']}'),
      ));
    }

    tokens.sort((TokenBalance a, TokenBalance b) {
      final int byValue = (b.usdValue ?? -1).compareTo(a.usdValue ?? -1);
      return byValue != 0 ? byValue : a.symbol.compareTo(b.symbol);
    });
    return tokens;
  }

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
      );
    } catch (_) {
      throw const ChainApiException(
        'Could not reach the blockchain API. Check your connection.',
      );
    }

    if (response.statusCode == 404) {
      // An address with no history yet is not an error.
      return null;
    }
    if (response.statusCode >= 400) {
      throw ChainApiException(
        'The API rejected the request (HTTP ${response.statusCode}).',
        retryable: response.statusCode >= 500 || response.statusCode == 429,
      );
    }

    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const ChainApiException(
        'Unexpected response from the API.',
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
      );
    } catch (_) {
      throw const ChainApiException(
        'Could not reach the blockchain API. Check your connection.',
      );
    }

    if (response.statusCode >= 400) {
      throw ChainApiException(
        'The API rejected the request (HTTP ${response.statusCode}).',
        retryable: response.statusCode >= 500 || response.statusCode == 429,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const ChainApiException(
        'Unexpected response from the API.',
        retryable: false,
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw const ChainApiException(
        'Unexpected response from the API.',
        retryable: false,
      );
    }

    final Object? error = decoded['error'];
    if (error is Map<String, Object?>) {
      throw ChainApiException(
        error['message'] as String? ?? 'The node rejected the request.',
        retryable: false,
      );
    }

    return decoded['result'];
  }

  // --- Bitcoin parsing -----------------------------------------------------

  /// mempool.space returns confirmed history in pages of 25.
  static const int _bitcoinPageSize = 25;

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

      // The original's own fee cap, tip, gas limit and calldata. Blockscout v2
      // exposes them (hex quantities); a replacement must be priced from these
      // and carry identical calldata, so they are kept when present.
      final BigInt? maxFeePerGas = _parseQuantity(raw['max_fee_per_gas']);
      final BigInt? maxPriorityFeePerGas =
          _parseQuantity(raw['max_priority_fee_per_gas']);
      final BigInt? gasLimit = _parseQuantity(raw['gas_limit']);
      final String? rawInput = raw['raw_input'] is String &&
              (raw['raw_input'] as String).startsWith('0x')
          ? raw['raw_input'] as String
          : null;

      // Blockscout reports the nonce as an integer in v2 and hex in some
      // deployments, so accept either. The fee-cap fields below follow the
      // same rule (hex strings in the standard v2 response).
      final Object? nonceRaw = raw['nonce'];
      final int? nonce = nonceRaw is num
          ? nonceRaw.toInt()
          : nonceRaw is String
              ? int.tryParse(
                  nonceRaw.startsWith('0x')
                      ? nonceRaw.substring(2)
                      : nonceRaw,
                  radix: 16,
                )
              : null;

      // The sender pays the fee, so an outgoing transfer costs value + fee
      // while an incoming one only adds the value it actually delivered — the
      // fee was paid by the other side.
      final BigInt signed = incoming ? value : -(value + fee);

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
          nonce: nonce,
          maxFeePerGas: maxFeePerGas,
          maxPriorityFeePerGas: maxPriorityFeePerGas,
          gasLimit: gasLimit,
          rawInput: rawInput,
        ),
      );
    }

    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }

  /// A JSON-RPC-style quantity: `0x`-prefixed hex, a plain decimal string, or
  /// an integer. `null` when absent or unparseable — the callers treat that as
  /// "the API did not say", never as zero.
  static BigInt? _parseQuantity(Object? raw) {
    if (raw is num) {
      return BigInt.from(raw.toInt());
    }
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    return raw.startsWith('0x')
        ? BigInt.tryParse(raw.substring(2), radix: 16)
        : BigInt.tryParse(raw);
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

  Future<ActivityPage> _fetchSolanaPage(
    NetworkConfig network,
    String address,
    ActivityCursor? after,
  ) async {
    final String? before = after?.native?['before'];
    if (after != null && before == null) {
      return const ActivityPage();
    }
    final Object? signatures = await _rpc(
      network.apiBase,
      'getSignaturesForAddress',
      <Object?>[
        address,
        <String, Object?>{
          'limit': _solanaHistoryLimit,
          'before': ?before,
        },
      ],
    );
    if (signatures is! List) {
      return const ActivityPage();
    }

    final List<ChainTransaction> result = <ChainTransaction>[];
    String? lastSignature;
    for (final Object? entry in signatures.take(_solanaHistoryLimit)) {
      if (entry is! Map<String, Object?>) {
        continue;
      }
      final String? signature = entry['signature'] as String?;
      if (signature == null) {
        continue;
      }
      lastSignature = signature;
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
    return ActivityPage(
      native: result,
      next: signatures.length >= _solanaHistoryLimit && lastSignature != null
          ? ActivityCursor(native: <String, String>{'before': lastSignature})
          : null,
    );
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

  Future<ActivityPage> _fetchAptosPage(
    NetworkConfig network,
    String address,
    ActivityCursor? after,
  ) async {
    // The account feed is addressed by sequence number, newest page by
    // default. An older page is the `limit` numbers below the oldest one seen.
    final String? start = after?.native?['start'];
    if (after != null && start == null) {
      return const ActivityPage();
    }
    final String limit = after?.native?['limit'] ?? '$_aptosHistoryLimit';
    final Object? json = await _get(
      '${network.apiBase}/accounts/$address/transactions'
      '?limit=$limit${start == null ? '' : '&start=$start'}',
    );
    final List<ChainTransaction> items = _parseAptosTransactions(json, address);

    int? oldest;
    if (json is List) {
      for (final Object? raw in json) {
        final int? seq = raw is Map<String, Object?>
            ? int.tryParse('${raw['sequence_number']}')
            : null;
        if (seq != null && (oldest == null || seq < oldest)) {
          oldest = seq;
        }
      }
    }
    ActivityCursor? next;
    if (oldest != null && oldest > 0) {
      final int nextStart =
          oldest > _aptosHistoryLimit ? oldest - _aptosHistoryLimit : 0;
      next = ActivityCursor(
        native: <String, String>{
          'start': '$nextStart',
          'limit': '${oldest - nextStart}',
        },
      );
    }
    return ActivityPage(native: items, next: next);
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
