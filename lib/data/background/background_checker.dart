import 'dart:convert';

import '../../core/utils/app_log.dart';
import '../../l10n/messages.dart';
import '../networks/activity_merge.dart';
import '../networks/chain_api.dart';
import '../networks/chain_models.dart';
import '../networks/network_config.dart';
import '../wallet/snapshot_cache.dart';
import '../wallet/wallet_storage.dart';
import 'background_targets.dart';

/// Posts one notification; the real one talks to the OS, tests record calls.
/// [incoming] picks the channel (funds arriving vs. a transfer confirming).
typedef NotificationSink = Future<void> Function({
  required int id,
  required String title,
  required String body,
  required bool incoming,
});

/// One pass of the background worker: look at each remembered address and tell
/// the user about funds that arrived and transfers that confirmed.
///
/// It runs with **no seed and no password** — the wallet may be locked or the
/// app closed — so it only reads public chain data for the addresses the app
/// stored while it was unlocked. Nothing here can sign or send.
class BackgroundChecker {
  BackgroundChecker({
    required this.chainApi,
    required this.sink,
    this._storage = const WalletStorage(),
    this._cache = const SnapshotCache(),
  });

  final ChainApi chainApi;
  final NotificationSink sink;
  final WalletStorage _storage;
  final SnapshotCache _cache;

  /// Hashes remembered per address; older ones fall off so the stored set stays
  /// small.
  static const int seenLimit = 120;

  /// Runs one pass and returns how many notifications it posted.
  Future<int> run() async {
    final List<BackgroundTarget> targets =
        BackgroundTarget.decode(await _storage.readBackgroundTargets());
    if (targets.isEmpty) {
      return 0;
    }

    final Set<String> watched = (await _storage.readWatchedTxs()).toSet();
    final Map<String, List<String>> seen =
        _decodeSeen(await _storage.readBackgroundSeen());
    final Set<String> hiddenTokens = _decodeHidden(await _storage.readHiddenTokens());
    final bool privacy = await _storage.readHideBalances() ?? false;
    final bool severalWallets =
        targets.map((BackgroundTarget t) => t.walletId).toSet().length > 1;

    int posted = 0;
    final Set<String> done = <String>{};
    for (final BackgroundTarget target in targets) {
      // The same address can belong to two wallets; look at it once.
      if (!done.add(target.key)) {
        continue;
      }
      final NetworkConfig? network = _networkFor(target.networkId);
      if (network == null) {
        continue;
      }

      final List<ChainTransaction> rows;
      try {
        final ActivityPage page =
            await chainApi.fetchActivityPage(network, target.address);
        rows = mergeTokenTransfers(
          native: page.native,
          transfers: page.transfers,
          address: target.address,
        );
      } on ChainApiException catch (error) {
        // An unreachable node is not a reason to forget what was seen: try this
        // address again on the next pass.
        AppLog.warning('Background check of ${network.name} failed', error);
        continue;
      } catch (error, stackTrace) {
        AppLog.warning('Background check of ${network.name} broke', error, stackTrace);
        continue;
      }

      final List<String>? before = seen[target.key];
      final Set<String> known = (before ?? const <String>[]).toSet();
      // The first look at an address only learns its history: the user is not
      // told about every old transfer the moment they turn the feature on.
      final bool firstLook = before == null;
      final Set<String> heldTokens = firstLook
          ? const <String>{}
          : await _heldTokens(network, target.address, hiddenTokens);

      for (final ChainTransaction tx in rows) {
        if (tx.failed) {
          continue;
        }
        final String hash = tx.hash.toLowerCase();

        if (!tx.isIncoming) {
          if (tx.confirmed && watched.remove(tx.hash)) {
            posted++;
            await sink(
              id: _id(tx.hash),
              incoming: false,
              title: tr('Transfer confirmed'),
              body: tr(privacy
                  ? 'A transfer is confirmed on ${network.name}.'
                  : '${tx.amountLabel(network)} is confirmed on ${network.name}.'),
            );
          }
          continue;
        }

        if (firstLook || known.contains(hash)) {
          continue;
        }
        if (!_worthTelling(tx, heldTokens)) {
          continue;
        }
        posted++;
        final String where = severalWallets && target.walletName.isNotEmpty
            ? '${network.name} · ${target.walletName}'
            : network.name;
        await sink(
          id: _id(tx.hash),
          incoming: true,
          title: tr('Funds received'),
          body: tr(privacy
              ? 'New incoming transfer on $where.'
              : '${tx.amountLabel(network)} on $where.'),
        );
      }

      seen[target.key] = _remember(rows, before);
    }

    await _storage.writeWatchedTxs(watched.toList(growable: false));
    await _storage.writeBackgroundSeen(jsonEncode(seen));
    return posted;
  }

  /// A native receipt always counts. A token counts only when the user already
  /// holds it (as of the last time the app looked), so an unsolicited airdrop of
  /// a worthless token does not ping the phone — it still shows in Activity.
  static bool _worthTelling(ChainTransaction tx, Set<String> heldTokens) {
    if (tx.isToken) {
      return (tx.tokenAmount ?? BigInt.zero) > BigInt.zero &&
          heldTokens.contains(tx.tokenSymbol);
    }
    return tx.amount > BigInt.zero;
  }

  Future<Set<String>> _heldTokens(
    NetworkConfig network,
    String address,
    Set<String> hidden,
  ) async {
    try {
      final AccountSnapshot? cached = await _cache.read(network.id, address);
      return <String>{
        for (final TokenBalance t in cached?.tokens ?? const <TokenBalance>[])
          if (!hidden.contains('${network.id}:${t.contractAddress.toLowerCase()}'))
            t.symbol,
      };
    } catch (_) {
      return const <String>{};
    }
  }

  static List<String> _remember(List<ChainTransaction> rows, List<String>? before) {
    final List<String> next = <String>[];
    final Set<String> added = <String>{};
    for (final ChainTransaction tx in rows) {
      final String hash = tx.hash.toLowerCase();
      if (added.add(hash)) {
        next.add(hash);
      }
    }
    for (final String hash in before ?? const <String>[]) {
      if (added.add(hash)) {
        next.add(hash);
      }
    }
    return next.length > seenLimit ? next.sublist(0, seenLimit) : next;
  }

  static NetworkConfig? _networkFor(String id) {
    for (final NetworkConfig n in NetworkCatalog.all) {
      if (n.id == id) {
        return n;
      }
    }
    return null;
  }

  static int _id(String hash) => hash.hashCode & 0x7fffffff;

  static Map<String, List<String>> _decodeSeen(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <String, List<String>>{};
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, List<String>>{};
      }
      return <String, List<String>>{
        for (final MapEntry<Object?, Object?> e in decoded.entries)
          if (e.key is String && e.value is List)
            e.key! as String: <String>[
              for (final Object? h in e.value! as List)
                if (h is String) h,
            ],
      };
    } on FormatException {
      return <String, List<String>>{};
    }
  }

  static Set<String> _decodeHidden(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String>{};
    }
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is List
          ? <String>{for (final Object? e in decoded) if (e is String) e}
          : const <String>{};
    } on FormatException {
      return const <String>{};
    }
  }
}
