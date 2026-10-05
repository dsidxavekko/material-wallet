import 'package:crypto_wallet/data/wallet/biometric_auth.dart';
import 'package:crypto_wallet/data/wallet/secure_pin_store.dart';
import 'package:crypto_wallet/data/wallet/seed_vault.dart';
import 'package:crypto_wallet/data/wallet/unlock_throttle.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the platform keystore that holds the encrypted seed.
class _FakeWalletStorage extends WalletStorage {
  _FakeWalletStorage({this.vault});

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

/// In-memory stand-in for the fingerprint prompt.
class _FakeBiometrics extends BiometricAuth {
  bool available = true;
  bool result = true;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async => result;
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

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';
  const int fastRounds = 1000;

  group('UnlockThrottle', () {
    final DateTime t0 = DateTime(2026, 1, 1, 12);

    test('the first mistakes are not penalised', () {
      UnlockThrottle throttle = UnlockThrottle.none;
      for (int i = 1; i <= 3; i++) {
        throttle = throttle.recordFailure(t0);
        expect(throttle.isThrottledAt(t0), isFalse, reason: 'failure $i');
      }
      expect(throttle.failedAttempts, 3);
      expect(throttle.lockedUntil, isNull);
    });

    test('penalties escalate and then cap', () {
      expect(UnlockThrottle.delayForAttempts(3), Duration.zero);
      expect(UnlockThrottle.delayForAttempts(4), const Duration(seconds: 15));
      expect(UnlockThrottle.delayForAttempts(5), const Duration(seconds: 60));
      expect(UnlockThrottle.delayForAttempts(6), const Duration(minutes: 5));
      expect(UnlockThrottle.delayForAttempts(7), const Duration(minutes: 15));
      expect(UnlockThrottle.delayForAttempts(99), const Duration(minutes: 15));
    });

    test('a penalty expires once enough time passes', () {
      UnlockThrottle throttle = UnlockThrottle.none;
      for (int i = 0; i < 4; i++) {
        throttle = throttle.recordFailure(t0);
      }
      expect(throttle.isThrottledAt(t0), isTrue);
      expect(
        throttle.isThrottledAt(t0.add(const Duration(seconds: 10))),
        isTrue,
      );
      expect(
        throttle.isThrottledAt(t0.add(const Duration(seconds: 16))),
        isFalse,
      );
    });

    test('clearing resets the counter', () {
      final UnlockThrottle throttle = UnlockThrottle.none.recordFailure(t0);
      expect(throttle.cleared().failedAttempts, 0);
      expect(throttle.cleared().isThrottledAt(t0), isFalse);
    });

    test('json round-trips the counter and deadline', () {
      UnlockThrottle throttle = UnlockThrottle.none;
      for (int i = 0; i < 4; i++) {
        throttle = throttle.recordFailure(t0);
      }
      final UnlockThrottle restored =
          UnlockThrottle.fromJson(throttle.toJson());
      expect(restored.failedAttempts, throttle.failedAttempts);
      expect(restored.lockedUntil, throttle.lockedUntil);
      expect(restored.isThrottledAt(t0), isTrue);
    });

    test('fromJson tolerates missing and corrupt data', () {
      expect(UnlockThrottle.fromJson(null).failedAttempts, 0);
      expect(UnlockThrottle.fromJson(<String, Object?>{}).failedAttempts, 0);
      final UnlockThrottle bad = UnlockThrottle.fromJson(<String, Object?>{
        'failedAttempts': -5,
        'lockedUntil': 'not-a-date',
      });
      expect(bad.failedAttempts, 0);
      expect(bad.lockedUntil, isNull);
      expect(bad.isThrottledAt(t0), isFalse);
    });

    test('retryHint counts down in seconds then minutes', () {
      UnlockThrottle short = UnlockThrottle.none;
      for (int i = 0; i < 4; i++) {
        short = short.recordFailure(t0);
      }
      expect(short.retryHint(t0), 'Try again in 15s');

      UnlockThrottle long = UnlockThrottle.none;
      for (int i = 0; i < 6; i++) {
        long = long.recordFailure(t0);
      }
      expect(long.retryHint(t0), 'Try again in 5 min 00s');
    });
  });

  group('PIN attempt throttling', () {
    // Every controller touches SharedPreferences (for the persisted counter),
    // so each test needs the in-memory plugin stand-in. Resetting it here also
    // guarantees the restart tests start from a clean slate.
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    Future<WalletIdentityController> lockedWallet(
      DateTime Function() clock, {
      _FakeWalletStorage? storage,
    }) async {
      final WalletIdentityController identity = WalletIdentityController(
        storage: storage ??
            _FakeWalletStorage(
              vault: SeedVault.encrypt(mnemonic, pin, rounds: fastRounds),
            ),
        clock: clock,
        kdfRounds: fastRounds,
      );
      await identity.load();
      return identity;
    }

    test('three mistakes are free, the fourth starts a penalty', () async {
      final DateTime now = DateTime(2026, 1, 1, 12);
      final WalletIdentityController identity =
          await lockedWallet(() => now);

      for (int i = 0; i < 3; i++) {
        await expectLater(
          identity.unlock('000000'),
          throwsA(isA<SeedVaultException>()),
        );
      }
      expect(identity.unlockThrottled, isFalse);

      await expectLater(
        identity.unlock('000000'),
        throwsA(isA<SeedVaultException>()),
      );
      expect(identity.unlockThrottled, isTrue);
      expect(identity.throttle.failedAttempts, 4);
    });

    test('an attempt during a penalty is rejected without counting', () async {
      final DateTime now = DateTime(2026, 1, 1, 12);
      final WalletIdentityController identity =
          await lockedWallet(() => now);

      for (int i = 0; i < 4; i++) {
        await expectLater(
          identity.unlock('000000'),
          throwsA(isA<SeedVaultException>()),
        );
      }
      final int before = identity.throttle.failedAttempts;

      // Even the correct PIN is refused while the penalty is in force.
      await expectLater(
        identity.unlock(pin),
        throwsA(isA<SeedVaultException>()),
      );
      expect(identity.throttle.failedAttempts, before);
      expect(identity.unlocked, isFalse);
    });

    test('a correct PIN clears the counter once the penalty lapses', () async {
      DateTime now = DateTime(2026, 1, 1, 12);
      final WalletIdentityController identity =
          await lockedWallet(() => now);

      for (int i = 0; i < 4; i++) {
        await expectLater(
          identity.unlock('000000'),
          throwsA(isA<SeedVaultException>()),
        );
      }

      now = now.add(const Duration(seconds: 16));
      expect(identity.unlockThrottled, isFalse);

      await identity.unlock(pin);
      expect(identity.unlocked, isTrue);
      expect(identity.throttle.failedAttempts, 0);
      expect(identity.throttle.lockedUntil, isNull);
    });

    test('the penalty survives a restart', () async {
      final DateTime now = DateTime(2026, 1, 1, 12);
      final _FakeWalletStorage storage = _FakeWalletStorage(
        vault: SeedVault.encrypt(mnemonic, pin, rounds: fastRounds),
      );

      final WalletIdentityController first = await lockedWallet(
        () => now,
        storage: storage,
      );
      for (int i = 0; i < 4; i++) {
        await expectLater(
          first.unlock('000000'),
          throwsA(isA<SeedVaultException>()),
        );
      }
      expect(first.unlockThrottled, isTrue);

      // A fresh controller (simulating a relaunch) must not reset the penalty.
      final WalletIdentityController second = await lockedWallet(
        () => now,
        storage: storage,
      );
      expect(second.unlockThrottled, isTrue);
      expect(second.throttle.failedAttempts, 4);
    });

    test('a successful unlock resets a persisted counter', () async {
      final DateTime now = DateTime(2026, 1, 1, 12);
      final _FakeWalletStorage storage = _FakeWalletStorage(
        vault: SeedVault.encrypt(mnemonic, pin, rounds: fastRounds),
      );
      final WalletIdentityController identity = await lockedWallet(
        () => now,
        storage: storage,
      );

      // One failure, then a correct PIN: the counter must not linger.
      await expectLater(
        identity.unlock('000000'),
        throwsA(isA<SeedVaultException>()),
      );
      await identity.unlock(pin);
      expect(identity.throttle.failedAttempts, 0);

      final WalletIdentityController reloaded = await lockedWallet(
        () => now,
        storage: storage,
      );
      expect(reloaded.throttle.failedAttempts, 0);
    });

    test('biometric unlock bypasses and clears a PIN penalty', () async {
      final DateTime now = DateTime(2026, 1, 1, 12);
      final WalletIdentityController identity = WalletIdentityController(
        storage: _FakeWalletStorage(),
        biometrics: _FakeBiometrics(),
        pinStore: _FakePinStore(),
        clock: () => now,
        kdfRounds: fastRounds,
      );
      await identity.load();
      await identity.createWallet(
        mnemonic: mnemonic,
        pin: pin,
        useBiometrics: true,
      );
      identity.lock();

      for (int i = 0; i < 4; i++) {
        await expectLater(
          identity.unlock('000000'),
          throwsA(isA<SeedVaultException>()),
        );
      }
      expect(identity.unlockThrottled, isTrue);

      final bool unlocked = await identity.unlockWithBiometrics();
      expect(unlocked, isTrue);
      expect(identity.unlocked, isTrue);
      expect(identity.unlockThrottled, isFalse);
      expect(identity.throttle.failedAttempts, 0);
    });
  });
}