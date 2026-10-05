import 'package:crypto_wallet/core/utils/formatters.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/seed_vault.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/state/settings_controller.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage whose keystore read can be made to fail on demand.
class _FlakyStorage extends WalletStorage {
  _FlakyStorage({this.vault});

  String? vault;
  bool failReads = false;

  @override
  Future<String?> readVault() async {
    if (failReads) {
      throw StateError('keystore unavailable');
    }
    return vault;
  }

  @override
  Future<void> writeVault(String payload, DateTime createdAt) async {
    vault = payload;
  }

  @override
  Future<void> clear() async {
    vault = null;
  }
}

/// Storage whose preferences always fail, to exercise the fallback path.
class _BrokenPrefs extends WalletStorage {
  @override
  Future<String?> readNetworkId() async => throw StateError('no prefs');
}

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';

  group('wallet load resilience', () {
    test('a storage failure is not mistaken for "no wallet"', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final _FlakyStorage storage = _FlakyStorage()..failReads = true;
      final WalletIdentityController identity =
          WalletIdentityController(storage: storage);

      await identity.load();

      // Crucially not `empty`: onboarding would let the user overwrite a real
      // wallet just because the keystore hiccuped.
      expect(identity.status, WalletStatus.failed);
      expect(identity.hasWallet, isFalse);
    });

    test('retrying after the storage recovers reaches the lock screen',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final _FlakyStorage storage = _FlakyStorage()..failReads = true;
      final WalletIdentityController identity =
          WalletIdentityController(storage: storage);
      await identity.load();
      expect(identity.status, WalletStatus.failed);

      storage
        ..failReads = false
        ..vault = SeedVault.encrypt(mnemonic, pin, rounds: 1000);
      await identity.load();

      expect(identity.status, WalletStatus.locked);
    });
  });

  group('settings load resilience', () {
    test('falls back to defaults instead of blocking startup', () async {
      final SettingsController settings =
          SettingsController(storage: _BrokenPrefs());

      await settings.load();

      expect(settings.network.id, NetworkCatalog.bitcoin.id);
      expect(settings.currency, AppCurrency.usd);
      expect(settings.autoLockEnabled, isTrue);
    });
  });

  group('ChainApiException taxonomy', () {
    test('a 5xx is retryable and tagged as HTTP', () async {
      final ChainApi api = ChainApi(
        client: MockClient((_) async => http.Response('boom', 503)),
      );

      Object? thrown;
      try {
        await api.fetchBalance(NetworkCatalog.bitcoin, 'bc1qexample');
      } on ChainApiException catch (error) {
        thrown = error;
      }

      expect(thrown, isA<ChainApiException>());
      final ChainApiException error = thrown! as ChainApiException;
      expect(error.code, ChainApiErrorCode.http);
      expect(error.retryable, isTrue);
    });

    test('an unparseable body is not retryable', () async {
      final ChainApi api = ChainApi(
        client: MockClient((_) async => http.Response('not json', 200)),
      );

      Object? thrown;
      try {
        await api.fetchBalance(NetworkCatalog.bitcoin, 'bc1qexample');
      } on ChainApiException catch (error) {
        thrown = error;
      }

      expect(thrown, isA<ChainApiException>());
      final ChainApiException error = thrown! as ChainApiException;
      expect(error.code, ChainApiErrorCode.parse);
      expect(error.retryable, isFalse);
    });
  });
}
