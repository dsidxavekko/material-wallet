import 'dart:async';

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
import '../data/wallet/wallet_book.dart';
import '../data/wallet/wallet_entry.dart';
import '../data/wallet/wallet_storage.dart';
import '../data/wallet/watch_address.dart';

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

  /// Unlocked: mnemonic and seed are in memory. A device that only follows
  /// watch-only wallets has no vault and nothing to lock, so it sits here too.
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

  /// Everything the vault holds (all seed wallets); `null` while locked.
  WalletAccount? _vaultAccount;

  /// The active seed wallet on its own; `null` while locked or when a
  /// watch-only wallet is active.
  WalletAccount? _account;
  Uint8List? _seed;
  WalletBook _book = WalletBook.empty;
  String _activeId = primaryWalletId;
  String? _evmAddress;
  String? _solanaAddress;
  String? _aptosAddress;
  final Map<String, String> _bitcoinAddresses = <String, String>{};

  int _accountIndex = 0;
  int _accountCount = 1;

  /// The BIP-44 account index currently active (0 = the default account).
  /// Non-secret; persisted so the wallet reopens where the user left it.
  int get accountIndex => _accountIndex;

  /// How many accounts exist. Accounts `0 .. accountCount - 1` are selectable.
  int get accountCount => _accountCount;

  // --- wallets ---------------------------------------------------------------

  /// `true` when an encrypted vault (and so a password) exists on this device.
  bool get hasVault => _vault != null;

  /// Every wallet the user can switch to: the seed wallets (known once the
  /// vault is unlocked) followed by the watch-only ones.
  List<WalletEntry> get wallets {
    final WalletAccount? vault = _vaultAccount;
    final List<WalletAccount> seeds = vault?.seeds ?? const <WalletAccount>[];
    return <WalletEntry>[
      for (int i = 0; i < seeds.length; i++)
        WalletEntry(
          id: seeds[i].id,
          name: _book.names[seeds[i].id] ?? 'Wallet ${i + 1}',
          kind: WalletKind.seed,
        ),
      ..._book.watch.map(
        (WalletEntry w) => w.renamed(_book.names[w.id] ?? w.name),
      ),
    ];
  }

  String get activeWalletId => _activeId;

  /// The wallet currently shown, or `null` while locked or empty.
  WalletEntry? get activeWallet {
    for (final WalletEntry w in wallets) {
      if (w.id == _activeId) {
        return w;
      }
    }
    return null;
  }

  /// `true` when the active wallet only follows addresses.
  bool get isWatchOnly => activeWallet?.isWatchOnly ?? false;

  /// `true` when the active wallet holds keys, so a transfer can be signed.
  bool get canSign => unlocked && _seed != null && !isWatchOnly;

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
    if (_status == WalletStatus.unlocked) {
      final WalletEntry? watch = _activeWatch;
      if (watch != null) {
        return watch.watched[WatchAddresses.familyOf(network)];
      }
    }
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

  WalletEntry? get _activeWatch {
    for (final WalletEntry w in _book.watch) {
      if (w.id == _activeId) {
        return w;
      }
    }
    return null;
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
      _book = WalletBook.fromJson(await _storage.readWalletBook());
      _activeId = _book.activeId;
      await _loadAccountSettings();
      if (_vault != null) {
        _status = WalletStatus.locked;
      } else if (_book.watch.isNotEmpty) {
        // Nothing secret exists, so there is nothing to unlock: the watch-only
        // wallets open straight away.
        if (_activeWatch == null) {
          _activeId = _book.watch.first.id;
        }
        await _loadAccountSettings();
        _status = WalletStatus.unlocked;
      } else {
        _status = WalletStatus.empty;
      }
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

  /// Reads the account index and count of the active wallet.
  Future<void> _loadAccountSettings() async {
    _accountIndex = await _storage.readAccountIndex(walletId: _activeId);
    _accountCount = await _storage.readAccountCount(walletId: _activeId);
    if (_accountIndex >= _accountCount) {
      // The stored index can only go stale if storage was edited or partially
      // cleared; an out-of-range index would derive a dead account.
      _accountIndex = 0;
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
    if (_vault != null) {
      throw const SeedVaultException(
        'A wallet already exists; add the phrase as another wallet instead.',
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
    _activeId = account.id;
    _accountIndex = 0;
    _accountCount = 1;
    await _storage.writeThrottle(_throttle);
    await _storage.writeAccountIndex(_accountIndex, walletId: _activeId);
    await _storage.writeAccountCount(_accountCount, walletId: _activeId);
    await _saveBook(_book.copyWith(activeId: _activeId));
    if (useBiometrics) {
      await enableBiometrics(pin);
    }
    await _adopt(account);
    notifyListeners();
  }

  /// Adds another recovery phrase to the vault and switches to it.
  ///
  /// The vault is re-encrypted under the same [password], which is checked
  /// first: a wrong one leaves everything as it was. On a device that has no
  /// vault yet (only watch-only wallets) this behaves like [createWallet] and
  /// [password] becomes the device password.
  Future<void> addSeedWallet({
    required String mnemonic,
    required String password,
    String passphrase = '',
    String? name,
  }) async {
    if (_vault == null) {
      await createWallet(
        mnemonic: mnemonic,
        pin: password,
        passphrase: passphrase,
      );
      if (name != null && name.trim().isNotEmpty) {
        await renameWallet(_activeId, name);
      }
      return;
    }
    final WalletAccount? vault = _vaultAccount;
    if (vault == null) {
      throw const SeedVaultException('Unlock the wallet first.');
    }
    final String normalized = normalize(mnemonic);
    if (!bip39.validateMnemonic(normalized)) {
      throw const SeedVaultException(
        'That recovery phrase is not a valid BIP-39 phrase.',
      );
    }
    await SeedVault.decryptAsync(_vault!, password); // throws on a wrong password

    // The same phrase with the same passphrase is the same wallet: refuse it
    // instead of listing two identical rows.
    for (final WalletAccount seed in vault.seeds) {
      if (seed.mnemonic == normalized && seed.passphrase == passphrase) {
        throw const SeedVaultException('This wallet is already on the device.');
      }
    }

    final WalletAccount added = WalletAccount(
      mnemonic: normalized,
      passphrase: passphrase,
      createdAt: DateTime.now(),
      id: _newWalletId(),
    );
    final WalletAccount next = WalletAccount.fromSeeds(
      <WalletAccount>[...vault.seeds, added],
    );
    await _rewriteVault(next, password);
    _vaultAccount = next;
    final String label = (name ?? '').trim();
    if (label.isNotEmpty) {
      await _saveBook(_book.copyWith(
        names: <String, String>{..._book.names, added.id: _clip(label)},
      ));
    }
    await selectWallet(added.id);
  }

  String _newWalletId() {
    final Set<String> taken = <String>{
      ...?_vaultAccount?.seeds.map((WalletAccount s) => s.id),
      ..._book.watch.map((WalletEntry w) => w.id),
    };
    int n = taken.length + 1;
    while (taken.contains('w$n')) {
      n++;
    }
    return 'w$n';
  }

  Future<void> _rewriteVault(WalletAccount account, String password) async {
    final String payload = await SeedVault.encryptAsync(
      account.toVaultPayload(),
      password,
      rounds: _kdfRounds,
    );
    await _storage.writeVault(payload, _createdAt ?? DateTime.now());
    _vault = payload;
  }

  Future<void> _saveBook(WalletBook book) async {
    _book = book;
    await _storage.writeWalletBook(book.toJson());
  }

  /// Verifies [currentPin] and re-encrypts every phrase under [newPin].
  Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final String? vault = _vault;
    final WalletAccount? contents = _vaultAccount;
    if (vault == null || contents == null) {
      throw const SeedVaultException('Unlock the wallet first.');
    }
    await SeedVault.decryptAsync(vault, currentPin); // throws on a wrong PIN

    await _rewriteVault(contents, newPin);
    if (_biometricsEnabled) {
      // Keep the keystore copy in sync with the new PIN, otherwise the
      // fingerprint would replay the old one.
      await _pinStore.write(newPin);
    }
    notifyListeners();
  }

  /// Drops the decrypted material from memory but keeps the vault on disk.
  void lock() {
    if (_status != WalletStatus.unlocked || _vault == null) {
      // With no vault there is no password to come back with, so a device of
      // watch-only wallets stays open.
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
    if (isWatchOnly ||
        index < 0 ||
        index >= _accountCount ||
        index == _accountIndex) {
      return;
    }
    _accountIndex = index;
    _forgetAddresses();
    await _storage.writeAccountIndex(index, walletId: _activeId);
    notifyListeners();
  }

  /// Reserves the next BIP-44 account index and switches to it.
  Future<void> addAccount() async {
    if (isWatchOnly) {
      return;
    }
    _accountCount += 1;
    await _storage.writeAccountCount(_accountCount, walletId: _activeId);
    await selectAccount(_accountCount - 1);
  }

  // --- wallets --------------------------------------------------------------

  /// Switches to wallet [id] (a seed wallet of the unlocked vault, or a
  /// watch-only one).
  Future<void> selectWallet(String id) async {
    if (_status != WalletStatus.unlocked) {
      return;
    }
    final bool known = wallets.any((WalletEntry w) => w.id == id);
    if (!known || (id == _activeId && _loadedWalletId == id)) {
      return;
    }
    await _activate(id);
    await _saveBook(_book.copyWith(activeId: id));
    notifyListeners();
  }

  /// Follows [addresses] (family → address, see `WatchAddresses`) without any
  /// key. No password is needed because nothing secret is stored.
  Future<WalletEntry> addWatchWallet({
    required String name,
    required Map<String, String> addresses,
  }) async {
    if (addresses.isEmpty) {
      throw const SeedVaultException('Add at least one address to follow.');
    }
    if (_status == WalletStatus.locked) {
      throw const SeedVaultException('Unlock the wallet first.');
    }
    final String id = _newWalletId();
    final String label = _clip(name.trim());
    final WalletEntry entry = WalletEntry(
      id: id,
      name: label.isEmpty ? 'Watch-only' : label,
      kind: WalletKind.watchOnly,
      watched: Map<String, String>.unmodifiable(addresses),
    );
    final bool first = _status == WalletStatus.empty;
    await _saveBook(_book.copyWith(watch: <WalletEntry>[..._book.watch, entry]));
    if (first) {
      _status = WalletStatus.unlocked;
    }
    await selectWallet(id);
    if (first) {
      notifyListeners();
    }
    return entry;
  }

  /// Renames wallet [id]; an empty [name] restores the default.
  Future<void> renameWallet(String id, String name) async {
    final String clean = _clip(name.trim());
    final Map<String, String> names = Map<String, String>.of(_book.names);
    if (clean.isEmpty) {
      names.remove(id);
    } else {
      names[id] = clean;
    }
    await _saveBook(_book.copyWith(names: names));
    notifyListeners();
  }

  /// Removes watch-only wallet [id]. Nothing secret is involved, so no
  /// password is asked.
  Future<void> removeWatchWallet(String id) async {
    if (!_book.watch.any((WalletEntry w) => w.id == id)) {
      return;
    }
    final Map<String, String> names = Map<String, String>.of(_book.names)
      ..remove(id);
    await _saveBook(_book.copyWith(
      watch: <WalletEntry>[
        for (final WalletEntry w in _book.watch)
          if (w.id != id) w,
      ],
      names: names,
    ));
    await _storage.removeWalletSettings(id);
    if (_activeId == id) {
      await _fallBackFromRemoved();
    }
    notifyListeners();
  }

  /// Removes one recovery phrase from the vault, after checking [password].
  ///
  /// The last phrase cannot be removed this way — [removeWallet] erases the
  /// whole vault, with its own warning.
  Future<void> removeSeedWallet(String id, String password) async {
    final String? vault = _vault;
    final WalletAccount? contents = _vaultAccount;
    if (vault == null || contents == null) {
      throw const SeedVaultException('Unlock the wallet first.');
    }
    final List<WalletAccount> seeds = contents.seeds;
    if (!seeds.any((WalletAccount s) => s.id == id)) {
      return;
    }
    if (seeds.length == 1) {
      throw const SeedVaultException(
        'This is the only recovery phrase on the device. Erase the wallet '
        'from Settings instead.',
      );
    }
    await SeedVault.decryptAsync(vault, password); // throws on a wrong password

    final WalletAccount next = WalletAccount.fromSeeds(
      <WalletAccount>[
        for (final WalletAccount s in seeds)
          if (s.id != id) s,
      ],
    );
    await _rewriteVault(next, password);
    _vaultAccount = next;
    final Map<String, String> names = Map<String, String>.of(_book.names)
      ..remove(id);
    await _saveBook(_book.copyWith(names: names));
    await _storage.removeWalletSettings(id);
    if (_activeId == id) {
      await _fallBackFromRemoved();
    }
    notifyListeners();
  }

  Future<void> _fallBackFromRemoved() async {
    final List<WalletEntry> left = wallets;
    if (left.isEmpty) {
      _status = WalletStatus.empty;
      _clearMemory();
      return;
    }
    await _activate(left.first.id);
    await _saveBook(_book.copyWith(activeId: _activeId));
  }

  /// Deletes every recovery phrase and the password from the device.
  ///
  /// Watch-only wallets hold nothing secret, so they stay; the app then opens
  /// straight onto them. With none left it returns to onboarding.
  Future<void> removeWallet() async {
    final List<WalletEntry> watch = _book.watch;
    final Map<String, String> names = <String, String>{
      for (final WalletEntry w in watch)
        if (_book.names.containsKey(w.id)) w.id: _book.names[w.id]!,
    };
    await _storage.clear();
    await _pinStore.clear();
    _vault = null;
    _vaultAccount = null;
    _createdAt = null;
    _biometricsEnabled = false;
    _throttle = UnlockThrottle.none;
    _accountIndex = 0;
    _accountCount = 1;
    _clearMemory();
    if (watch.isEmpty) {
      _book = WalletBook.empty;
      _activeId = primaryWalletId;
      _status = WalletStatus.empty;
    } else {
      _activeId = watch.first.id;
      await _saveBook(
        WalletBook(activeId: _activeId, names: names, watch: watch),
      );
      await _loadAccountSettings();
      _status = WalletStatus.unlocked;
    }
    notifyListeners();
  }

  static String _clip(String name) =>
      name.length > 30 ? name.substring(0, 30) : name;

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

  /// Takes the decrypted vault into memory and opens the wallet that was
  /// active when the app was last used (the first one if that is gone).
  Future<void> _adopt(WalletAccount contents) async {
    _vaultAccount = contents;
    final bool known = wallets.any((WalletEntry w) => w.id == _activeId);
    await _activate(known ? _activeId : contents.id);
    _status = WalletStatus.unlocked;
  }

  /// The wallet whose account settings and seed are currently loaded.
  String? _loadedWalletId;

  /// Makes [id] the active wallet: loads its account settings and, for a seed
  /// wallet, derives its seed (the previous one is wiped first).
  Future<void> _activate(String id) async {
    _wipeSeed();
    _forgetAddresses();
    _activeId = id;
    _account = _vaultAccount?.seedWithId(id);
    final WalletAccount? seedWallet = _account;
    if (seedWallet != null) {
      _seed = await AddressDeriver.seedFromMnemonicAsync(
        seedWallet.mnemonic,
        passphrase: seedWallet.passphrase,
      );
    }
    await _loadAccountSettings();
    _loadedWalletId = id;
  }

  void _forgetAddresses() {
    _evmAddress = null;
    _solanaAddress = null;
    _aptosAddress = null;
    _bitcoinAddresses.clear();
  }

  void _wipeSeed() {
    // Overwrite the derived seed before dropping the reference so it does not
    // linger in the heap until the GC runs. (The mnemonic itself is an
    // immutable String and cannot be wiped the same way.)
    final Uint8List? seed = _seed;
    if (seed != null) {
      seed.fillRange(0, seed.length, 0);
    }
    _seed = null;
  }

  void _clearMemory() {
    _wipeSeed();
    _account = null;
    _vaultAccount = null;
    _loadedWalletId = null;
    _forgetAddresses();
  }
}
