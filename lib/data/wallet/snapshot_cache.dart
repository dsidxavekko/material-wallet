import 'dart:convert';

import '../networks/chain_models.dart';
import 'wallet_storage.dart';

/// Persists the last successful [AccountSnapshot] per network.
///
/// The data is public (balances and public transactions), so it lives in
/// `shared_preferences` next to the other non-secret preferences. It exists so
/// the app can show the last known balance immediately on launch and while
/// offline, instead of an empty loading card.
class SnapshotCache {
  const SnapshotCache({this._storage = const WalletStorage()});

  final WalletStorage _storage;

  /// The cached snapshot for [networkId], or `null` when absent/corrupt.
  Future<AccountSnapshot?> read(String networkId) async {
    final String? raw = await _storage.readCache(networkId);
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
      snapshot.network.id,
      jsonEncode(snapshot.toJson()),
    );
  }
}
