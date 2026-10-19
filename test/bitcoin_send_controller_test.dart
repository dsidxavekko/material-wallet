import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/bitcoin_signer.dart';
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
  Future<bool> write(String value, {String reason = ''}) async {
    pin = value;
    return true;
  }

  @override
  Future<String?> read({String reason = ''}) async => pin;

  @override
  Future<void> clear() async => pin = null;

  @override
  Future<bool> get hasPin async => pin != null;
}

/// Stand-in for mempool.space: a fixed utxo set, counted broadcasts.
class _FakeChainApi extends ChainApi {
  _FakeChainApi({required this.utxos});

  List<BitcoinUtxo> utxos;
  int broadcasts = 0;

  @override
  Future<List<BitcoinUtxo>> fetchBitcoinUtxos(
    NetworkConfig network,
    String address,
  ) async =>
      utxos;

  @override
  Future<int> fetchBitcoinFeeRate(NetworkConfig network) async => 1;

  @override
  Future<String> broadcastBitcoinTransaction(
    NetworkConfig network,
    String rawTransaction,
  ) async {
    broadcasts++;
    return 'b' * 64;
  }

  @override
  Future<bool?> waitForBitcoinConfirmation(
    NetworkConfig network,
    String txid, {
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
  const String recipient = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
  const NetworkConfig network = NetworkCatalog.bitcoin;

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

  SendController controller(
    WalletIdentityController identity,
    _FakeChainApi api,
  ) =>
      SendController(
        identity: identity,
        network: network,
        address: identity.addressFor(network)!,
        chainApi: api,
      );

  List<BitcoinUtxo> oneUtxo(BigInt value) => <BitcoinUtxo>[
        BitcoinUtxo(txid: 'a' * 64, vout: 0, value: value),
      ];

  group('prepareBitcoin', () {
    test('selects a utxo and returns change for the entered amount', () async {
      final WalletIdentityController identity = await unlockedWallet();
      final _FakeChainApi api =
          _FakeChainApi(utxos: oneUtxo(BigInt.from(100000)));
      final SendController send = controller(identity, api);

      final BitcoinPlan? plan = await send.prepareBitcoin(
        to: recipient,
        amount: BigInt.from(50000),
        feeRate: 1,
      );

      expect(plan, isNotNull);
      expect(plan!.inputs, hasLength(1));
      expect(plan.fee, BigInt.from(BitcoinSigner.estimateVsize(1, 2)));
      expect(plan.change, BigInt.from(100000 - 50000) - plan.fee);
      expect(plan.outputs, hasLength(2));
      send.dispose();
    });

    test('returns null when the utxos cannot cover the amount', () async {
      final WalletIdentityController identity = await unlockedWallet();
      final _FakeChainApi api = _FakeChainApi(utxos: oneUtxo(BigInt.from(1000)));
      final SendController send = controller(identity, api);

      expect(
        await send.prepareBitcoin(
          to: recipient,
          amount: BigInt.from(1000),
          feeRate: 1,
        ),
        isNull,
      );
      send.dispose();
    });
  });

  group('sendBitcoin', () {
    test('signs and broadcasts a prepared plan', () async {
      final WalletIdentityController identity = await unlockedWallet();
      final _FakeChainApi api =
          _FakeChainApi(utxos: oneUtxo(BigInt.from(100000)));
      final SendController send = controller(identity, api);

      final BitcoinPlan plan = (await send.prepareBitcoin(
        to: recipient,
        amount: BigInt.from(50000),
        feeRate: 1,
      ))!;

      expect(await send.sendBitcoin(plan: plan), isTrue);
      expect(api.broadcasts, 1);
      expect(send.txHash, 'b' * 64);
      send.dispose();
    });

    test('refuses when a planned utxo has been spent', () async {
      final WalletIdentityController identity = await unlockedWallet();
      final _FakeChainApi api =
          _FakeChainApi(utxos: oneUtxo(BigInt.from(100000)));
      final SendController send = controller(identity, api);

      final BitcoinPlan plan = (await send.prepareBitcoin(
        to: recipient,
        amount: BigInt.from(50000),
        feeRate: 1,
      ))!;

      // The coin is gone by the time the user confirms.
      api.utxos = <BitcoinUtxo>[];

      expect(await send.sendBitcoin(plan: plan), isFalse);
      expect(api.broadcasts, 0, reason: 'nothing may reach the network');
      expect(send.error, contains('balance changed'));
      send.dispose();
    });
  });

  group('maxBitcoinAmount', () {
    test('keeps the fee back from the whole utxo set', () async {
      final WalletIdentityController identity = await unlockedWallet();
      final _FakeChainApi api =
          _FakeChainApi(utxos: oneUtxo(BigInt.from(100000)));
      final SendController send = controller(identity, api);

      expect(
        await send.maxBitcoinAmount(feeRate: 1),
        BigInt.from(100000 - BitcoinSigner.estimateVsize(1, 1)),
      );
      send.dispose();
    });
  });
}
