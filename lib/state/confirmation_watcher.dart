import 'dart:async';

import '../core/utils/app_log.dart';
import '../data/networks/chain_models.dart';
import '../data/networks/network_config.dart';
import '../data/notifications/notification_service.dart';
import '../data/wallet/wallet_storage.dart';
import 'settings_controller.dart';
import 'wallet_controller.dart';

/// Notifies the user when an outgoing transfer they were waiting on confirms.
///
/// It watches the live wallet state: a hash is remembered while its transfer is
/// pending and fires a system notification the moment it turns confirmed — even
/// if that happens after a restart, because the pending set is persisted.
///
/// This watcher covers the app being open and unlocked (WalletController polls a
/// pending transfer every 20–60 s and the watcher reacts to each reload). When
/// the app is closed or locked, `BackgroundChecker` (WorkManager, about every
/// 15 minutes, opt-in) reads the same persisted pending set, so a transfer is
/// announced by whichever of the two sees it confirm first — never twice, since
/// both remove the hash from that set.
///
/// ponytail: the background worker only knows addresses the app stored while it
/// was unlocked, and it cannot run more often than every 15 minutes (the system
/// may delay it further to save battery).
class ConfirmationWatcher {
  ConfirmationWatcher({
    required this.wallet,
    required this.settings,
    required this.notifications,
    WalletStorage storage = const WalletStorage(),
  }) : _storage = storage { // ignore: prefer_initializing_formals
    wallet.addListener(_onUpdate);
    unawaited(_load());
  }

  final WalletController wallet;
  final SettingsController settings;
  final NotificationService notifications;
  final WalletStorage _storage;

  /// Outgoing hashes still waiting to confirm (persisted across restarts).
  final Set<String> _watched = <String>{};

  Future<void> _load() async {
    try {
      _watched.addAll(await _storage.readWatchedTxs());
    } catch (error, stackTrace) {
      AppLog.warning('Could not read watched transfers', error, stackTrace);
    }
  }

  void _onUpdate() {
    final AccountSnapshot? snapshot = wallet.snapshot;
    // A followed address is someone else's money: its outgoing transfers are
    // not ones this person is waiting on.
    if (snapshot == null || wallet.identity.isWatchOnly) {
      return;
    }
    final NetworkConfig network = snapshot.network;
    final bool canNotify =
        settings.notificationsEnabled && notifications.enabled;

    bool changed = false;
    for (final ChainTransaction tx in snapshot.transactions) {
      if (tx.isIncoming) {
        continue;
      }

      if (!tx.confirmed && !tx.failed) {
        // Pending: keep watching it.
        if (_watched.add(tx.hash)) {
          changed = true;
        }
        continue;
      }

      // Confirmed: only announce if we were waiting on it. A freshly seen,
      // already-confirmed outgoing transfer is history (or was announced by the
      // in-app success screen) and must not be replayed.
      if (tx.confirmed && !tx.failed && _watched.remove(tx.hash)) {
        changed = true;
        if (canNotify) {
          unawaited(
            notifications.show(
              id: tx.hash.hashCode & 0x7fffffff,
              title: 'Transfer confirmed',
              body: '${tx.amountLabel(network)} is confirmed on ${network.name}.',
            ),
          );
        }
      }
    }

    if (changed) {
      unawaited(_persist());
    }
  }

  Future<void> _persist() async {
    try {
      await _storage.writeWatchedTxs(_watched.toList(growable: false));
    } catch (error, stackTrace) {
      AppLog.warning('Could not persist watched transfers', error, stackTrace);
    }
  }

  void dispose() {
    wallet.removeListener(_onUpdate);
  }
}
