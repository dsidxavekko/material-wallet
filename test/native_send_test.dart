import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto_wallet/core/crypto/base58.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/address_deriver.dart';
import 'package:crypto_wallet/data/wallet/aptos_signer.dart';
import 'package:crypto_wallet/data/wallet/secure_pin_store.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/state/send_controller.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _FakeChain extends ChainApi {
  final Map<String, BigInt> balances = <String, BigInt>{};
  BigInt rent = BigInt.from(890880);
  BigInt? messageFee = BigInt.from(5000);
  int broadcasts = 0;
  Uint8List? lastTransaction;

  // Aptos
  int? sequence = 7;
  bool simulationOk = true;
  int gasUsed = 9;
  int gasPrice = 100;
  Uint8List? lastSimulation;

  @override
  Future<BigInt> fetchBalance(NetworkConfig network, String address) async =>
      balances[address] ?? BigInt.zero;

  @override
  Future<Uint8List> fetchSolanaBlockhash(NetworkConfig network) async =>
      Uint8List.fromList(List<int>.generate(32, (int i) => i + 1));

  @override
  Future<BigInt> fetchSolanaRentExemptMinimum(NetworkConfig network) async =>
      rent;

  @override
  Future<BigInt?> fetchSolanaMessageFee(
    NetworkConfig network,
    Uint8List message,
  ) async =>
      messageFee;

  @override
  Future<String> sendSolanaTransaction(
    NetworkConfig network,
    Uint8List transaction,
  ) async {
    broadcasts++;
    lastTransaction = transaction;
    return 'solsig';
  }

  @override
  Future<bool?> waitForSolanaConfirmation(
    NetworkConfig network,
    String signature, {
    int attempts = 20,
  }) async =>
      true;

  @override
  Future<int?> fetchAptosSequenceNumber(
    NetworkConfig network,
    String address,
  ) async =>
      sequence;

  @override
  Future<({int chainId, int ledgerTimeSecs})> fetchAptosLedger(
    NetworkConfig network,
  ) async =>
      (chainId: 1, ledgerTimeSecs: 1700000000);

  @override
  Future<int> fetchAptosGasUnitPrice(NetworkConfig network) async => gasPrice;

  @override
  Future<({bool success, String vmStatus, int gasUsed})> simulateAptos(
    NetworkConfig network,
    Uint8List signedTransaction,
  ) async {
    lastSimulation = signedTransaction;
    return (
      success: simulationOk,
      vmStatus: simulationOk ? 'Executed successfully' : 'Move abort',
      gasUsed: gasUsed,
    );
  }

  @override
  Future<String> submitAptos(
    NetworkConfig network,
    Uint8List signedTransaction,
  ) async {
    broadcasts++;
    lastTransaction = signedTransaction;
    return '0xaptoshash';
  }

  @override
  Future<bool?> waitForAptosTransaction(
    NetworkConfig network,
    String hash, {
    int attempts = 20,
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
  const String solRecipient = 'BLeUXTx9thHGT7VJUtF9vHEmfMDgW1nnKZ9UVer2CoLX';
  final String aptRecipient = '0x${'11' * 32}';

  Future<WalletIdentityController> unlocked() async {
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

  BigInt sol(double v) => BigInt.from((v * 1e9).round());
  BigInt apt(double v) => BigInt.from((v * 1e8).round());

  group('Solana', () {
    const NetworkConfig network = NetworkCatalog.solana;

    Future<(SendController, _FakeChain, String)> setup() async {
      final WalletIdentityController identity = await unlocked();
      final String address = identity.addressFor(network)!;
      final _FakeChain chain = _FakeChain()
        ..balances[address] = sol(2)
        ..balances[solRecipient] = sol(1);
      return (
        SendController(
          identity: identity,
          network: network,
          address: address,
          chainApi: chain,
        ),
        chain,
        address,
      );
    }

    test('prices a transfer with the exact fee from the cluster', () async {
      final (SendController send, _FakeChain chain, _) = await setup();
      chain.messageFee = BigInt.from(5000);

      final quote =
          await send.prepareNative(to: solRecipient, amount: sol(0.5));

      expect(quote.problem, isNull);
      expect(quote.fee, BigInt.from(5000));
      send.dispose();
    });

    test('a first payment below the rent minimum to a new account is refused',
        () async {
      final (SendController send, _FakeChain chain, _) = await setup();
      chain.balances[solRecipient] = BigInt.zero;

      final quote =
          await send.prepareNative(to: solRecipient, amount: BigInt.from(1000));

      expect(quote.problem, contains('new'));
      expect(quote.problem, contains('0.00089088'));
      send.dispose();
    });

    test('a first payment at the rent minimum is fine', () async {
      final (SendController send, _FakeChain chain, _) = await setup();
      chain.balances[solRecipient] = BigInt.zero;

      final quote = await send.prepareNative(
        to: solRecipient,
        amount: BigInt.from(890880),
      );

      expect(quote.problem, isNull);
      send.dispose();
    });

    test('leaving the sender between zero and the minimum is refused', () async {
      final (SendController send, _FakeChain chain, String address) =
          await setup();
      // 2 SOL − 1.9999 SOL − 5 000 = 95 000 lamports left: stranded.
      chain.balances[address] = sol(2);
      final BigInt amount = sol(2) - BigInt.from(5000) - BigInt.from(95000);

      final quote = await send.prepareNative(to: solRecipient, amount: amount);

      expect(quote.problem, contains('below'));
      send.dispose();
    });

    test('sending everything (remainder zero) is allowed', () async {
      final (SendController send, _FakeChain chain, String address) =
          await setup();
      final BigInt amount = chain.balances[address]! - BigInt.from(5000);

      final quote = await send.prepareNative(to: solRecipient, amount: amount);

      expect(quote.problem, isNull);
      send.dispose();
    });

    test('signs a transaction whose signature verifies, and broadcasts once',
        () async {
      final (SendController send, _FakeChain chain, String address) =
          await setup();

      final bool ok = await send.sendNative(to: solRecipient, amount: sol(0.5));

      expect(ok, isTrue);
      expect(chain.broadcasts, 1);
      expect(send.txHash, 'solsig');

      final Uint8List tx = chain.lastTransaction!;
      expect(tx[0], 1); // one signature
      final Uint8List signature = Uint8List.sublistView(tx, 1, 65);
      final Uint8List message = Uint8List.sublistView(tx, 65);
      final ed.PublicKey publicKey =
          ed.PublicKey(Base58.decode(address)!);
      expect(ed.verify(publicKey, message, signature), isTrue);
      send.dispose();
    });

    test('refuses to sign when the balance dropped, and never broadcasts',
        () async {
      final (SendController send, _FakeChain chain, String address) =
          await setup();
      chain.balances[address] = sol(0.1);

      final bool ok = await send.sendNative(to: solRecipient, amount: sol(0.5));

      expect(ok, isFalse);
      expect(chain.broadcasts, 0);
      expect(send.error, contains('Nothing was sent'));
      send.dispose();
    });

    test('refuses a self-transfer', () async {
      final (SendController send, _FakeChain chain, String address) =
          await setup();

      final bool ok = await send.sendNative(to: address, amount: sol(0.5));

      expect(ok, isFalse);
      expect(chain.broadcasts, 0);
      send.dispose();
    });
  });

  group('Aptos', () {
    const NetworkConfig network = NetworkCatalog.aptos;

    Future<(SendController, _FakeChain, String, WalletIdentityController)>
        setup() async {
      final WalletIdentityController identity = await unlocked();
      final String address = identity.addressFor(network)!;
      final _FakeChain chain = _FakeChain()..balances[address] = apt(5);
      return (
        SendController(
          identity: identity,
          network: network,
          address: address,
          chainApi: chain,
        ),
        chain,
        address,
        identity,
      );
    }

    test('prices the transfer from a simulation', () async {
      final (SendController send, _FakeChain chain, _, _) = await setup();

      final quote =
          await send.prepareNative(to: aptRecipient, amount: apt(1));

      expect(quote.problem, isNull);
      expect(quote.fee, BigInt.from(9 * 100));
      expect(chain.lastSimulation, isNotNull);
      // The dry run carries a zero signature — nothing real is signed for it.
      expect(hex.encode(chain.lastSimulation!), endsWith('40${'00' * 64}'));
      send.dispose();
    });

    test('a failed simulation refuses before anything is signed', () async {
      final (SendController send, _FakeChain chain, _, _) = await setup();
      chain.simulationOk = false;

      final quote =
          await send.prepareNative(to: aptRecipient, amount: apt(1));
      expect(quote.problem, contains('would reject'));

      final bool ok = await send.sendNative(to: aptRecipient, amount: apt(1));
      expect(ok, isFalse);
      expect(chain.broadcasts, 0);
      send.dispose();
    });

    test('an unfunded account cannot send', () async {
      final (SendController send, _FakeChain chain, _, _) = await setup();
      chain.sequence = null;

      final quote =
          await send.prepareNative(to: aptRecipient, amount: apt(1));

      expect(quote.problem, contains('not been funded'));
      send.dispose();
    });

    test('submits exactly the transaction the signer produces', () async {
      final (SendController send, _FakeChain chain, String address, _) =
          await setup();

      final bool ok = await send.sendNative(to: aptRecipient, amount: apt(1));

      expect(ok, isTrue);
      expect(chain.broadcasts, 1);
      expect(send.txHash, '0xaptoshash');

      // Rebuild the same transaction independently and compare.
      final Uint8List seed = AddressDeriver.seedFromMnemonic(mnemonic);
      final keys = AddressDeriver.aptosKeyPairFromSeed(seed);
      final Uint8List raw = AptosSigner.rawTransfer(
        sender: AptosSigner.addressBytes(address),
        sequenceNumber: 7,
        to: AptosSigner.addressBytes(aptRecipient),
        amount: apt(1),
        maxGasAmount: AptosSigner.maxGasFloor, // max(2 × 9, floor)
        gasUnitPrice: 100,
        expirationTimestampSecs: 1700000600, // ledger time + 10 minutes
        chainId: 1,
      );
      expect(
        hex.encode(chain.lastTransaction!),
        hex.encode(
          AptosSigner.sign(privateSeed: keys.privateSeed, rawTransaction: raw),
        ),
      );
      send.dispose();
    });

    test('refuses when the balance cannot cover the gas reserve', () async {
      final (SendController send, _FakeChain chain, String address, _) =
          await setup();
      chain.balances[address] = BigInt.from(100000); // < floor × 100 reserve

      final bool ok =
          await send.sendNative(to: aptRecipient, amount: BigInt.from(1000));

      expect(ok, isFalse);
      expect(chain.broadcasts, 0);
      send.dispose();
    });
  });
}
