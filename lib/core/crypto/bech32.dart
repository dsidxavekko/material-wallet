/// Minimal [BIP-173](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki)
/// bech32 encoder.
///
/// Only the encoding path is implemented because that is all a wallet needs to
/// render native SegWit (P2WPKH) receive addresses.
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

  /// Encodes [program] as a SegWit address, e.g. `bc1q…` for Bitcoin mainnet.
  static String encodeSegwit({
    required String hrp,
    required int witnessVersion,
    required List<int> program,
  }) {
    final List<int> data = <int>[
      witnessVersion,
      ..._convertBits(program, 8, 5, true),
    ];
    final List<int> checksum = _createChecksum(hrp, data);
    final StringBuffer buffer = StringBuffer(hrp)..write('1');
    for (final int value in <int>[...data, ...checksum]) {
      buffer.write(_charset[value]);
    }
    return buffer.toString();
  }

  static List<int> _createChecksum(String hrp, List<int> data) {
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
    final int polymod = _polymod(values) ^ 1;
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
