import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';

import 'hashing.dart';

/// ENS name handling for a recipient field: normalisation, EIP-137 namehash and
/// the ABI for a Universal Resolver `resolve(name, addr(node))` lookup.
///
/// Pure, so the encoding can be pinned by the published EIP-137 vectors without
/// a node.
class Ens {
  const Ens._();

  /// The ENS Universal Resolver proxy on Ethereum mainnet. It resolves any
  /// name (wildcards included) in one `eth_call`.
  static const String universalResolver =
      '0xeeeeeeee14d718c2b47d9923deab1335e144eeee';

  /// `resolve(bytes,bytes)`.
  static const String _resolveSelector = '9061b923';

  /// `addr(bytes32)`.
  static const String _addrSelector = '3b3b57de';

  static final RegExp _label = RegExp(r'^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$');

  /// Whether [input] looks like a name the user means to resolve.
  static bool looksLikeName(String input) {
    final String value = input.trim().toLowerCase();
    return value.endsWith('.eth') && !value.contains(' ') && !value.contains('@');
  }

  /// The lowercase name, or `null` when it contains anything outside plain
  /// ASCII letters, digits, `-` and `_`.
  ///
  /// Full UTS-46 normalisation (emoji, accents) is deliberately not done: a
  /// homoglyph that normalises differently than the registrar did would resolve
  /// to the wrong owner, so such names are refused instead of guessed.
  static String? normalize(String input) {
    final String value = input.trim().toLowerCase();
    if (value.isEmpty || value.length > 253) {
      return null;
    }
    final List<String> labels = value.split('.');
    for (final String label in labels) {
      if (label.isEmpty || label.length > 63 || !_label.hasMatch(label)) {
        return null;
      }
    }
    return value;
  }

  /// EIP-137 namehash of an already normalised [name].
  static Uint8List namehash(String name) {
    Uint8List node = Uint8List(32);
    if (name.isEmpty) {
      return node;
    }
    for (final String label in name.split('.').reversed) {
      final Uint8List labelHash =
          Hashing.keccak256(Uint8List.fromList(utf8.encode(label)));
      node = Hashing.keccak256(Uint8List.fromList(<int>[...node, ...labelHash]));
    }
    return node;
  }

  /// DNS wire format used by ENSIP-10: length-prefixed labels, zero-terminated.
  static Uint8List dnsEncode(String name) {
    final List<int> out = <int>[];
    for (final String label in name.split('.')) {
      final List<int> bytes = utf8.encode(label);
      out
        ..add(bytes.length)
        ..addAll(bytes);
    }
    out.add(0);
    return Uint8List.fromList(out);
  }

  /// `eth_call` data for `UniversalResolver.resolve(dnsEncode(name),
  /// addr(namehash(name)))`.
  static String resolveCallData(String name) {
    final Uint8List dnsName = dnsEncode(name);
    final Uint8List inner = Uint8List.fromList(<int>[
      ...hex.decode(_addrSelector),
      ...namehash(name),
    ]);

    Uint8List padded(Uint8List data) {
      final int rem = data.length % 32;
      return rem == 0
          ? data
          : Uint8List.fromList(<int>[...data, ...Uint8List(32 - rem)]);
    }

    Uint8List word(int value) {
      final Uint8List out = Uint8List(32);
      out[30] = (value >> 8) & 0xff;
      out[31] = value & 0xff;
      return out;
    }

    final Uint8List nameTail = padded(dnsName);
    final Uint8List innerTail = padded(inner);
    // Two dynamic arguments: heads are the offsets of their tails.
    final int nameOffset = 0x40;
    final int innerOffset = nameOffset + 32 + nameTail.length;

    final Uint8List body = Uint8List.fromList(<int>[
      ...word(nameOffset),
      ...word(innerOffset),
      ...word(dnsName.length),
      ...nameTail,
      ...word(inner.length),
      ...innerTail,
    ]);
    return '0x$_resolveSelector${hex.encode(body)}';
  }

  /// The address in a `resolve` return value `(bytes result, address resolver)`
  /// whose `result` is `abi.encode(address)`. `null` for an empty answer or
  /// the zero address — a name nobody pointed anywhere.
  static String? decodeResolveResult(String returnData) {
    final String body =
        returnData.startsWith('0x') ? returnData.substring(2) : returnData;
    if (body.length < 64 * 2) {
      return null;
    }
    final Uint8List data = Uint8List.fromList(hex.decode(body));

    int readInt(int offset) {
      if (offset + 32 > data.length) {
        return -1;
      }
      // Offsets and lengths in a sane answer fit in 16 bits.
      for (int i = 0; i < 30; i++) {
        if (data[offset + i] != 0) {
          return -1;
        }
      }
      return (data[offset + 30] << 8) | data[offset + 31];
    }

    final int bytesOffset = readInt(0);
    if (bytesOffset < 0) {
      return null;
    }
    final int length = readInt(bytesOffset);
    if (length < 32 || bytesOffset + 32 + length > data.length) {
      return null;
    }
    final Uint8List address = Uint8List.sublistView(
      data,
      bytesOffset + 32 + 12,
      bytesOffset + 32 + 32,
    );
    if (address.every((int b) => b == 0)) {
      return null;
    }
    return '0x${hex.encode(address)}';
  }
}
