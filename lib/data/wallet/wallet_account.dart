import 'dart:convert';

/// A wallet created or imported on this device.
///
/// The BIP-39 mnemonic and the optional passphrase (the "25th word") are
/// persisted — every address and key is derived from them on demand, so
/// nothing else needs to be stored.
class WalletAccount {
  const WalletAccount({
    required this.mnemonic,
    this.passphrase = '',
    required this.createdAt,
  });

  /// The BIP-39 recovery phrase (12 or 24 lowercase words).
  final String mnemonic;

  /// The optional BIP-39 passphrase ("25th word"). `''` when the wallet does
  /// not use one; it never appears in [mnemonic] itself.
  final String passphrase;

  final DateTime createdAt;

  List<String> get words => mnemonic.split(' ');

  bool get hasPassphrase => passphrase.isNotEmpty;

  /// Serialises the secret material for the encrypted vault.
  ///
  /// A JSON envelope keeps the two secrets self-describing:
  /// `{"m": "<phrase>", "p": "<passphrase>"}`.
  String toVaultPayload() => jsonEncode(<String, Object>{
        'm': mnemonic,
        if (passphrase.isNotEmpty) 'p': passphrase,
      });

  /// Rebuilds an account from a decrypted vault payload.
  ///
  /// Vaults written before passphrase existed (v1) store the bare mnemonic as
  /// the whole payload; the JSON envelope is only used when it parses *and*
  /// carries an `m` field — a BIP-39 phrase can never look like that, so the
  /// two formats cannot be confused.
  factory WalletAccount.fromVaultPayload(String payload, DateTime createdAt) {
    try {
      final Object? decoded = jsonDecode(payload);
      if (decoded is Map && decoded['m'] is String) {
        final Object? passphrase = decoded['p'];
        return WalletAccount(
          mnemonic: decoded['m']! as String,
          passphrase: passphrase is String ? passphrase : '',
          createdAt: createdAt,
        );
      }
    } on FormatException {
      // v1 payload — the whole string is the mnemonic.
    }
    return WalletAccount(mnemonic: payload, createdAt: createdAt);
  }
}
