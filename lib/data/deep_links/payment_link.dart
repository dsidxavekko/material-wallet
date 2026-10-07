import '../../core/utils/units.dart';
import '../networks/network_config.dart';

/// A parsed payment link: `bitcoin:`, `ethereum:` (EIP-681), `solana:` (Solana
/// Pay) or `aptos:`.
class PaymentLink {
  const PaymentLink({
    required this.network,
    required this.recipient,
    this.amount,
  });

  final NetworkConfig network;

  /// The recipient address.
  final String recipient;

  /// Whole-coin amount as a decimal string, when the link carried one.
  final String? amount;
}

/// Parses a payment URI into a [PaymentLink], or returns `null` when the scheme
/// is unknown or the address is missing.
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
  String recipient = uri.path.isNotEmpty ? uri.path : uri.host;
  final int at = recipient.indexOf('@'); // ethereum:<address>@<chainId>
  if (at >= 0) {
    recipient = recipient.substring(0, at);
  }
  final int slash = recipient.indexOf('/'); // ethereum:<address>/<function>
  if (slash >= 0) {
    recipient = recipient.substring(0, slash);
  }
  recipient = recipient.trim();
  if (recipient.isEmpty) {
    return null;
  }

  return PaymentLink(
    network: network,
    recipient: recipient,
    amount: _amountFor(uri, network),
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
