import 'dart:async';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/foundation.dart';

import '../data/models/chain_kind.dart';
import '../data/networks/network_config.dart';
import '../data/wallet/address_deriver.dart';
import '../data/wallet/biometric_auth.dart';
import '../data/wallet/secure_pin_store.dart';
import '../data/wallet/seed_vault.dart';
import '../data/wallet/unlock_throttle.dart';
import '../data/wallet/wallet_account.dart';
import '../data/wallet/wallet_storage.dart';

/// Lifecycle of the on-device wallet.
enum WalletStatus {
  /// Reading the vault from storage.
  loading,

  /// No wallet yet — show onboarding.
  empty,

  /// A wallet exists but the PIN has not been entered yet.
  locked,

  /// Unlocked: mnemonic and seed are in memory.
  unlocked,
}

/// Owns the wallet that lives on this device.
///
/// The recovery phrase is stored **encrypted** (AES-256-GCM under a PBKDF2 key
/// derived from the user's PIN) and is only decrypted into memory after a
/// successful [unlock]. Addresses are then derived once per network and cached.
class WalletIdentityController extends ChangeNotifier {
  WalletIdentityController({
    this._storage = const WalletStorage(),
    BiometricAuth? biometrics,
    this._pinStore = const SecurePinStore(),
    int? kdfRounds,
    DateTime Function()? clock,
  })  : _biometrics = biometrics ?? BiometricAuth(),
        _kdfRounds = kdfRounds ?? SeedVault.iterations,
        _clock = clock ?? DateTime.now;

  final WalletStorage _storage;
  final BiometricAuth _biometrics;
  final SecurePinStore _pinStore;

  /// Source of "now", injectable so backoff tests need no real waiting.
  final DateTime Function() _clock;

  /// PBKDF2 rounds used when a new vault is created or re-encrypted. Exposed so
  /// tests can use a cheap value instead of the production [SeedVault.iterations].
  final int _kdfRounds;

  bool _biometricsEnabled = false;

  /// `true` when the PIN is kept in the platform keystore, so a fingerprint
  /// (or face) can unlock the wallet instead of typing it.
  bool get biometricsEnabled => _biometricsEnabled;

  WalletStatus _status = WalletStatus.loading;
  String? _vault;
  DateTime? _createdAt;
  WalletAccount? _account;
  Uint8List? _seed;
  String? _evmAddress;
  String? _solanaAddress;
  String? _aptosAddress;
  final Map<String, String> _bitcoinAddresses = <String, String>{};

  UnlockThrottle _throttle = UnlockThrottle.none;

  /// Backoff applied to repeated wrong PIN entries. Persisted across restarts.
  UnlockThrottle get throttle => _throttle;

  /// `true` while a wrong-PIN penalty is in force.
  bool get unlockThrottled => _throttle.isThrottledAt(_clock());

  WalletStatus get status => _status;

  bool get loading => _status == WalletStatus.loading;

  /// `true` when a wallet exists on the device, locked or not.
  bool get hasWallet =>
      _status == WalletStatus.locked || _status == WalletStatus.unlocked;

  bool get unlocked => _status == WalletStatus.unlocked;

  WalletAccount? get account => _account;

  List<String> get words => _account?.words ?? const <String>[];

  DateTime? get createdAt => _createdAt;

  String? get evmAddress => _evmAddress;

  /// The mainnet Bitcoin address (`bc1q…`).
  String? get bitcoinAddress => _bitcoinAddresses['bc'];

  /// Receive address for [network], or `null` while locked or empty.
  String? addressFor(NetworkConfig network) {
    final Uint8List? seed = _seed;
    if (seed == null) {
      return null;
    }
    return switch (network.chain) {
      ChainKind.bitcoin => _bitcoinAddresses.putIfAbsent(
          network.hrp,
          () => AddressDeriver.bitcoinAddressFromSeed(seed, hrp: network.hrp),
        ),
      ChainKind.evm =>
        _evmAddress ??= AddressDeriver.ethereumAddressFromSeed(seed),
      ChainKind.solana =>
        _solanaAddress ??= AddressDeriver.solanaAddressFromSeed(seed),
      ChainKind.aptos =>
        _aptosAddress ??= AddressDeriver.aptosAddressFromSeed(seed),
    };
  }

  // --- mnemonic helpers ----------------------------------------------------

  /// 128 bits → 12 words, 256 bits → 24 words.
  static String generateMnemonic({int strength = 128}) =>
      bip39.generateMnemonic(strength: strength);

  /// Validates a phrase against the BIP-39 wordlist and checksum.
  static bool isValidMnemonic(String value) =>
      bip39.validateMnemonic(normalize(value));

  /// Trims, lower-cases and collapses whitespace.
  static String normalize(String value) => value
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .join(' ');

  // --- lifecycle -----------------------------------------------------------

  /// Reads the vault at app start. The wallet stays locked until [unlock].
  ///
  /// The biometric flag is refreshed in the background so a slow keystore can
  /// never delay the first frame.
  Future<void> load() async {
    _vault = await _storage.readVault();
    _createdAt = await _storage.readCreatedAt();
    _throttle = await _storage.readThrottle();
    _status = _vault == null ? WalletStatus.empty : WalletStatus.locked;
    notifyListeners();

    if (_vault != null) {
      unawaited(_refreshBiometricState());
    }
  }

  Future<void> _refreshBiometricState() async {
    final bool enabled = await _pinStore.hasPin;
    if (enabled != _biometricsEnabled) {
      _biometricsEnabled = enabled;
      notifyListeners();
    }
  }

  /// Decrypts the stored phrase and derives the addresses.
  ///
  /// Throws [SeedVaultException] when the PIN is wrong, or while a wrong-PIN
  /// penalty from earlier attempts is still in force.
  Future<void> unlock(String pin) async {
    final DateTime now = _clock();
    if (_throttle.isThrottledAt(now)) {
      throw SeedVaultException(_throttle.retryHint(now));
    }
    try {
      await _decryptInto(pin);
    } on SeedVaultException {
      // Only a genuinely wrong PIN reaches here: a throttled call was rejected
      // above, so a lockout cannot feed on itself.
      _throttle = _throttle.recordFailure(now);
      await _storage.writeThrottle(_throttle);
      notifyListeners();
      rethrow;
    }
    await _clearThrottle();
  }

  /// Decrypts [pin] and adopts the resulting account. No throttle handling.
  Future<void> _decryptInto(String pin) async {
    final String? vault = _vault;
    if (vault == null) {
      throw const SeedVaultException('No wallet on this device.');
    }
    final String mnemonic = await SeedVault.decryptAsync(vault, pin);
    await _adopt(
      WalletAccount(
        mnemonic: mnemonic,
        createdAt: _createdAt ?? DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<void> _clearThrottle() async {
    if (_throttle.failedAttempts == 0 && _throttle.lockedUntil == null) {
      return;
    }
    _throttle = UnlockThrottle.none;
    await _storage.writeThrottle(_throttle);
  }

  /// Encrypts [mnemonic] with [pin] and stores it on the device.
  ///
  /// When [useBiometrics] is set (and the device supports it) the PIN is also
  /// kept in the platform keystore, so the wallet can be opened with a
  /// fingerprint afterwards.
  Future<void> createWallet({
    required String mnemonic,
    required String pin,
    bool useBiometrics = false,
  }) async {
    final String normalized = normalize(mnemonic);
    if (!bip39.validateMnemonic(normalized)) {
      throw const SeedVaultException(
        'That recovery phrase is not a valid BIP-39 phrase.',
      );
    }

    final String payload =
        await SeedVault.encryptAsync(normalized, pin, rounds: _kdfRounds);
    final DateTime now = DateTime.now();
    await _storage.writeVault(payload, now);

    _vault = payload;
    _createdAt = now;
    _throttle = UnlockThrottle.none;
    await _storage.writeThrottle(_throttle);
    if (useBiometrics) {
      await enableBiometrics(pin);
    }
    await _adopt(WalletAccount(mnemonic: normalized, createdAt: now));
    notifyListeners();
  }

  /// Alias that reads better when the phrase was typed by the user.
  Future<void> importWallet({
    required String mnemonic,
    required String pin,
  }) =>
      createWallet(mnemonic: mnemonic, pin: pin);

  /// Verifies [currentPin] and re-encrypts the phrase under [newPin].
  Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final String? vault = _vault;
    final WalletAccount? account = _account;
    if (vault == null || account == null) {
      throw const SeedVaultException('Unlock the wallet first.');
    }
    await SeedVault.decryptAsync(vault, currentPin); // throws on a wrong PIN

    final String payload =
        await SeedVault.encryptAsync(account.mnemonic, newPin, rounds: _kdfRounds);
    await _storage.writeVault(payload, _createdAt ?? DateTime.now());
    _vault = payload;
    if (_biometricsEnabled) {
      // Keep the keystore copy in sync with the new PIN, otherwise the
      // fingerprint would replay the old one.
      await _pinStore.write(newPin);
    }
    notifyListeners();
  }

  /// Drops the decrypted material from memory but keeps the vault on disk.
  void lock() {
    if (_status != WalletStatus.unlocked) {
      return;
    }
    _clearMemory();
    _status = WalletStatus.locked;
    notifyListeners();
  }

  /// Deletes the encrypted wallet from the device.
  Future<void> removeWallet() async {
    await _storage.clear();
    await _pinStore.clear();
    _vault = null;
    _createdAt = null;
    _biometricsEnabled = false;
    _throttle = UnlockThrottle.none;
    _clearMemory();
    _status = WalletStatus.empty;
    notifyListeners();
  }

  // --- biometrics -----------------------------------------------------------

  /// `true` when the device has biometric hardware with an enrolled print.
  Future<bool> canUseBiometrics() => _biometrics.isAvailable();

  /// Runs a biometric check and, on success, keeps [pin] in the keystore so
  /// later launches can be unlocked with a fingerprint.
  Future<void> enableBiometrics(String pin) async {
    if (!await canUseBiometrics()) {
      return;
    }
    if (!await _biometrics.authenticate(reason: 'Enable fingerprint unlock')) {
      return;
    }
    await _pinStore.write(pin);
    _biometricsEnabled = true;
    notifyListeners();
  }

  /// Forgets the stored PIN; the wallet goes back to PIN-only unlocking.
  Future<void> disableBiometrics() async {
    await _pinStore.clear();
    if (_biometricsEnabled) {
      _biometricsEnabled = false;
      notifyListeners();
    }
  }

  /// Unlocks using the fingerprint prompt plus the PIN from the keystore.
  ///
  /// Biometric success is its own authorisation factor, so it is not subject to
  /// the wrong-PIN backoff (a fingerprint cannot be guessed offline). A
  /// successful unlock clears any pending PIN penalty.
  ///
  /// Returns `false` (and leaves the wallet locked) when biometrics is off, the
  /// prompt is cancelled, or no PIN is stored.
  Future<bool> unlockWithBiometrics() async {
    if (!_biometricsEnabled) {
      return false;
    }
    if (!await _biometrics.authenticate(reason: 'Unlock Material Wallet')) {
      return false;
    }
    final String? pin = await _pinStore.read();
    if (pin == null) {
      return false;
    }
    await _decryptInto(pin);
    await _clearThrottle();
    return true;
  }

  /// Checks [pin] against the vault without changing any state.
  ///
  /// Throws [SeedVaultException] when the PIN is wrong.
  Future<void> verifyPin(String pin) async {
    final String? vault = _vault;
    if (vault == null) {
      throw const SeedVaultException('No wallet on this device.');
    }
    await SeedVault.decryptAsync(vault, pin);
  }

  Future<void> _adopt(WalletAccount account) async {
    _account = account;
    _seed = await AddressDeriver.seedFromMnemonicAsync(account.mnemonic);
    _evmAddress = null;
    _solanaAddress = null;
    _aptosAddress = null;
    _bitcoinAddresses.clear();
    _status = WalletStatus.unlocked;
  }

  void _clearMemory() {
    _account = null;
    _seed = null;
    _evmAddress = null;
    _solanaAddress = null;
    _aptosAddress = null;
    _bitcoinAddresses.clear();
  }
}
