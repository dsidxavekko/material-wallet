import 'dart:convert';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

import '../../core/crypto/hashing.dart';

/// Thrown when an Aptos transfer cannot be built or signed.
class AptosSigningException implements Exception {
  const AptosSigningException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Builds and signs an APT transfer (`0x1::aptos_account::transfer`) as a BCS
/// `SignedTransaction`.
///
/// `aptos_account::transfer` (unlike `coin::transfer`) creates the recipient
/// account if it does not exist, so a first payment to a fresh address works.
/// Pinned by a vector generated with the official `aptos-sdk`.
class AptosSigner {
  const AptosSigner._();

  /// Smallest `max_gas_amount` the wallet signs. The node refuses anything
  /// under its intrinsic minimum with
  /// `MAX_GAS_UNITS_BELOW_MIN_TRANSACTION_GAS_UNITS`: 5 210 units on testnet
  /// (live probe, 2026-10-19; 2 000 was refused). Mainnet was not probed, so the
  /// floor leaves a wide margin; only gas actually used is charged.
  static const int maxGasFloor = 10000;

  /// Domain separator mixed into everything that is signed:
  /// `sha3_256("APTOS::RawTransaction")`.
  static final Uint8List _rawTransactionPrefix = Hashing.sha3_256(
    Uint8List.fromList(utf8.encode('APTOS::RawTransaction')),
  );

  /// ULEB128, BCS's length encoding.
  static Uint8List uleb128(int value) {
    final List<int> out = <int>[];
    int rest = value;
    do {
      int byte = rest & 0x7f;
      rest >>= 7;
      if (rest != 0) {
        byte |= 0x80;
      }
      out.add(byte);
    } while (rest != 0);
    return Uint8List.fromList(out);
  }

  static Uint8List _u64(BigInt value) {
    if (value.isNegative || value >= (BigInt.one << 64)) {
      throw const AptosSigningException('Amount out of range.');
    }
    final Uint8List out = Uint8List(8);
    for (int i = 0; i < 8; i++) {
      out[i] = ((value >> (8 * i)) & BigInt.from(0xff)).toInt();
    }
    return out;
  }

  /// A 32-byte account address from `0x…` hex (shorter forms such as `0x1` are
  /// left-padded, as Aptos does).
  static Uint8List addressBytes(String address) {
    String body = address.trim().toLowerCase();
    if (body.startsWith('0x')) {
      body = body.substring(2);
    }
    if (body.isEmpty || body.length > 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(body)) {
      throw const AptosSigningException('Invalid Aptos address.');
    }
    body = body.padLeft(64, '0');
    return Uint8List.fromList(<int>[
      for (int i = 0; i < 64; i += 2) int.parse(body.substring(i, i + 2), radix: 16),
    ]);
  }

  /// BCS `RawTransaction` for sending [amount] octas to [to].
  static Uint8List rawTransfer({
    required Uint8List sender,
    required int sequenceNumber,
    required Uint8List to,
    required BigInt amount,
    required int maxGasAmount,
    required int gasUnitPrice,
    required int expirationTimestampSecs,
    required int chainId,
  }) {
    _checkTransfer(sender, to, amount, chainId);
    return _rawEntry(
      sender: sender,
      sequenceNumber: sequenceNumber,
      module: 'aptos_account',
      function: 'transfer',
      typeArguments: const <List<int>>[],
      arguments: <List<int>>[to, _u64(amount)],
      maxGasAmount: maxGasAmount,
      gasUnitPrice: gasUnitPrice,
      expirationTimestampSecs: expirationTimestampSecs,
      chainId: chainId,
    );
  }

  /// `true` when [assetType] names a *fungible asset* (a metadata object
  /// address, `0x…`), `false` when it is a legacy coin type (`0xaddr::mod::Name`).
  static bool isFungibleAsset(String assetType) => !assetType.contains('::');

  /// BCS `RawTransaction` for sending [amount] of a token other than APT.
  ///
  /// * a **fungible asset** ([assetType] is its metadata object address) is
  ///   moved with `0x1::primary_fungible_store::transfer<0x1::fungible_asset::Metadata>
  ///   (metadata, to, amount)`;
  /// * a **legacy coin** ([assetType] is a `0xaddr::module::Name` type) with
  ///   `0x1::aptos_account::transfer_coins<CoinType>(to, amount)`.
  ///
  /// Both create the recipient's store when it does not exist yet. Pinned by
  /// vectors from the official `aptos-sdk`.
  static Uint8List rawTokenTransfer({
    required Uint8List sender,
    required int sequenceNumber,
    required String assetType,
    required Uint8List to,
    required BigInt amount,
    required int maxGasAmount,
    required int gasUnitPrice,
    required int expirationTimestampSecs,
    required int chainId,
  }) {
    _checkTransfer(sender, to, amount, chainId);
    if (isFungibleAsset(assetType)) {
      final Uint8List metadata = addressBytes(assetType);
      return _rawEntry(
        sender: sender,
        sequenceNumber: sequenceNumber,
        module: 'primary_fungible_store',
        function: 'transfer',
        typeArguments: <List<int>>[
          structTag(Uint8List.fromList(<int>[...Uint8List(31), 1]),
              'fungible_asset', 'Metadata'),
        ],
        arguments: <List<int>>[metadata, to, _u64(amount)],
        maxGasAmount: maxGasAmount,
        gasUnitPrice: gasUnitPrice,
        expirationTimestampSecs: expirationTimestampSecs,
        chainId: chainId,
      );
    }
    final List<String> parts = assetType.split('::');
    if (parts.length != 3 ||
        parts.any((String p) => p.isEmpty) ||
        assetType.contains('<') ||
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(parts[1]) ||
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(parts[2])) {
      throw const AptosSigningException('Unsupported token type.');
    }
    return _rawEntry(
      sender: sender,
      sequenceNumber: sequenceNumber,
      module: 'aptos_account',
      function: 'transfer_coins',
      typeArguments: <List<int>>[
        structTag(addressBytes(parts[0]), parts[1], parts[2]),
      ],
      arguments: <List<int>>[to, _u64(amount)],
      maxGasAmount: maxGasAmount,
      gasUnitPrice: gasUnitPrice,
      expirationTimestampSecs: expirationTimestampSecs,
      chainId: chainId,
    );
  }

  /// BCS `TypeTag::Struct` for `address::module::name` (no type parameters).
  static List<int> structTag(Uint8List address, String module, String name) {
    final List<int> m = utf8.encode(module);
    final List<int> n = utf8.encode(name);
    return <int>[
      7, // TypeTag::Struct
      ...address,
      ...uleb128(m.length), ...m,
      ...uleb128(n.length), ...n,
      0, // no type parameters
    ];
  }

  static void _checkTransfer(
    Uint8List sender,
    Uint8List to,
    BigInt amount,
    int chainId,
  ) {
    if (sender.length != 32 || to.length != 32) {
      throw const AptosSigningException('Malformed address.');
    }
    if (amount <= BigInt.zero) {
      throw const AptosSigningException('Invalid amount.');
    }
    if (chainId < 0 || chainId > 255) {
      throw const AptosSigningException('Invalid chain id.');
    }
  }

  /// A `RawTransaction` calling `0x1::[module]::[function]`. Each argument is
  /// given as its BCS bytes and wrapped in the length prefix entry functions
  /// expect.
  static Uint8List _rawEntry({
    required Uint8List sender,
    required int sequenceNumber,
    required String module,
    required String function,
    required List<List<int>> typeArguments,
    required List<List<int>> arguments,
    required int maxGasAmount,
    required int gasUnitPrice,
    required int expirationTimestampSecs,
    required int chainId,
  }) {
    final List<int> moduleName = utf8.encode(module);
    final List<int> functionName = utf8.encode(function);
    return Uint8List.fromList(<int>[
      ...sender,
      ..._u64(BigInt.from(sequenceNumber)),
      2, // TransactionPayload::EntryFunction
      ...Uint8List(31), 1, // module address 0x1
      ...uleb128(moduleName.length), ...moduleName,
      ...uleb128(functionName.length), ...functionName,
      ...uleb128(typeArguments.length),
      for (final List<int> t in typeArguments) ...t,
      ...uleb128(arguments.length),
      for (final List<int> a in arguments) ...<int>[...uleb128(a.length), ...a],
      ..._u64(BigInt.from(maxGasAmount)),
      ..._u64(BigInt.from(gasUnitPrice)),
      ..._u64(BigInt.from(expirationTimestampSecs)),
      chainId,
    ]);
  }

  /// The bytes that are actually signed.
  static Uint8List signingMessage(Uint8List rawTransaction) =>
      Uint8List.fromList(<int>[..._rawTransactionPrefix, ...rawTransaction]);

  /// `SignedTransaction`: the raw transaction plus an ed25519 authenticator
  /// (`0x00 ‖ len ‖ publicKey ‖ len ‖ signature`).
  static Uint8List signedTransaction({
    required Uint8List rawTransaction,
    required Uint8List publicKey,
    required Uint8List signature,
  }) =>
      Uint8List.fromList(<int>[
        ...rawTransaction,
        0, // TransactionAuthenticator::Ed25519
        ...uleb128(publicKey.length), ...publicKey,
        ...uleb128(signature.length), ...signature,
      ]);

  /// Signs [rawTransaction] with the ed25519 [privateSeed].
  static Uint8List sign({
    required Uint8List privateSeed,
    required Uint8List rawTransaction,
  }) {
    final ed.PrivateKey key = ed.newKeyFromSeed(privateSeed);
    final Uint8List publicKey = Uint8List.fromList(ed.public(key).bytes);
    final Uint8List signature = ed.sign(key, signingMessage(rawTransaction));
    return signedTransaction(
      rawTransaction: rawTransaction,
      publicKey: publicKey,
      signature: signature,
    );
  }

  /// A signed transaction carrying an all-zero signature, which is what the
  /// `/transactions/simulate` endpoint expects (it rejects a real signature).
  static Uint8List simulationTransaction({
    required Uint8List rawTransaction,
    required Uint8List publicKey,
  }) =>
      signedTransaction(
        rawTransaction: rawTransaction,
        publicKey: publicKey,
        signature: Uint8List(64),
      );
}
