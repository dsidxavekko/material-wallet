import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'wallet_entry.dart';

/// The non-secret side of the wallet list: names, which wallet is active and
/// the watch-only wallets themselves (they hold only public addresses).
///
/// Seed wallets are *not* described here beyond their names — their phrases and
/// ids live in the encrypted vault, which stays the single source of truth for
/// which seed wallets exist.
@immutable
class WalletBook {
  const WalletBook({
    this.activeId = primaryWalletId,
    this.names = const <String, String>{},
    this.watch = const <WalletEntry>[],
  });

  static const WalletBook empty = WalletBook();

  final String activeId;

  /// Display names by wallet id (seed and watch-only).
  final Map<String, String> names;

  final List<WalletEntry> watch;

  WalletBook copyWith({
    String? activeId,
    Map<String, String>? names,
    List<WalletEntry>? watch,
  }) =>
      WalletBook(
        activeId: activeId ?? this.activeId,
        names: names ?? this.names,
        watch: watch ?? this.watch,
      );

  String toJson() => jsonEncode(<String, Object>{
        'active': activeId,
        'names': names,
        'watch': <Object>[
          for (final WalletEntry w in watch)
            <String, Object>{'id': w.id, 'name': w.name, 'a': w.watched},
        ],
      });

  /// Reads a stored book; anything unreadable yields [empty] rather than an
  /// error, because the book is only a convenience layer over the vault.
  factory WalletBook.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return empty;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return empty;
      }
      final Object? names = decoded['names'];
      final Object? watch = decoded['watch'];
      return WalletBook(
        activeId:
            decoded['active'] is String ? decoded['active']! as String : primaryWalletId,
        names: names is Map
            ? <String, String>{
                for (final MapEntry<Object?, Object?> e in names.entries)
                  if (e.key is String && e.value is String)
                    e.key! as String: e.value! as String,
              }
            : const <String, String>{},
        watch: watch is List
            ? <WalletEntry>[
                for (final Object? w in watch)
                  if (_watchFrom(w) case final WalletEntry entry) entry,
              ]
            : const <WalletEntry>[],
      );
    } on FormatException {
      return empty;
    }
  }

  static WalletEntry? _watchFrom(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['a'] is! Map) {
      return null;
    }
    final Map<Object?, Object?> addresses = raw['a']! as Map<Object?, Object?>;
    final Map<String, String> watched = <String, String>{
      for (final MapEntry<Object?, Object?> e in addresses.entries)
        if (e.key is String && e.value is String) e.key! as String: e.value! as String,
    };
    if (watched.isEmpty) {
      return null;
    }
    return WalletEntry(
      id: raw['id']! as String,
      name: raw['name'] is String ? raw['name']! as String : 'Watch-only',
      kind: WalletKind.watchOnly,
      watched: watched,
    );
  }
}
