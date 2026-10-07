import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/evm_signer.dart';
import 'package:crypto_wallet/data/wallet/secure_pin_store.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/state/send_controller.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the wallet vault.
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

/// In-memory stand-in for the platform keystore.
class _FakePinStore extends SecurePinStore {
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

/// Stand-in for the chain that reports a fixed balance and counts broadcasts.
class _FakeChainApi extends ChainApi {
  _FakeChainApi({required this.balance, this.tokenBalance});

  BigInt balance;

  /// Live `balanceOf` answer; `null` means the chain was not asked.
  BigInt? tokenBalance;
  int tokenReads = 0;
  int broadcasts = 0;

  @override
  Future<BigInt> fetchBalance(NetworkConfig network, String address) async =>
      balance;

  @override
  Future<BigInt> fetchTokenBalance({
    required NetworkConfig network,
    required String token,
    required String owner,
  }) async {
    tokenReads++;
    return tokenBalance ?? BigInt.zero;
  }

  @override
  Future<int> getTransactionCount(NetworkConfig network, String address) async =>
      0;

  @override
  Future<String> sendRawTransaction(
    NetworkConfig network,
    String rawTransaction,
  ) async {
    broadcasts++;
    return '0x${'ab' * 32}';
  }

  @override
  Future<bool?> waitForReceipt(
    NetworkConfig network,
    String hash, {
    int attempts = 12,
  }) async =>
      true;

  @override
  void dispose() {}
}

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';
  const String recipient = '0x3535353535353535353535353535353535353535';
  const NetworkConfig network = NetworkCatalog.sepolia;

  Future<WalletIdentityController> unlockedWallet() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final WalletIdentityController identity = WalletIdentityController(
      storage: _FakeWalletStorage(),
      pinStore: _FakePinStore(),
      kdfRounds: 1000,
    );
    await identity.load();
    await identity.createWallet(mnemonic: mnemonic, pin: pin);
    return identity;
  }

  Future<bool> attempt(
    WalletIdentityController identity,
    _FakeChainApi api,
    BigInt value,
  ) {
    final SendController controller = SendController(
      identity: identity,
      network: network,
      address: identity.addressFor(network)!,
      chainApi: api,
    );
    return controller.send(
      to: recipient,
      value: value,
      maxPriorityFeePerGas: BigInt.from(1000000000),
      maxFeePerGas: BigInt.from(30000000000),
      gasLimit: BigInt.from(21000),
    );
  }

  group('FeePreset', () {
    final BigInt tip = BigInt.from(1000000000); // 1 gwei
    final BigInt baseFee = BigInt.from(1000000000);

    test('scales the suggested tip', () {
      expect(FeePreset.slow.tipFor(tip), BigInt.from(500000000));
      expect(FeePreset.normal.tipFor(tip), tip);
      expect(FeePreset.fast.tipFor(tip), BigInt.from(2000000000));
    });

    test('never lets the slow tip reach zero', () {
      expect(FeePreset.slow.tipFor(BigInt.one), BigInt.one);
      expect(FeePreset.slow.tipFor(BigInt.zero), BigInt.one);
    });

    test('builds the cap as twice the base fee plus the tip', () {
      expect(FeePreset.normal.capFor(baseFee, tip), BigInt.from(3000000000));
      expect(FeePreset.fast.capFor(baseFee, tip), BigInt.from(4000000000));
    });
  });

  group('SendController balance guard', () {
    test('refuses to send when the live balance dropped below the total',
        () async {      final WalletIdentityController identity = await unlockedWallet();
      // 0.001 ether is above the live balance.
      final _FakeChainApi api = _FakeChainApi(balance: BigInt.from(100));

      expect(await attempt(identity, api, BigInt.from(1000)), isFalse);
      expect(api.broadcasts, 0, reason: 'nothing may reach the network');
    });

    test('broadcasts once the live balance covers amount plus fee', () async {
      final WalletIdentityController identity = await unlockedWallet();
      final _FakeChainApi api =
          _FakeChainApi(balance: BigInt.parse('1000000000000000000'));

      expect(await attempt(identity, api, BigInt.from(1000000000000)), isTrue);
      expect(api.broadcasts, 1);
    });
  });

  group('SendController token guard', () {
    const String tokenContract = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

    Future<bool> attemptTokenSend(
      WalletIdentityController identity,
      _FakeChainApi api,
      BigInt amount,
    ) {
      final SendController controller = SendController(
        identity: identity,
        network: network,
        address: identity.addressFor(network)!,
        chainApi: api,
      );
      return controller.send(
        to: tokenContract,
        value: BigInt.zero, // a token transfer moves no native value
        maxPriorityFeePerGas: BigInt.from(1000000000),
        maxFeePerGas: BigInt.from(30000000000),
        gasLimit: BigInt.from(60000),
        data: EvmSigner.erc20TransferData(to: recipient, amount: amount),
        tokenContract: tokenContract,
        tokenAmount: amount,
      );
    }

    test('refuses when the live token holding no longer covers the amount',
        () async {
      final WalletIdentityController identity = await unlockedWallet();
      // The native balance is ample; only the token holding is short. Without
      // the second check this transfer would sign and burn its gas.
      final _FakeChainApi api = _FakeChainApi(
        balance: BigInt.parse('1000000000000000000'),
        tokenBalance: BigInt.from(500),
      );

      expect(await attemptTokenSend(identity, api, BigInt.from(1000)), isFalse);
      expect(api.broadcasts, 0, reason: 'nothing may reach the network');
    });

    test('reports the drop instead of the generic native-balance message',
        () async {
      final WalletIdentityController identity = await unlockedWallet();
      final _FakeChainApi api = _FakeChainApi(
        balance: BigInt.parse('1000000000000000000'),
        tokenBalance: BigInt.from(1),
      );

      final SendController controller = SendController(
        identity: identity,
        network: network,
        address: identity.addressFor(network)!,
        chainApi: api,
      );
      await controller.send(
        to: tokenContract,
        value: BigInt.zero,
        maxPriorityFeePerGas: BigInt.from(1000000000),
        maxFeePerGas: BigInt.from(30000000000),
        gasLimit: BigInt.from(60000),
        data: EvmSigner.erc20TransferData(to: recipient, amount: BigInt.from(9)),
        tokenContract: tokenContract,
        tokenAmount: BigInt.from(9),
      );

      // The user must be able to tell *which* balance moved under them.
      expect(controller.error, contains('token balance dropped'));
    });

    test('broadcasts once the live token holding covers the amount', () async {
      final WalletIdentityController identity = await unlockedWallet();
      final _FakeChainApi api = _FakeChainApi(
        balance: BigInt.parse('1000000000000000000'),
        tokenBalance: BigInt.from(5000),
      );

      expect(await attemptTokenSend(identity, api, BigInt.from(1000)), isTrue);
      expect(api.broadcasts, 1);
    });

    test('a native send does not consult the token balance', () async {
      final WalletIdentityController identity = await unlockedWallet();
      final _FakeChainApi api = _FakeChainApi(
        balance: BigInt.parse('1000000000000000000'),
        tokenBalance: BigInt.zero,
      );

      expect(await attempt(identity, api, BigInt.from(1000)), isTrue);
      expect(api.tokenReads, 0);
    });
  });
}
