import 'dart:async';
import 'dart:convert';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/foundation.dart';

import '../core/utils/app_log.dart';
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

  /// Storage could not be read; the wallet is neither known to exist nor
  /// known to be absent, so the user must retry rather than be shown
  /// onboarding (which could overwrite a real wallet).
  failed,

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

  int _accountIndex = 0;
  int _accountCount = 1;

  /// Local names by account index; an account without one is "Account N".
  Map<int, String> _accountNames = <int, String>{};

  /// The BIP-44 account index currently active (0 = the default account).
  /// Non-secret; persisted so the wallet reopens where the user left it.
  int get accountIndex => _accountIndex;

  /// How many accounts exist. Accounts `0 .. accountCount - 1` are selectable.
  int get accountCount => _accountCount;

  /// Longest account name accepted; keeps the picker and Settings on one line.
  static const int maxAccountNameLength = 32;

  /// The name shown for account [index]: the user's own, or "Account N".
  String accountName(int index) => _accountNames[index] ?? 'Account ${index + 1}';

  /// Whether account [index] carries a user-chosen name.
  bool hasCustomAccountName(int index) => _accountNames.containsKey(index);

  /// Names account [index]. A blank [name] restores the default "Account N".
  ///
  /// The name is a local label only: nothing derives from it and it is never
  /// part of the vault.
  Future<void> renameAccount(int index, String name) async {
    if (index < 0 || index >= _accountCount) {
      return;
    }
    final String trimmed = name.trim();
    final Map<int, String> next = Map<int, String>.of(_accountNames);
    if (trimmed.isEmpty) {
      next.remove(index);
    } else {
      next[index] = trimmed.length > maxAccountNameLength
          ? trimmed.substring(0, maxAccountNameLength)
          : trimmed;
    }
    _accountNames = next;
    notifyListeners();
    await _storage.writeAccountNames(
      jsonEncode(<String, String>{
        for (final MapEntry<int, String> entry in next.entries)
          '${entry.key}': entry.value,
      }),
    );
  }

  static Map<int, String> _decodeAccountNames(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <int, String>{};
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <int, String>{};
      }
      return <int, String>{
        for (final MapEntry<Object?, Object?> entry in decoded.entries)
          if (int.tryParse('${entry.key}') != null &&
              entry.value is String &&
              (entry.value! as String).trim().isNotEmpty)
            int.parse('${entry.key}'): entry.value! as String,
      };
    } catch (_) {
      // A damaged name map is only labels; fall back to the defaults.
      return <int, String>{};
    }
  }

  UnlockThrottle _throttle = UnlockThrottle.none;

  /// Backoff applied to repeated wrong PIN entries. Persisted across restarts.
  UnlockThrottle get throttle => _throttle;

  /// `true` while a wrong-PIN penalty is in force.
  bool get unlockThrottled => _throttle.isThrottledAt(_clock());

  WalletStatus get status => _status;

  bool get loading => _status == WalletStatus.loading;

  bool get unlocked => _status == WalletStatus.unlocked;

  WalletAccount? get account => _account;

  List<String> get words => _account?.words ?? const <String>[];

  DateTime? get createdAt => _createdAt;

  String? get evmAddress => _evmAddress;

  /// Receive address for [network] on the active account, or `null` while
  /// locked or empty.
  String? addressFor(NetworkConfig network) {
    final Uint8List? seed = _seed;
    if (seed == null) {
      return null;
    }
    return switch (network.chain) {
      ChainKind.bitcoin => _bitcoinAddresses.putIfAbsent(
          network.hrp,
          () => AddressDeriver.bitcoinAddressFromSeed(
            seed,
            hrp: network.hrp,
            account: _accountIndex,
          ),
        ),
      ChainKind.evm => _evmAddress ??= AddressDeriver.ethereumAddressFromSeed(
          seed,
          account: _accountIndex,
        ),
      ChainKind.solana => _solanaAddress ??= AddressDeriver.solanaAddressFromSeed(
          seed,
          account: _accountIndex,
        ),
      ChainKind.aptos => _aptosAddress ??= AddressDeriver.aptosAddressFromSeed(
          seed,
          account: _accountIndex,
        ),
    };
  }

  /// The decrypted BIP-39 seed, or `null` while locked.
  ///
  /// Exposed for on-device transaction signing. Callers must treat the result
  /// as read-only and copy what they need — [lock] overwrites the original.
  Uint8List? get seed => _seed;

  // --- mnemonic helpers ----------------------------------------------------

  /// 128 bits → 12 words, 256 bits → 24 words.
  static String generateMnemonic({int strength = 128}) =>
      bip39.generateMnemonic(strength: strength);

  /// Validates a phrase against the BIP-39 wordlist and checksum.
  static bool isValidMnemonic(String value) =>
      bip39.validateMnemonic(normalize(value));

  /// Trims, lower-cases and collapses whitespace.
  static String normalize(String value) => AddressDeriver.normalize(value);

  // --- lifecycle -----------------------------------------------------------

  /// Reads the vault at app start. The wallet stays locked until [unlock].
  ///
  /// The biometric flag is refreshed in the background so a slow keystore can
  /// never delay the first frame.
  Future<void> load() async {
    try {
      _vault = await _storage.readVault();
      _createdAt = await _storage.readCreatedAt();
      _throttle = await _storage.readThrottle();
      _accountIndex = await _storage.readAccountIndex();
      _accountCount = await _storage.readAccountCount();
      _accountNames = _decodeAccountNames(await _storage.readAccountNames());
      if (_accountIndex >= _accountCount) {
        // The stored index can only go stale if storage was edited or partially
        // cleared; an out-of-range index would derive a dead account.
        _accountIndex = 0;
      }
      _status = _vault == null ? WalletStatus.empty : WalletStatus.locked;
    } catch (error, stackTrace) {
      // Never fall through to `empty`: if the keystore merely hiccuped, showing
      // onboarding would let the user overwrite a wallet that still exists.
      AppLog.error('Failed to read the wallet vault', error, stackTrace);
      _status = WalletStatus.failed;
    }
    notifyListeners();

    if (_status == WalletStatus.locked) {
      unawaited(_refreshBiometricState());
    }
  }

  Future<void> _refreshBiometricState() async {
    try {
      final bool enabled = await _pinStore.hasPin;
      if (enabled != _biometricsEnabled) {
        _biometricsEnabled = enabled;
        notifyListeners();
      }
    } catch (error, stackTrace) {
      AppLog.warning('Could not read the biometric flag', error, stackTrace);
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
    final String payload = await SeedVault.decryptAsync(vault, pin);
    await _adopt(
      WalletAccount.fromVaultPayload(payload, _createdAt ?? DateTime.now()),
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

  /// Encrypts the account's secrets with [pin] and stores them on the device.
  ///
  /// [passphrase] is the optional BIP-39 25th word. It is part of the secret:
  /// it is encrypted inside the same vault and changes every derived address.
  ///
  /// When [useBiometrics] is set (and the device supports it) the PIN is also
  /// kept in the platform keystore, so the wallet can be opened with a
  /// fingerprint afterwards.
  Future<void> createWallet({
    required String mnemonic,
    required String pin,
    String passphrase = '',
    bool useBiometrics = false,
  }) async {
    final String normalized = normalize(mnemonic);
    if (!bip39.validateMnemonic(normalized)) {
      throw const SeedVaultException(
        'That recovery phrase is not a valid BIP-39 phrase.',
      );
    }

    final WalletAccount account = WalletAccount(
      mnemonic: normalized,
      passphrase: passphrase,
      createdAt: DateTime.now(),
    );
    final String payload = await SeedVault.encryptAsync(
      account.toVaultPayload(),
      pin,
      rounds: _kdfRounds,
    );
    final DateTime now = account.createdAt;
    await _storage.writeVault(payload, now);

    _vault = payload;
    _createdAt = now;
    _throttle = UnlockThrottle.none;
    _accountIndex = 0;
    _accountCount = 1;
    // A different seed: the old seed's account names do not describe it.
    _accountNames = <int, String>{};
    await _storage.writeThrottle(_throttle);
    await _storage.writeAccountIndex(_accountIndex);
    await _storage.writeAccountCount(_accountCount);
    await _storage.writeAccountNames('{}');
    if (useBiometrics) {
      await enableBiometrics(pin);
    }
    await _adopt(account);
    notifyListeners();
  }

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

    final String payload = await SeedVault.encryptAsync(
      account.toVaultPayload(),
      newPin,
      rounds: _kdfRounds,
    );
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

  // --- accounts -------------------------------------------------------------

  /// Switches to the account at [index].
  ///
  /// Every chain derives a fresh set of addresses from the same seed, so the
  /// cached addresses are dropped and [WalletController] re-loads the balances
  /// for the new set.
  Future<void> selectAccount(int index) async {
    if (index < 0 || index >= _accountCount || index == _accountIndex) {
      return;
    }
    _accountIndex = index;
    _evmAddress = null;
    _solanaAddress = null;
    _aptosAddress = null;
    _bitcoinAddresses.clear();
    await _storage.writeAccountIndex(index);
    notifyListeners();
  }

  /// Reserves the next BIP-44 account index and switches to it.
  Future<void> addAccount() async {
    _accountCount += 1;
    await _storage.writeAccountCount(_accountCount);
    await selectAccount(_accountCount - 1);
  }

  /// Deletes the encrypted wallet from the device.
  Future<void> removeWallet() async {
    await _storage.clear();
    await _pinStore.clear();
    _vault = null;
    _createdAt = null;
    _biometricsEnabled = false;
    _throttle = UnlockThrottle.none;
    _accountIndex = 0;
    _accountCount = 1;
    _accountNames = <int, String>{};
    _clearMemory();
    _status = WalletStatus.empty;
    notifyListeners();
  }

  // --- biometrics -----------------------------------------------------------

  /// `true` when the device has biometric hardware with an enrolled print.
  Future<bool> canUseBiometrics() => _biometrics.isAvailable();

  /// Runs a biometric check and, on success, keeps [pin] in the keystore so
  /// later launches can be unlocked with a fingerprint.
  ///
  /// Returns `true` only when the PIN was actually stored. It returns `false`
  /// when the device has no biometrics or the user cancels the prompt, so
  /// callers can report the real outcome instead of assuming success.
  Future<bool> enableBiometrics(String pin) async {
    if (!await canUseBiometrics()) {
      return false;
    }
    if (!await _biometrics.authenticate(reason: 'Enable fingerprint unlock')) {
      return false;
    }
    await _pinStore.write(pin);
    _biometricsEnabled = true;
    notifyListeners();
    return true;
  }

  /// Forgets the stored PIN; the wallet goes back to PIN-only unlocking.
  Future<void> disableBiometrics() async {
    await _pinStore.clear();
    if (_biometricsEnabled) {
      _biometricsEnabled = false;
      notifyListeners();
    }
  }

  /// Re-authenticates for a sensitive action (e.g. revealing the recovery
  /// phrase) while the wallet is already unlocked.
  ///
  /// Returns `false` when biometrics is off or the prompt is cancelled, so the
  /// caller can fall back to asking for the PIN.
  Future<bool> confirmWithBiometrics({required String reason}) async {
    if (!_biometricsEnabled) {
      return false;
    }
    return _biometrics.authenticate(reason: reason);
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
    _seed = await AddressDeriver.seedFromMnemonicAsync(
      account.mnemonic,
      passphrase: account.passphrase,
    );
    _evmAddress = null;
    _solanaAddress = null;
    _aptosAddress = null;
    _bitcoinAddresses.clear();
    _status = WalletStatus.unlocked;
  }

  void _clearMemory() {
    // Overwrite the derived seed before dropping the reference so it does not
    // linger in the heap until the GC runs. (The mnemonic itself is an
    // immutable String and cannot be wiped the same way.)
    final Uint8List? seed = _seed;
    if (seed != null) {
      seed.fillRange(0, seed.length, 0);
    }
    _account = null;
    _seed = null;
    _evmAddress = null;
    _solanaAddress = null;
    _aptosAddress = null;
    _bitcoinAddresses.clear();
  }
}
