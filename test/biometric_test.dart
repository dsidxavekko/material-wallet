import 'package:crypto_wallet/data/wallet/biometric_auth.dart';
import 'package:crypto_wallet/data/wallet/secure_pin_store.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the fingerprint prompt.
class _FakeBiometrics extends BiometricAuth {
  _FakeBiometrics({this.available = true});

  bool available;
  bool result = true;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    return result;
  }
}

/// In-memory stand-in for the platform keystore.
class _FakePinStore extends SecurePinStore {
  _FakePinStore();

  String? pin;

  @override
  Future<void> write(String value) async => pin = value;

  @override
  Future<String?> read() async => pin;

  @override
  Future<void> clear() async => pin = null;

  @override
  Future<bool> get hasPin async => pin != null;
}

/// In-memory stand-in for the platform keystore that holds the encrypted seed.
class _FakeWalletStorage extends WalletStorage {
  String? vault;

  @override
  Future<String?> readVault() async => vault;

  @override
  Future<void> writeVault(String payload, DateTime createdAt) async {
    vault = payload;
  }

  @override
  Future<void> clear() async {
    vault = null;
  }
}

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';

  Future<WalletIdentityController> newWallet({
    required _FakeBiometrics biometrics,
    required _FakePinStore store,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final WalletIdentityController identity = WalletIdentityController(
      storage: _FakeWalletStorage(),
      biometrics: biometrics,
      pinStore: store,
      kdfRounds: 1000,
    );
    await identity.load();
    return identity;
  }

  group('biometric unlock', () {
    test('stores the PIN at creation and unlocks with a fingerprint',
        () async {
      final _FakeBiometrics biometrics = _FakeBiometrics();
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity =
          await newWallet(biometrics: biometrics, store: store);

      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );

      expect(identity.biometricsEnabled, isTrue);
      expect(store.pin, pin);

      identity.lock();
      expect(identity.status, WalletStatus.locked);

      expect(await identity.unlockWithBiometrics(), isTrue);
      expect(identity.status, WalletStatus.unlocked);
      expect(identity.words.length, 12);
    });

    test('stays locked when the fingerprint is rejected', () async {
      final _FakeBiometrics biometrics = _FakeBiometrics();
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity =
          await newWallet(biometrics: biometrics, store: store);

      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );
      identity.lock();

      biometrics.result = false;
      expect(await identity.unlockWithBiometrics(), isFalse);
      expect(identity.status, WalletStatus.locked);
    });

    test('is not enabled when the device has no biometrics', () async {
      final _FakeBiometrics biometrics = _FakeBiometrics(available: false);
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity =
          await newWallet(biometrics: biometrics, store: store);

      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );

      expect(identity.biometricsEnabled, isFalse);
      expect(store.pin, isNull);
      expect(biometrics.prompts, 0);
    });

    test('changing the PIN keeps the stored copy in sync', () async {
      final _FakeBiometrics biometrics = _FakeBiometrics();
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity =
          await newWallet(biometrics: biometrics, store: store);

      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );

      await identity.changePin(currentPin: pin, newPin: '999999');
      expect(store.pin, '999999');

      identity.lock();
      expect(await identity.unlockWithBiometrics(), isTrue);
      expect(identity.status, WalletStatus.unlocked);
    });

    test('disabling forgets the stored PIN', () async {
      final _FakeBiometrics biometrics = _FakeBiometrics();
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity =
          await newWallet(biometrics: biometrics, store: store);

      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );
      await identity.disableBiometrics();

      expect(identity.biometricsEnabled, isFalse);
      expect(store.pin, isNull);
    });

    test('verifyPin accepts the right PIN and rejects a wrong one', () async {
      final WalletIdentityController identity = await newWallet(
        biometrics: _FakeBiometrics(),
        store: _FakePinStore(),
      );
      await identity.createWallet(mnemonic: mnemonic, pin: pin);

      await expectLater(identity.verifyPin(pin), completes);
      await expectLater(identity.verifyPin('000000'), throwsA(anything));
    });
  });
}
