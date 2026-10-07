import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/notifications/notification_service.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/state/confirmation_watcher.dart';
import 'package:crypto_wallet/state/settings_controller.dart';
import 'package:crypto_wallet/state/wallet_controller.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage extends WalletStorage {
  _FakeStorage([List<String>? watched])
      : watched = watched ?? <String>[];

  final List<String> watched;

  @override
  Future<List<String>> readWatchedTxs() async => List<String>.from(watched);

  @override
  Future<void> writeWatchedTxs(List<String> hashes) async {
    watched
      ..clear()
      ..addAll(hashes);
  }
}

class _FakeNotifications extends NotificationService {
  final List<String> shown = <String>[];

  @override
  bool get enabled => true;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    shown.add(title);
  }
}

class _FakeSettings extends SettingsController {
  @override
  bool get notificationsEnabled => true;
}

class _FakeWallet extends WalletController {
  _FakeWallet({required super.identity, required super.settings});

  AccountSnapshot? _snapshot;

  @override
  AccountSnapshot? get snapshot => _snapshot;

  void emit(AccountSnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }
}

ChainTransaction _tx(String hash, {required bool confirmed}) => ChainTransaction(
      hash: hash,
      timestamp: DateTime(2026),
      amount: BigInt.from(-1),
      fee: BigInt.one,
      counterparty: '0xdef',
      isIncoming: false,
      confirmed: confirmed,
      nonce: 0,
    );

AccountSnapshot _snap(List<ChainTransaction> txs) => AccountSnapshot(
      network: NetworkCatalog.ethereum,
      address: '0xabc',
      balance: BigInt.zero,
      transactions: txs,
      chart: const <double>[],
      fetchedAt: DateTime(2026),
    );

void main() {
  late _FakeWallet wallet;

  setUp(() {
    wallet = _FakeWallet(
      identity: WalletIdentityController(),
      settings: _FakeSettings(),
    );
  });

  ConfirmationWatcher watch(
    _FakeStorage storage,
    _FakeNotifications notifications,
  ) =>
      ConfirmationWatcher(
        wallet: wallet,
        settings: _FakeSettings(),
        notifications: notifications,
        storage: storage,
      );

  test('notifies once when a watched transfer confirms', () async {
    final _FakeStorage storage = _FakeStorage();
    final _FakeNotifications notifications = _FakeNotifications();
    watch(storage, notifications);
    await Future<void>.delayed(Duration.zero);

    wallet.emit(_snap(<ChainTransaction>[_tx('0xa', confirmed: false)]));
    await Future<void>.delayed(Duration.zero);
    expect(notifications.shown, isEmpty);
    expect(storage.watched, contains('0xa'));

    wallet.emit(_snap(<ChainTransaction>[_tx('0xa', confirmed: true)]));
    await Future<void>.delayed(Duration.zero);
    expect(notifications.shown, hasLength(1));
    expect(storage.watched, isNot(contains('0xa')));
  });

  test('announces a transfer that was pending before a restart', () async {
    final _FakeStorage storage = _FakeStorage(<String>['0xb']);
    final _FakeNotifications notifications = _FakeNotifications();
    watch(storage, notifications);
    await Future<void>.delayed(Duration.zero);

    wallet.emit(_snap(<ChainTransaction>[_tx('0xb', confirmed: true)]));
    await Future<void>.delayed(Duration.zero);

    expect(notifications.shown, hasLength(1));
  });

  test('never replays historical confirmations', () async {
    final _FakeStorage storage = _FakeStorage();
    final _FakeNotifications notifications = _FakeNotifications();
    watch(storage, notifications);
    await Future<void>.delayed(Duration.zero);

    wallet.emit(_snap(<ChainTransaction>[_tx('0xc', confirmed: true)]));
    await Future<void>.delayed(Duration.zero);

    expect(notifications.shown, isEmpty);
  });
}
