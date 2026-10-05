import 'dart:typed_data';

/// Minimal [RLP](https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/)
/// encoder — the serialisation format every legacy EVM transaction is built
/// from.
///
/// RLP has exactly two item types:
/// * **bytes** — prefixed with `0x80 + len` (a single byte below `0xb8`), or
///   `0xb7 + lenOfLen + len` when the payload reaches 56 bytes.
/// * **list** — the concatenated encoding of its items, prefixed with
///   `0xc0 + len` or `0xf7 + lenOfLen + len`.
///
/// Encodes big-endian, leading-zero-free integers; a zero is the empty string.
class Rlp {
  const Rlp._();

  static const int _byteStart = 0x80;
  static const int _shortListStart = 0xc0;

  /// RLP-encodes a list of already-encoded items.
  static Uint8List encodeList(List<Uint8List> items) {
    final BytesBuilder builder = BytesBuilder();
    for (final Uint8List item in items) {
      builder.add(item);
    }
    return _withLength(builder.takeBytes(), _shortListStart);
  }

  /// RLP-encodes a byte string. An empty input becomes the empty byte string
  /// `0x80`, not a list — this distinction is load-bearing for transactions.
  ///
  /// A single byte below `0x80` is its own encoding. Skipping that rule yields
  /// non-canonical output: every node rejects such a transaction, because the
  /// signature commits to the bytes as sent.
  static Uint8List encodeBytes(Uint8List value) {
    if (value.length == 1 && value[0] < _byteStart) {
      return Uint8List.fromList(value);
    }
    return _withLength(value, _byteStart);
  }

  /// RLP-encodes a non-negative integer as its minimal big-endian bytes.
  static Uint8List encodeInt(BigInt value) =>
      encodeBytes(value == BigInt.zero ? Uint8List(0) : _bigEndian(value));

  /// Encodes an integer that may be negative, as RLP does for chain ids in
  /// pre-EIP-155 payloads. Never needed by the EIP-155 path kept in
  /// [evm_signer]; provided so a future pre-EIP-155 signer stays correct.
  static Uint8List encodeSignedInt(BigInt value) =>
      value.isNegative ? encodeBytes(_bigEndian(value)) : encodeInt(value);

  /// Minimal big-endian representation: no leading zero bytes.
  static Uint8List _bigEndian(BigInt value) {
    final BigInt unsigned = value.isNegative ? -value : value;
    final int length = (unsigned.bitLength + 7) ~/ 8;
    final Uint8List out = Uint8List(length);
    BigInt remaining = unsigned;
    for (int i = length - 1; i >= 0; i--) {
      out[i] = (remaining & BigInt.from(0xff)).toInt();
      remaining = remaining >> 8;
    }
    return out;
  }

  /// Prefixes [payload] with its RLP length header.
  ///
  /// [base] is `0x80` for byte strings and `0xc0` for lists; the long form adds
  /// `0xb7` to it and encodes the length itself.
  static Uint8List _withLength(Uint8List payload, int base) {
    final int length = payload.length;
    if (length <= 55) {
      final Uint8List out = Uint8List(1 + length)
        ..[0] = base + length;
      out.setRange(1, 1 + length, payload);
      return out;
    }

    final Uint8List lengthBytes = _bigEndian(BigInt.from(length));
    final Uint8List out = Uint8List(1 + lengthBytes.length + length)
      ..[0] = base + 55 + lengthBytes.length;
    out.setRange(1, 1 + lengthBytes.length, lengthBytes);
    out.setRange(1 + lengthBytes.length, out.length, payload);
    return out;
  }
}