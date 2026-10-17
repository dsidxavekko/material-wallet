import 'dart:convert';

import '../networks/chain_models.dart';
import 'wallet_storage.dart';

/// Persists the last successful [AccountSnapshot] per network **and address**.
///
/// The data is public (balances and public transactions), so it lives in
/// `shared_preferences` next to the other non-secret preferences. It exists so
/// the app can show the last known balance immediately on launch and while
/// offline, instead of an empty loading card.
///
/// The address is part of the key because one device can hold several accounts
/// (BIP-44 indexes): a cache entry written for account 0 must never be read
/// back for account 1.
class SnapshotCache {
  const SnapshotCache({this._storage = const WalletStorage()});

  final WalletStorage _storage;

  static String _key(String networkId, String address) =>
      '$networkId|$address';

  /// The cached snapshot for ([networkId], [address]), or `null` when
  /// absent/corrupt.
  Future<AccountSnapshot?> read(String networkId, String address) async {
    final String? raw = await _storage.readCache(_key(networkId, address));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return AccountSnapshot.fromJson(decoded.cast<String, Object?>());
    } on FormatException {
      return null;
    }
  }

  Future<void> write(AccountSnapshot snapshot) async {
    await _storage.writeCache(
      _key(snapshot.network.id, snapshot.address),
      jsonEncode(snapshot.toJson()),
    );
  }
}
