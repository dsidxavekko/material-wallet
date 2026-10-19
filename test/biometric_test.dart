import 'package:crypto_wallet/data/wallet/secure_pin_store.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the hardware-bound store: the fingerprint prompt is
/// part of [write] and [read], exactly as on the device.
class _FakePinStore extends SecurePinStore {
  _FakePinStore({this.supported = true});

  bool supported;

  /// What the next fingerprint prompt does.
  bool fingerPasses = true;

  /// The key was reset (fingerprints changed).
  bool invalidated = false;

  int prompts = 0;
  String? pin;

  @override
  Future<bool> get isSupported async => supported;

  @override
  Future<bool> get hasPin async => pin != null;

  @override
  Future<bool> write(String value, {String reason = ''}) async {
    prompts++;
    if (!fingerPasses) {
      return false;
    }
    pin = value;
    return true;
  }

  @override
  Future<String?> read({String reason = ''}) async {
    prompts++;
    if (invalidated) {
      pin = null;
      throw const BoundSecretInvalidated();
    }
    return fingerPasses ? pin : null;
  }

  @override
  Future<void> clear() async => pin = null;

  @override
  Future<void> dropLegacy() async {}
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
    required _FakePinStore store,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final WalletIdentityController identity = WalletIdentityController(
      storage: _FakeWalletStorage(),
      pinStore: store,
      kdfRounds: 1000,
    );
    await identity.load();
    return identity;
  }

  group('biometric unlock', () {
    test('stores the PIN at creation and unlocks with a fingerprint',
        () async {
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity =
          await newWallet(store: store);

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
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity =
          await newWallet(store: store);

      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );
      identity.lock();

      store.fingerPasses = false;
      expect(await identity.unlockWithBiometrics(), isFalse);
      expect(identity.status, WalletStatus.locked);
    });

    test('is not enabled when the device has no biometrics', () async {
      final _FakePinStore store = _FakePinStore(supported: false);
      final WalletIdentityController identity =
          await newWallet(store: store);

      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );

      expect(identity.biometricsEnabled, isFalse);
      expect(store.pin, isNull);
      expect(store.prompts, 0);
    });

    test('enableBiometrics reports failure when the prompt is cancelled',
        () async {
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity =
          await newWallet(store: store);
      await identity.createWallet(mnemonic: mnemonic, pin: pin);

      store.fingerPasses = false;
      expect(await identity.enableBiometrics(pin), isFalse);
      expect(identity.biometricsEnabled, isFalse);
      expect(store.pin, isNull);
    });

    test('changing the PIN keeps the stored copy in sync', () async {
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity =
          await newWallet(store: store);

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
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity =
          await newWallet(store: store);

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
        store: _FakePinStore(),
      );
      await identity.createWallet(mnemonic: mnemonic, pin: pin);

      await expectLater(identity.verifyPin(pin), completes);
      await expectLater(identity.verifyPin('000000'), throwsA(anything));
    });

    test('confirmWithBiometrics passes when enabled and the prompt succeeds',
        () async {
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity = await newWallet(store: store);
      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );

      expect(
        await identity.confirmWithBiometrics(reason: 'Reveal phrase'),
        isTrue,
      );

      store.fingerPasses = false;
      expect(
        await identity.confirmWithBiometrics(reason: 'Reveal phrase'),
        isFalse,
      );
    });

    test('confirmWithBiometrics never authorises when disabled', () async {
      final WalletIdentityController identity = await newWallet(
        store: _FakePinStore(),
      );
      await identity.createWallet(mnemonic: mnemonic, pin: pin);

      expect(
        await identity.confirmWithBiometrics(reason: 'Reveal phrase'),
        isFalse,
      );
    });

    test('the password is only released by the fingerprint prompt', () async {
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity = await newWallet(store: store);
      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );
      identity.lock();
      final int before = store.prompts;

      expect(await identity.unlockWithBiometrics(), isTrue);
      // One read, one prompt: there is no second "gate" that could be skipped.
      expect(store.prompts, before + 1);
    });

    test('changed fingerprints switch the feature off and say so', () async {
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity = await newWallet(store: store);
      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );
      identity.lock();

      store.invalidated = true;
      expect(await identity.unlockWithBiometrics(), isFalse);
      expect(identity.status, WalletStatus.locked);
      expect(identity.biometricsEnabled, isFalse);
      expect(identity.biometricsReset, isTrue);
      expect(store.pin, isNull);

      // The password still opens the wallet, and turning the feature on again
      // clears the notice.
      await identity.unlock(pin);
      store.invalidated = false;
      expect(await identity.enableBiometrics(pin), isTrue);
      expect(identity.biometricsReset, isFalse);
    });

    test('a cancelled prompt leaves the feature on for next time', () async {
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity = await newWallet(store: store);
      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );
      identity.lock();

      store.fingerPasses = false;
      expect(await identity.unlockWithBiometrics(), isFalse);
      expect(identity.biometricsEnabled, isTrue);
      expect(identity.biometricsReset, isFalse);
    });

    test('a stored password that no longer opens the vault is dropped',
        () async {
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity = await newWallet(store: store);
      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );
      identity.lock();

      store.pin = 'a stale copy';
      expect(await identity.unlockWithBiometrics(), isFalse);
      expect(identity.biometricsEnabled, isFalse);
      expect(store.pin, isNull);
    });

    test('cancelling the prompt during a password change turns it off safely',
        () async {
      final _FakePinStore store = _FakePinStore();
      final WalletIdentityController identity = await newWallet(store: store);
      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );

      store.fingerPasses = false;
      final bool kept =
          await identity.changePin(currentPin: pin, newPin: 'another password');
      expect(kept, isFalse);
      expect(identity.biometricsEnabled, isFalse);
      // The old password must not stay behind where the fingerprint could
      // replay it.
      expect(store.pin, isNull);

      identity.lock();
      await identity.unlock('another password');
      expect(identity.unlocked, isTrue);
    });
  });
}
