import 'package:flutter/foundation.dart';

/// Id of the first seed wallet. It is also the id every pre-multi-wallet
/// install already is, so its storage keys stay exactly as they were.
const String primaryWalletId = 'main';

enum WalletKind {
  /// Holds a recovery phrase in the encrypted vault; can sign.
  seed,

  /// Follows public addresses only; holds no secret and can never sign.
  watchOnly,
}

/// One wallet the user can switch to.
@immutable
class WalletEntry {
  const WalletEntry({
    required this.id,
    required this.name,
    required this.kind,
    this.watched = const <String, String>{},
  });

  final String id;
  final String name;
  final WalletKind kind;

  /// Watch-only addresses by family (see `WatchAddresses`); empty for a seed
  /// wallet, whose addresses are derived.
  final Map<String, String> watched;

  bool get isWatchOnly => kind == WalletKind.watchOnly;

  WalletEntry renamed(String next) =>
      WalletEntry(id: id, name: next, kind: kind, watched: watched);
}
