import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';

import '../../core/crypto/base58.dart';
import '../../core/crypto/bech32.dart';
import '../../core/crypto/hashing.dart';
import '../models/chain_kind.dart';
import '../networks/network_config.dart';

/// Result of checking a destination address before a transfer.
class AddressValidation {
  const AddressValidation._(this.valid, this.reason);

  final bool valid;

  /// User-facing explanation when [valid] is `false`.
  final String? reason;

  static const AddressValidation ok = AddressValidation._(true, null);

  factory AddressValidation.invalid(String reason) =>
      AddressValidation._(false, reason);
}

/// Validates a recipient address for the active [NetworkConfig].
///
/// The send flow used to accept anything eight characters or longer, which
/// would happily take a typo, an address for the wrong network, or a garbage
/// string. This checks the structure and — where the format has one — the
/// checksum (bech32/BIP-350, Base58Check, EIP-55).
class AddressValidator {
  const AddressValidator._();

  static final RegExp _hex40 = RegExp(r'^[0-9a-fA-F]{40}$');
  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]+$');
  static final RegExp _digit = RegExp(r'[0-9]');

  /// Validates [input] for [network]; surrounding whitespace is ignored.
  static AddressValidation validate(NetworkConfig network, String input) {
    final String address = input.trim();
    if (address.isEmpty) {
      return AddressValidation.invalid('Enter a recipient address');
    }

    return switch (network.chain) {
      ChainKind.bitcoin => _bitcoin(network, address),
      ChainKind.evm => _evm(address),
      ChainKind.solana => _solana(address),
      ChainKind.aptos => _aptos(address),
    };
  }

  static AddressValidation _bitcoin(NetworkConfig network, String address) {
    final Bech32Data? decoded = Bech32.decode(address);
    if (decoded != null) {
      if (decoded.hrp != network.hrp) {
        return AddressValidation.invalid(
          'This address is for a different Bitcoin network',
        );
      }
      if (Bech32.decodeSegwit(decoded) == null) {
        return AddressValidation.invalid('Invalid Bitcoin SegWit address');
      }
      return AddressValidation.ok;
    }

    // Legacy P2PKH / P2SH addresses are Base58Check-encoded.
    final Uint8List? payload = Base58.decodeCheck(address);
    if (payload == null || payload.length != 21) {
      return AddressValidation.invalid('Invalid Bitcoin address');
    }
    final bool mainnet = network.hrp == 'bc';
    final Set<int> allowedVersions =
        mainnet ? <int>{0x00, 0x05} : <int>{0x6f, 0xc4};
    if (!allowedVersions.contains(payload[0])) {
      return AddressValidation.invalid(
        'This address is for a different Bitcoin network',
      );
    }
    return AddressValidation.ok;
  }

  static AddressValidation _evm(String address) {
    if (!address.startsWith('0x') && !address.startsWith('0X')) {
      return AddressValidation.invalid('An EVM address starts with 0x');
    }
    final String body = address.substring(2);
    if (!_hex40.hasMatch(body)) {
      return AddressValidation.invalid('An EVM address has 40 hex characters');
    }

    // EIP-55 only defines meaning for mixed-case addresses; all-lowercase and
    // all-uppercase forms are commonly used and accepted as-is.
    final bool hasUpper = body != body.toLowerCase();
    final bool hasLower = body != body.toUpperCase();
    if (hasUpper && hasLower && !_matchesChecksum(body)) {
      return AddressValidation.invalid('The address checksum does not match');
    }
    return AddressValidation.ok;
  }

  static bool _matchesChecksum(String body) {
    final String lower = body.toLowerCase();
    final String hash = hex.encode(
      Hashing.keccak256(Uint8List.fromList(utf8.encode(lower))),
    );
    for (int i = 0; i < lower.length; i++) {
      final String character = body[i];
      if (_digit.hasMatch(character)) {
        continue;
      }
      final bool shouldBeUpper = int.parse(hash[i], radix: 16) >= 8;
      if (shouldBeUpper != (character == character.toUpperCase())) {
        return false;
      }
    }
    return true;
  }

  static AddressValidation _solana(String address) {
    final Uint8List? decoded = Base58.decode(address);
    if (decoded == null || decoded.length != 32) {
      return AddressValidation.invalid('Invalid Solana address');
    }
    return AddressValidation.ok;
  }

  static AddressValidation _aptos(String address) {
    if (!address.startsWith('0x') && !address.startsWith('0X')) {
      return AddressValidation.invalid('An Aptos address starts with 0x');
    }
    final String body = address.substring(2);
    if (body.isEmpty || body.length > 64 || !_hex.hasMatch(body)) {
      return AddressValidation.invalid('Invalid Aptos address');
    }
    return AddressValidation.ok;
  }
}
