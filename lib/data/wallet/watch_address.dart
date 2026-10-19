import 'package:flutter/foundation.dart';

import '../models/chain_kind.dart';
import '../networks/network_config.dart';
import 'address_validator.dart';

/// An address recognised as belonging to one chain family.
@immutable
class WatchAddress {
  const WatchAddress({
    required this.family,
    required this.label,
    required this.address,
  });

  /// Storage key: `btc`, `btc-test`, `evm`, `sol` or `apt`.
  final String family;

  /// What to call the family in the UI.
  final String label;

  final String address;
}

/// Works out which chain family an address belongs to, so a watch-only wallet
/// needs nothing but the pasted address.
///
/// A wallet keeps at most one address per family: an EVM address is the same on
/// every EVM network, a Solana address on both Solana networks.
class WatchAddresses {
  const WatchAddresses._();

  /// The family key of [network].
  static String familyOf(NetworkConfig network) => switch (network.chain) {
        ChainKind.bitcoin => network.hrp == 'bc' ? 'btc' : 'btc-test',
        ChainKind.evm => 'evm',
        ChainKind.solana => 'sol',
        ChainKind.aptos => 'apt',
      };

  static const Map<String, String> labels = <String, String>{
    'btc': 'Bitcoin',
    'btc-test': 'Bitcoin testnet',
    'evm': 'EVM networks',
    'sol': 'Solana',
    'apt': 'Aptos',
  };

  static final RegExp _evmShape = RegExp(r'^0[xX][0-9a-fA-F]{40}$');

  /// Pulls the bare address out of a pasted or scanned payment link
  /// (`bitcoin:bc1…?amount=…`, `ethereum:0x…@1`, `solana:…`); plain addresses
  /// pass through untouched.
  static String extract(String raw) {
    String value = raw.trim();
    final RegExpMatch? scheme =
        RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:(//)?').firstMatch(value);
    if (scheme != null) {
      value = value.substring(scheme.end);
    }
    final int cut = value.indexOf(RegExp(r'[?@/]'));
    return cut < 0 ? value : value.substring(0, cut);
  }

  /// Classifies [input], or returns `null` when it is no address the wallet can
  /// follow. Surrounding whitespace is ignored.
  static WatchAddress? detect(String input) {
    final String address = input.trim();
    if (address.isEmpty) {
      return null;
    }
    // A 0x + 40-hex string is an EVM address; any other 0x form is Aptos. An
    // Aptos address that happens to be exactly 40 hex digits is the one case
    // this reads as EVM — the checksum cannot tell them apart.
    final NetworkConfig? network = _evmShape.hasMatch(address)
        ? NetworkCatalog.ethereum
        : <NetworkConfig>[
            NetworkCatalog.bitcoin,
            NetworkCatalog.bitcoinTestnet,
            NetworkCatalog.solana,
            NetworkCatalog.aptos,
          ].cast<NetworkConfig?>().firstWhere(
              (NetworkConfig? n) =>
                  AddressValidator.validate(n!, address).valid,
              orElse: () => null,
            );
    if (network == null || !AddressValidator.validate(network, address).valid) {
      return null;
    }
    final String family = familyOf(network);
    return WatchAddress(
      family: family,
      label: labels[family]!,
      address: address,
    );
  }

  /// Why [input] was refused, in words fit for the field's error line.
  static String? explain(String input) {
    final String address = input.trim();
    if (address.isEmpty) {
      return null;
    }
    if (detect(address) != null) {
      return null;
    }
    if (_evmShape.hasMatch(address)) {
      return AddressValidator.validate(NetworkCatalog.ethereum, address).reason;
    }
    return 'Not a Bitcoin, EVM, Solana or Aptos address';
  }
}
