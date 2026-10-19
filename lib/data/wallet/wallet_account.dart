import 'dart:convert';

import 'wallet_entry.dart';

/// The secrets of a device: one or more BIP-39 recovery phrases.
///
/// The BIP-39 mnemonic and the optional passphrase (the "25th word") are
/// persisted — every address and key is derived from them on demand, so
/// nothing else needs to be stored.
///
/// The first phrase is the account itself; any further seed wallets ride along
/// in [others] and are encrypted in the same vault under the same password, so
/// one unlock opens all of them and switching wallet needs no second prompt.
class WalletAccount {
  const WalletAccount({
    required this.mnemonic,
    this.passphrase = '',
    required this.createdAt,
    this.id = primaryWalletId,
    this.others = const <WalletAccount>[],
  });

  /// Stable id of this seed wallet; the first wallet of an install is
  /// [primaryWalletId].
  final String id;

  /// The BIP-39 recovery phrase (12 or 24 lowercase words).
  final String mnemonic;

  /// The optional BIP-39 passphrase ("25th word"). `''` when the wallet does
  /// not use one; it never appears in [mnemonic] itself.
  final String passphrase;

  final DateTime createdAt;

  /// The other seed wallets in this vault (never nested: each has no [others]).
  final List<WalletAccount> others;

  List<String> get words => mnemonic.split(' ');

  bool get hasPassphrase => passphrase.isNotEmpty;

  /// This wallet on its own, without the vault's other phrases.
  WalletAccount get single => others.isEmpty
      ? this
      : WalletAccount(
          mnemonic: mnemonic,
          passphrase: passphrase,
          createdAt: createdAt,
          id: id,
        );

  /// Every seed wallet in the vault, in order.
  List<WalletAccount> get seeds => <WalletAccount>[single, ...others];

  /// The seed wallet with [walletId], or `null`.
  WalletAccount? seedWithId(String walletId) {
    for (final WalletAccount seed in seeds) {
      if (seed.id == walletId) {
        return seed;
      }
    }
    return null;
  }

  /// A vault holding [seeds] (at least one): the first becomes the account,
  /// the rest go to [others].
  static WalletAccount fromSeeds(List<WalletAccount> seeds) {
    final WalletAccount first = seeds.first;
    return WalletAccount(
      mnemonic: first.mnemonic,
      passphrase: first.passphrase,
      createdAt: first.createdAt,
      id: first.id,
      others: seeds.skip(1).map((WalletAccount s) => s.single).toList(),
    );
  }

  /// Serialises the secret material for the encrypted vault.
  ///
  /// A JSON envelope keeps the secrets self-describing:
  /// `{"m": "<phrase>", "p": "<passphrase>"}` for the first wallet, plus `i`
  /// (its id, when it is not the default) and `x` (the other seed wallets, each
  /// `{"i", "m", "p"}`). A vault with one wallet serialises exactly as it did
  /// before multiple wallets existed.
  String toVaultPayload() => jsonEncode(<String, Object>{
        'm': mnemonic,
        if (passphrase.isNotEmpty) 'p': passphrase,
        if (id != primaryWalletId) 'i': id,
        if (others.isNotEmpty)
          'x': <Object>[
            for (final WalletAccount o in others)
              <String, Object>{
                'i': o.id,
                'm': o.mnemonic,
                if (o.passphrase.isNotEmpty) 'p': o.passphrase,
              },
          ],
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
        final Object? id = decoded['i'];
        final Object? extra = decoded['x'];
        return WalletAccount(
          mnemonic: decoded['m']! as String,
          passphrase: passphrase is String ? passphrase : '',
          createdAt: createdAt,
          id: id is String && id.isNotEmpty ? id : primaryWalletId,
          others: <WalletAccount>[
            if (extra is List)
              for (final Object? item in extra)
                if (item is Map && item['m'] is String && item['i'] is String)
                  WalletAccount(
                    mnemonic: item['m']! as String,
                    passphrase: item['p'] is String ? item['p']! as String : '',
                    createdAt: createdAt,
                    id: item['i']! as String,
                  ),
          ],
        );
      }
    } on FormatException {
      // v1 payload — the whole string is the mnemonic.
    }
    return WalletAccount(mnemonic: payload, createdAt: createdAt);
  }
}
