import 'dart:async';

import '../core/utils/app_log.dart';
import '../data/background/background_targets.dart';
import '../data/networks/network_config.dart';
import '../data/wallet/wallet_entry.dart';
import '../data/wallet/wallet_storage.dart';
import '../data/wallet/watch_address.dart';
import 'wallet_identity_controller.dart';

/// Keeps the list of addresses the background worker may watch in step with the
/// wallet.
///
/// The worker has no seed, so the app hands it the addresses while the wallet
/// is unlocked: the active account of each seed wallet (remembered from the
/// last time that wallet was open) and every watch-only address. Wallets that
/// were removed are dropped. Public data only.
class BackgroundTargetsSync {
  BackgroundTargetsSync({
    required this.identity,
    this._storage = const WalletStorage(),
  }) {
    identity.addListener(_onChanged);
    _onChanged();
  }

  final WalletIdentityController identity;
  final WalletStorage _storage;

  String? _lastWritten;
  Future<void> _queue = Future<void>.value();

  void _onChanged() {
    // Serialised, because every change reads what the previous one wrote.
    _queue = _queue.then((_) => _sync()).catchError((Object error, StackTrace s) {
      AppLog.warning('Could not update background targets', error, s);
    });
  }

  Future<void> _sync() async {
    if (identity.status == WalletStatus.empty) {
      await _write(const <BackgroundTarget>[]);
      return;
    }
    if (identity.status != WalletStatus.unlocked) {
      return;
    }
    final List<WalletEntry> wallets = identity.wallets;
    final Set<String> alive = <String>{
      for (final WalletEntry w in wallets) w.id,
    };
    final List<BackgroundTarget> stored =
        BackgroundTarget.decode(await _storage.readBackgroundTargets());

    // Keep what was remembered for seed wallets that still exist but are not
    // the open one; a watch-only wallet's addresses are always known, so they
    // are rebuilt from the wallet itself.
    final String active = identity.activeWalletId;
    final Set<String> watchIds = <String>{
      for (final WalletEntry w in wallets)
        if (w.isWatchOnly) w.id,
    };
    final List<BackgroundTarget> next = <BackgroundTarget>[
      for (final BackgroundTarget t in stored)
        if (alive.contains(t.walletId) &&
            t.walletId != active &&
            !watchIds.contains(t.walletId))
          t,
    ];
    for (final WalletEntry wallet in wallets) {
      for (final NetworkConfig network in NetworkCatalog.all) {
        final String? address = wallet.isWatchOnly
            ? wallet.watched[WatchAddresses.familyOf(network)]
            : (wallet.id == active ? identity.addressFor(network) : null);
        if (address != null) {
          next.add(
            BackgroundTarget(
              walletId: wallet.id,
              walletName: wallet.name,
              networkId: network.id,
              address: address,
            ),
          );
        }
      }
    }
    await _write(next);
  }

  Future<void> _write(List<BackgroundTarget> targets) async {
    final String json = BackgroundTarget.encode(targets);
    if (json == _lastWritten) {
      return;
    }
    _lastWritten = json;
    await _storage.writeBackgroundTargets(json);
  }

  void dispose() {
    identity.removeListener(_onChanged);
  }
}
