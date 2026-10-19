import '../../core/utils/units.dart';
import '../models/chain_kind.dart';
import '../networks/network_config.dart';

/// A parsed payment link: `bitcoin:`, `ethereum:` (EIP-681), `solana:` (Solana
/// Pay) or `aptos:`.
class PaymentLink {
  const PaymentLink({
    required this.network,
    required this.recipient,
    this.amount,
    this.tokenContract,
    this.uint256,
  });

  final NetworkConfig network;

  /// The recipient address. For an EIP-681 token transfer this is the
  /// `address` query parameter — whoever receives the tokens — never the token
  /// contract itself.
  final String recipient;

  /// Whole-coin amount as a decimal string, when the link carried one.
  final String? amount;

  /// Token contract of an EIP-681 `transfer` call
  /// (`ethereum:<token>@<chainId>/transfer?address=…&uint256=…`).
  final String? tokenContract;

  /// Raw transfer amount in the token's smallest unit, as written in the link.
  final String? uint256;

  /// `true` when the URI moves an ERC-20 token instead of the native coin.
  bool get isTokenTransfer => tokenContract != null;
}

/// Parses a payment URI into a [PaymentLink], or returns `null` when the scheme
/// is unknown, the address is missing, or an EIP-681 function call is not a
/// well-formed token `transfer` (any other function is refused, never misread
/// as a native send to the contract).
PaymentLink? parsePaymentLink(Uri uri) {
  final String scheme = uri.scheme.toLowerCase();
  final NetworkConfig? network = switch (scheme) {
    'bitcoin' => NetworkCatalog.bitcoin,
    'ethereum' => _evmNetwork(uri),
    'solana' => NetworkCatalog.solana,
    'aptos' => NetworkCatalog.aptos,
    _ => null,
  };
  if (network == null) {
    return null;
  }

  // An opaque URI puts the address in `path`; a few wallets use `host`.
  String value = uri.path.isNotEmpty ? uri.path : uri.host;

  // A trailing EIP-681 function name, e.g. `ethereum:<token>@1/transfer?…`.
  String? function;
  final int slash = value.indexOf('/');
  if (slash >= 0) {
    function = value.substring(slash + 1).trim();
    value = value.substring(0, slash);
  }

  final int at = value.indexOf('@'); // ethereum:<address>@<chainId>
  String address = (at >= 0 ? value.substring(0, at) : value).trim();
  if (address.isEmpty) {
    return null;
  }

  String? tokenContract;
  String? uint256;
  if (scheme == 'ethereum') {
    if (function != null) {
      // A token `transfer` carries its own recipient in `address`; treating
      // the token contract as the recipient would send ETH to a contract and
      // the payment would never arrive.
      if (function != 'transfer') {
        return null;
      }
      final String? to = uri.queryParameters['address']?.trim();
      final String? raw = uri.queryParameters['uint256'];
      if (to == null ||
          to.isEmpty ||
          raw == null ||
          BigInt.tryParse(raw) == null) {
        return null;
      }
      tokenContract = address;
      address = to;
      uint256 = raw;
    }
  } else if (function != null) {
    // The non-EVM schemes carry no function part (`solana:<addr>?amount=…`).
    return null;
  }

  // A BIP-21 link names no network; the address prefix does.
  final NetworkConfig linkNetwork =
      scheme == 'bitcoin' && address.toLowerCase().startsWith('tb1')
          ? NetworkCatalog.bitcoinTestnet
          : network;

  return PaymentLink(
    network: linkNetwork,
    recipient: address,
    amount: tokenContract == null ? _amountFor(uri, network) : null,
    tokenContract: tokenContract,
    uint256: uint256,
  );
}

/// Picks the EVM network by the `@chainId` in the link, or Ethereum by default.
NetworkConfig _evmNetwork(Uri uri) {
  final int? chainId = _ethereumChainId(uri);
  if (chainId != null) {
    for (final NetworkConfig network in NetworkCatalog.all) {
      if (network.chainId == chainId) {
        return network;
      }
    }
  }
  return NetworkCatalog.ethereum;
}

int? _ethereumChainId(Uri uri) {
  final String value = uri.path.isNotEmpty ? uri.path : uri.host;
  final int at = value.indexOf('@');
  if (at < 0) {
    return null;
  }
  return int.tryParse(value.substring(at + 1).split('/').first);
}

/// The amount in whole coins. EIP-681 carries wei in `value`; the other schemes
/// carry whole coins in `amount`.
String? _amountFor(Uri uri, NetworkConfig network) {
  final bool isEth = uri.scheme.toLowerCase() == 'ethereum';
  final String? raw =
      uri.queryParameters['amount'] ?? (isEth ? uri.queryParameters['value'] : null);
  if (raw == null || raw.isEmpty) {
    return null;
  }

  if (!isEth) {
    return raw;
  }

  final BigInt? wei = _parseWei(raw);
  if (wei == null) {
    return null;
  }
  return Units.format(
    wei,
    network.decimals,
    maxDecimals: network.decimals,
    group: false,
  );
}

BigInt? _parseWei(String raw) {
  if (!raw.contains('e') && !raw.contains('E')) {
    return BigInt.tryParse(raw);
  }
  final double? value = double.tryParse(raw);
  if (value == null || value.isNaN || value.isInfinite) {
    return null;
  }
  return BigInt.from(value);
}

/// Builds the payment-request URI for receiving [amount] (smallest units) of
/// the native coin at [address] on [network]: BIP-21 for Bitcoin, EIP-681 for
/// EVM chains (with `@chainId`), Solana Pay and `aptos:` for the rest.
///
/// Without an [amount] the plain address is returned — exactly what the QR
/// code carried before payment requests existed. The result round-trips
/// through [parsePaymentLink].
String buildPaymentLink({
  required NetworkConfig network,
  required String address,
  BigInt? amount,
}) {
  if (amount == null || amount <= BigInt.zero) {
    return address;
  }
  String whole() =>
      Units.format(amount, network.decimals, maxDecimals: network.decimals, group: false);

  return switch (network.chain) {
    ChainKind.bitcoin => 'bitcoin:$address?amount=${whole()}',
    ChainKind.evm => 'ethereum:$address'
        '${network.chainId == null ? '' : '@${network.chainId}'}'
        '?value=$amount',
    ChainKind.solana => 'solana:$address?amount=${whole()}',
    ChainKind.aptos => 'aptos:$address?amount=${whole()}',
  };
}
