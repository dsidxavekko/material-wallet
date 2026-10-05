import 'package:flutter/material.dart';

import '../models/chain_kind.dart';

/// A blockchain the wallet can connect to.
///
/// Carries everything needed to work with the chain: how addresses are derived,
/// which public API to query for balance/history and which block explorer to
/// link to.
@immutable
class NetworkConfig {
  const NetworkConfig({
    required this.id,
    required this.name,
    required this.chain,
    required this.symbol,
    required this.decimals,
    required this.apiBase,
    required this.explorerBase,
    required this.color,
    this.priceId,
    this.addressHrp,
    this.isTestnet = false,
    this.rpcUrl,
    this.addressPath = '/address/{address}',
    this.txPath = '/tx/{hash}',
    this.chainId,
    this.sendRpcUrl,
  });

  final String id;
  final String name;
  final ChainKind chain;

  /// Native currency ticker, e.g. `BTC` or `ETH`.
  final String symbol;

  /// Decimal places of the smallest unit (8 for BTC, 18 for EVM).
  final int decimals;

  /// Base URL of the public API used for balance and history.
  final String apiBase;

  /// Block explorer base URL, used for "view on explorer" links.
  final String explorerBase;

  /// Brand color for avatars and charts.
  final Color color;

  /// CoinGecko id used for price data; `null` when the coin has no market
  /// price (testnets).
  final String? priceId;

  /// bech32 human-readable part for Bitcoin networks (`bc` / `tb`).
  final String? addressHrp;

  final bool isTestnet;

  /// EVM JSON-RPC endpoint, used by chains that have no key-less Blockscout
  /// instance (BNB Chain). When set, balance/fee come from JSON-RPC calls and
  /// the REST [apiBase] is ignored.
  final String? rpcUrl;

  /// Path template (after [explorerBase]) for an address link.
  final String addressPath;

  /// Path template (after [explorerBase]) for a transaction link.
  final String txPath;

  /// EIP-155 chain id, required to sign a transaction for this network.
  ///
  /// Binds a signature to one chain so it can never be replayed elsewhere.
  /// `null` on chains the wallet cannot sign for (Bitcoin, Solana, Aptos).
  final int? chainId;

  /// JSON-RPC endpoint used **only** for broadcasting signed transactions.
  ///
  /// Kept separate from [rpcUrl] on purpose: setting `rpcUrl` switches balance
  /// and history reads to JSON-RPC and disables the Blockscout token index, so
  /// the two must not be conflated.
  final String? sendRpcUrl;

  /// `true` when the wallet can build and broadcast a transaction here.
  bool get canSign => chainId != null && sendRpcUrl != null;

  String get group => switch (chain) {
        ChainKind.bitcoin => 'Bitcoin',
        ChainKind.evm => 'EVM',
        ChainKind.solana => 'Solana',
        ChainKind.aptos => 'Aptos',
      };

  String get hrp => addressHrp ?? 'bc';

  String explorerAddress(String address) =>
      '$explorerBase${addressPath.replaceFirst('{address}', address)}';

  String explorerTx(String hash) =>
      '$explorerBase${txPath.replaceFirst('{hash}', hash)}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NetworkConfig &&
          other.id == id &&
          other.apiBase == apiBase &&
          other.isTestnet == isTestnet);

  @override
  int get hashCode => Object.hash(id, apiBase, isTestnet);

  @override
  String toString() => 'NetworkConfig($id)';
}

/// Every network the wallet supports.
///
/// Balance and history come from free, key-less public APIs:
/// * **Bitcoin** — `mempool.space`
/// * **EVM** — public Blockscout instances
class NetworkCatalog {
  const NetworkCatalog._();

  // --- Bitcoin -------------------------------------------------------------

  static const NetworkConfig bitcoin = NetworkConfig(
    id: 'bitcoin',
    name: 'Bitcoin',
    chain: ChainKind.bitcoin,
    symbol: 'BTC',
    decimals: 8,
    apiBase: 'https://mempool.space/api',
    explorerBase: 'https://mempool.space',
    color: Color(0xFFF7931A),
    priceId: 'bitcoin',
    addressHrp: 'bc',
  );

  static const NetworkConfig bitcoinTestnet = NetworkConfig(
    id: 'bitcoin-testnet',
    name: 'Bitcoin Testnet',
    chain: ChainKind.bitcoin,
    symbol: 'tBTC',
    decimals: 8,
    apiBase: 'https://mempool.space/testnet/api',
    explorerBase: 'https://mempool.space/testnet',
    color: Color(0xFFF7931A),
    addressHrp: 'tb',
    isTestnet: true,
  );

  // --- EVM -----------------------------------------------------------------

  static const NetworkConfig ethereum = NetworkConfig(
    id: 'ethereum',
    name: 'Ethereum',
    chain: ChainKind.evm,
    symbol: 'ETH',
    decimals: 18,
    apiBase: 'https://eth.blockscout.com/api/v2',
    explorerBase: 'https://eth.blockscout.com',
    color: Color(0xFF627EEA),
    priceId: 'ethereum',
    chainId: 1,
    sendRpcUrl: 'https://ethereum-rpc.publicnode.com',
  );

  static const NetworkConfig sepolia = NetworkConfig(
    id: 'sepolia',
    name: 'Ethereum Sepolia',
    chain: ChainKind.evm,
    symbol: 'ETH',
    decimals: 18,
    apiBase: 'https://eth-sepolia.blockscout.com/api/v2',
    explorerBase: 'https://eth-sepolia.blockscout.com',
    color: Color(0xFF627EEA),
    isTestnet: true,
    chainId: 11155111,
    sendRpcUrl: 'https://ethereum-sepolia-rpc.publicnode.com',
  );

  static const NetworkConfig base = NetworkConfig(
    id: 'base',
    name: 'Base',
    chain: ChainKind.evm,
    symbol: 'ETH',
    decimals: 18,
    apiBase: 'https://base.blockscout.com/api/v2',
    explorerBase: 'https://base.blockscout.com',
    color: Color(0xFF0052FF),
    priceId: 'ethereum',
    chainId: 8453,
    sendRpcUrl: 'https://base-rpc.publicnode.com',
  );

  static const NetworkConfig polygon = NetworkConfig(
    id: 'polygon',
    name: 'Polygon',
    chain: ChainKind.evm,
    symbol: 'POL',
    decimals: 18,
    apiBase: 'https://polygon.blockscout.com/api/v2',
    explorerBase: 'https://polygon.blockscout.com',
    color: Color(0xFF8247E5),
    priceId: 'polygon-ecosystem-token',
    chainId: 137,
    sendRpcUrl: 'https://polygon-bor-rpc.publicnode.com',
  );

  static const NetworkConfig arbitrum = NetworkConfig(
    id: 'arbitrum',
    name: 'Arbitrum One',
    chain: ChainKind.evm,
    symbol: 'ETH',
    decimals: 18,
    apiBase: 'https://arbitrum.blockscout.com/api/v2',
    explorerBase: 'https://arbitrum.blockscout.com',
    color: Color(0xFF28A0F0),
    priceId: 'ethereum',
    chainId: 42161,
    sendRpcUrl: 'https://arbitrum-one-rpc.publicnode.com',
  );

  // --- BNB Chain (key-less JSON-RPC) ---------------------------------------

  /// BNB Chain has no public Blockscout instance, so balance and the gas price
  /// come from a public JSON-RPC node. Without an API key there is no
  /// address-history index, so the activity list stays empty.
  static const NetworkConfig bnb = NetworkConfig(
    id: 'bnb',
    name: 'BNB Chain',
    chain: ChainKind.evm,
    symbol: 'BNB',
    decimals: 18,
    apiBase: 'https://bsc-rpc.publicnode.com',
    rpcUrl: 'https://bsc-rpc.publicnode.com',
    explorerBase: 'https://bscscan.com',
    color: Color(0xFFF0B90B),
    priceId: 'binancecoin',
    chainId: 56,
  );

  // --- Solana --------------------------------------------------------------

  static const NetworkConfig solana = NetworkConfig(
    id: 'solana',
    name: 'Solana',
    chain: ChainKind.solana,
    symbol: 'SOL',
    decimals: 9,
    apiBase: 'https://api.mainnet-beta.solana.com',
    explorerBase: 'https://explorer.solana.com',
    color: Color(0xFF9945FF),
    priceId: 'solana',
  );

  // --- Aptos ---------------------------------------------------------------

  static const NetworkConfig aptos = NetworkConfig(
    id: 'aptos',
    name: 'Aptos',
    chain: ChainKind.aptos,
    symbol: 'APT',
    decimals: 8,
    apiBase: 'https://fullnode.mainnet.aptoslabs.com/v1',
    explorerBase: 'https://explorer.aptoslabs.com',
    color: Color(0xFF06B6D4),
    priceId: 'aptos',
    addressPath: '/account/{address}?network=mainnet',
    txPath: '/txn/{hash}?network=mainnet',
  );

  static const List<NetworkConfig> all = <NetworkConfig>[
    bitcoin,
    bitcoinTestnet,
    ethereum,
    sepolia,
    base,
    bnb,
    polygon,
    arbitrum,
    solana,
    aptos,
  ];

  /// Networks grouped for the picker UI, mainnets first.
  static List<NetworkConfig> get mainnets =>
      all.where((n) => !n.isTestnet).toList(growable: false);

  static List<NetworkConfig> get testnets =>
      all.where((n) => n.isTestnet).toList(growable: false);

  static NetworkConfig byId(String id) =>
      all.firstWhere((n) => n.id == id, orElse: () => bitcoin);
}
