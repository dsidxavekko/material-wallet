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
/// ponytail: confirmation is only noticed while the app is running (or when it
/// next syncs). A transfer that confirms while the app is fully closed is
/// announced on the next launch, not in real time; a background worker would be
/// needed to do better.
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
    if (snapshot == null) {
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
