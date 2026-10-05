import 'dart:typed_data';

/// bech32 / bech32m encoding flavours ([BIP-173], [BIP-350]).
enum Bech32Encoding { bech32, bech32m }

/// A decoded bech32 string: its human-readable part, the 5-bit data values
/// (checksum removed) and which checksum constant matched.
class Bech32Data {
  const Bech32Data({
    required this.hrp,
    required this.data,
    required this.encoding,
  });

  final String hrp;
  final List<int> data;
  final Bech32Encoding encoding;

  @override
  String toString() => 'Bech32Data($hrp, $data, $encoding)';
}

/// A decoded SegWit output: witness version plus the raw witness program.
class SegwitAddress {
  const SegwitAddress({required this.version, required this.program});

  final int version;
  final Uint8List program;
}

/// [BIP-173](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki)
/// bech32 / [BIP-350](https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki)
/// bech32m codec.
///
/// The encoder renders native SegWit (P2WPKH / P2TR) receive addresses; the
/// decoder exists so recipient addresses can be validated before a transfer.
class Bech32 {
  const Bech32._();

  static const String _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  static const List<int> _generator = <int>[
    0x3b6a57b2,
    0x26508e6d,
    0x1ea119fa,
    0x3d4233dd,
    0x2a1462b3,
  ];

  static const int _bech32Const = 1;
  static const int _bech32mConst = 0x2bc830a3;

  /// Encodes [program] as a SegWit address, e.g. `bc1q…` for Bitcoin mainnet.
  ///
  /// Witness version 0 uses the original bech32 checksum; version 1 and above
  /// (e.g. Taproot) use bech32m, as required by BIP-350.
  static String encodeSegwit({
    required String hrp,
    required int witnessVersion,
    required List<int> program,
  }) {
    final List<int> data = <int>[
      witnessVersion,
      ..._convertBits(program, 8, 5, true),
    ];
    final int constant =
        witnessVersion == 0 ? _bech32Const : _bech32mConst;
    final List<int> checksum = _createChecksum(hrp, data, constant);
    final StringBuffer buffer = StringBuffer(hrp)..write('1');
    for (final int value in <int>[...data, ...checksum]) {
      buffer.write(_charset[value]);
    }
    return buffer.toString();
  }

  /// Decodes [input], returning `null` for anything that is not a valid bech32
  /// or bech32m string (bad charset, bad checksum, mixed case, wrong length).
  static Bech32Data? decode(String input) {
    if (input.length < 8 || input.length > 90) {
      return null;
    }

    final bool hasLower = input != input.toUpperCase();
    final bool hasUpper = input != input.toLowerCase();
    if (hasLower && hasUpper) {
      // Mixed case is explicitly forbidden by BIP-173.
      return null;
    }
    final String lower = input.toLowerCase();

    final int separator = lower.lastIndexOf('1');
    if (separator < 1 || separator + 7 > lower.length) {
      return null;
    }

    final String hrp = lower.substring(0, separator);
    for (final int code in hrp.codeUnits) {
      if (code < 33 || code > 126) {
        return null;
      }
    }

    final List<int> values = <int>[];
    for (int i = separator + 1; i < lower.length; i++) {
      final int value = _charset.indexOf(lower[i]);
      if (value == -1) {
        return null;
      }
      values.add(value);
    }

    final int polymod = _polymod(<int>[..._hrpExpand(hrp), ...values]);
    final Bech32Encoding encoding;
    if (polymod == _bech32Const) {
      encoding = Bech32Encoding.bech32;
    } else if (polymod == _bech32mConst) {
      encoding = Bech32Encoding.bech32m;
    } else {
      return null;
    }

    return Bech32Data(
      hrp: hrp,
      data: values.sublist(0, values.length - 6),
      encoding: encoding,
    );
  }

  /// Extracts the witness version and program from a decoded address.
  ///
  /// Enforces the BIP-173/350 rules: program length 2–40 bytes, v0 must be
  /// bech32 and 20/32 bytes, v1+ must be bech32m, and the 5-bit padding must be
  /// zero. Returns `null` when any of that fails.
  static SegwitAddress? decodeSegwit(Bech32Data decoded) {
    final List<int> data = decoded.data;
    if (data.isEmpty) {
      return null;
    }
    final int version = data[0];
    if (version > 16) {
      return null;
    }

    final List<int> program = _convertBits(data.sublist(1), 5, 8, false);
    if (program.length < 2 || program.length > 40) {
      return null;
    }
    if (version == 0 && program.length != 20 && program.length != 32) {
      return null;
    }
    if (version == 0 && decoded.encoding != Bech32Encoding.bech32) {
      return null;
    }
    if (version != 0 && decoded.encoding != Bech32Encoding.bech32m) {
      return null;
    }

    // Re-encoding must reproduce the input exactly, otherwise the discarded
    // padding bits were non-zero and the address is malformed.
    final List<int> reencoded = _convertBits(program, 8, 5, true);
    final List<int> original = data.sublist(1);
    if (reencoded.length != original.length) {
      return null;
    }
    for (int i = 0; i < reencoded.length; i++) {
      if (reencoded[i] != original[i]) {
        return null;
      }
    }

    return SegwitAddress(
      version: version,
      program: Uint8List.fromList(program),
    );
  }

  static List<int> _createChecksum(String hrp, List<int> data, int constant) {
    final List<int> values = <int>[
      ..._hrpExpand(hrp),
      ...data,
      0,
      0,
      0,
      0,
      0,
      0,
    ];
    final int polymod = _polymod(values) ^ constant;
    return List<int>.generate(6, (i) => (polymod >> (5 * (5 - i))) & 31);
  }

  static List<int> _hrpExpand(String hrp) {
    final List<int> codes = hrp.codeUnits;
    return <int>[
      ...codes.map((c) => c >> 5),
      0,
      ...codes.map((c) => c & 31),
    ];
  }

  static int _polymod(List<int> values) {
    int checksum = 1;
    for (final int value in values) {
      final int top = checksum >> 25;
      checksum = ((checksum & 0x1ffffff) << 5) ^ value;
      for (int i = 0; i < 5; i++) {
        if (((top >> i) & 1) == 1) {
          checksum ^= _generator[i];
        }
      }
    }
    return checksum;
  }

  /// Regroups bits from [fromBits] to [toBits], as required by bech32.
  static List<int> _convertBits(
    List<int> data,
    int fromBits,
    int toBits,
    bool pad,
  ) {
    int accumulator = 0;
    int bits = 0;
    final int maxValue = (1 << toBits) - 1;
    final List<int> result = <int>[];

    for (final int value in data) {
      accumulator = (accumulator << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((accumulator >> bits) & maxValue);
      }
    }

    if (pad && bits > 0) {
      result.add((accumulator << (toBits - bits)) & maxValue);
    }
    return result;
  }
}
