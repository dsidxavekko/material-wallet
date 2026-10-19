import 'dart:typed_data';

import 'package:crypto_wallet/core/crypto/base58.dart';
import 'package:crypto_wallet/data/networks/chain_api.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/address_deriver.dart';
import 'package:crypto_wallet/data/wallet/secure_pin_store.dart';
import 'package:crypto_wallet/data/wallet/spl_token_signer.dart';
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
  @override
  Future<bool> write(String value, {String reason = ''}) async => true;

  @override
  Future<String?> read({String reason = ''}) async => null;

  @override
  Future<void> clear() async {}

  @override
  Future<bool> get hasPin async => false;
}

/// A cluster with one mint, the sender's token accounts and a recipient.
class _SplChain extends ChainApi {
  _SplChain({required this.sender, required this.recipient, required this.mint});

  final String sender;
  final String recipient;
  final String mint;

  SplTokenProgram program = SplTokenProgram.token;
  bool mintKnown = true;
  int mintDecimals = 6;

  List<({String address, BigInt amount})> senderAccounts =
      <({String address, BigInt amount})>[];

  /// What exists at an address, by address (`null` = no account).
  final Map<String, ({String? mint, String? owner, SplTokenProgram? program})>
      accounts = <String, ({String? mint, String? owner, SplTokenProgram? program})>{};

  BigInt solBalance = BigInt.from(2000000000);
  BigInt messageFee = BigInt.from(5000);
  BigInt rentMinimum = BigInt.from(890880);
  BigInt newAccountRent = BigInt.from(2039280);

  Object? unsignedSimulationError;
  Object? signedSimulationError;

  int broadcasts = 0;
  Uint8List? lastTransaction;
  final List<bool> simulationChecks = <bool>[];

  @override
  Future<({SplTokenProgram program, int decimals})?> fetchSolanaMint(
    NetworkConfig network,
    String mint,
  ) async =>
      mintKnown ? (program: program, decimals: mintDecimals) : null;

  @override
  Future<List<({String address, BigInt amount})>> fetchSolanaTokenAccounts(
    NetworkConfig network,
    String owner,
    String mint,
  ) async =>
      List<({String address, BigInt amount})>.of(senderAccounts)
        ..sort((a, b) => b.amount.compareTo(a.amount));

  @override
  Future<({String? mint, String? owner, SplTokenProgram? program})?>
      fetchSolanaTokenAccountState(NetworkConfig network, String address) async =>
          accounts[address];

  @override
  Future<BigInt> fetchBalance(NetworkConfig network, String address) async =>
      solBalance;

  @override
  Future<Uint8List> fetchSolanaBlockhash(NetworkConfig network) async =>
      Uint8List.fromList(List<int>.generate(32, (int i) => i + 1));

  @override
  Future<BigInt> fetchSolanaRentExemptMinimum(NetworkConfig network) async =>
      rentMinimum;

  @override
  Future<BigInt?> fetchSolanaMessageFee(
    NetworkConfig network,
    Uint8List message,
  ) async =>
      messageFee;

  @override
  Future<({Object? error, List<BigInt?> lamports})> simulateSolanaTransaction(
    NetworkConfig network,
    Uint8List transaction, {
    List<String> watch = const <String>[],
    bool verifySignature = true,
  }) async {
    simulationChecks.add(verifySignature);
    lastTransaction = transaction;
    return (
      error: verifySignature ? signedSimulationError : unsignedSimulationError,
      lamports: <BigInt?>[for (final _ in watch) newAccountRent],
    );
  }

  @override
  Future<String> sendSolanaTransaction(
    NetworkConfig network,
    Uint8List transaction,
  ) async {
    broadcasts++;
    lastTransaction = transaction;
    return 'splsig';
  }

  @override
  Future<bool?> waitForSolanaConfirmation(
    NetworkConfig network,
    String signature, {
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
  const NetworkConfig network = NetworkCatalog.solana;
  const String usdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
  const String recipient = 'BLeUXTx9thHGT7VJUtF9vHEmfMDgW1nnKZ9UVer2CoLX';
  const String senderTokenAccount = 'hkcktF2Akp3vj8pbBVJuxJfk5m41i4t4TSVLx2VoNHT';

  final TokenBalance token = TokenBalance(
    symbol: 'USDC',
    name: 'USD Coin',
    decimals: 6,
    balance: BigInt.from(5000000),
    contractAddress: usdc,
  );

  String recipientAta(SplTokenProgram program) => Base58.encode(
        SplTokenSigner.associatedTokenAddress(
          owner: Base58.decode(recipient)!,
          mint: Base58.decode(usdc)!,
          program: program,
        ),
      );

  Future<(SendController, _SplChain, WalletIdentityController, String)> setup({
    bool watchOnly = false,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final WalletIdentityController identity = WalletIdentityController(
      storage: _FakeWalletStorage(),
      pinStore: _FakePinStore(),
      kdfRounds: 1000,
    );
    await identity.load();
    await identity.createWallet(mnemonic: mnemonic, pin: pin);
    final String address = identity.addressFor(network)!;
    final _SplChain chain = _SplChain(sender: address, recipient: recipient, mint: usdc)
      ..senderAccounts = <({String address, BigInt amount})>[
        (address: senderTokenAccount, amount: BigInt.from(5000000)),
      ];
    return (
      SendController(
        identity: identity,
        network: network,
        address: address,
        chainApi: chain,
      ),
      chain,
      identity,
      address,
    );
  }

  group('pricing an SPL transfer', () {
    test('to a wallet that already holds the token: just the network fee',
        () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.accounts[recipientAta(SplTokenProgram.token)] =
          (mint: usdc, owner: recipient, program: SplTokenProgram.token);

      final quote = await send.prepareSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );

      expect(quote.problem, isNull);
      expect(quote.fee, BigInt.from(5000));
      expect(quote.opensAccount, isFalse);
      send.dispose();
    });

    test('to a new wallet: the fee plus the rent of the account it opens',
        () async {
      final (SendController send, _, _, _) = await setup();

      final quote = await send.prepareSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );

      expect(quote.problem, isNull);
      expect(quote.opensAccount, isTrue);
      expect(quote.fee, BigInt.from(5000) + BigInt.from(2039280));
      send.dispose();
    });

    test('too little SOL for the fee and the new account is refused',
        () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.solBalance = BigInt.from(1000000); // 0.001 SOL

      final quote = await send.prepareSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );

      expect(quote.problem, contains('Not enough SOL'));
      expect(quote.problem, contains('opens'));
      send.dispose();
    });

    test('leaving SOL between zero and the minimum is refused', () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.accounts[recipientAta(SplTokenProgram.token)] =
          (mint: usdc, owner: recipient, program: SplTokenProgram.token);
      chain.solBalance = BigInt.from(5000) + BigInt.from(100000);

      final quote = await send.prepareSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );

      expect(quote.problem, contains('less SOL'));
      send.dispose();
    });

    test('more than the balance is refused', () async {
      final (SendController send, _, _, _) = await setup();
      final quote = await send.prepareSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(5000001),
      );
      expect(quote.problem, contains('balance is lower'));
      expect(quote.fee, isNull);
      send.dispose();
    });

    test('a balance split over accounts that cannot cover it alone is explained',
        () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.senderAccounts = <({String address, BigInt amount})>[
        (address: senderTokenAccount, amount: BigInt.from(3000000)),
        (address: 'DkUCtL5y1yCbZVGJ2FTxiUpVyqpBkGsFyouXXjQU7AcJ', amount: BigInt.from(2000000)),
      ];
      final quote = await send.prepareSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(4000000),
      );
      expect(quote.problem, contains('split'));
      send.dispose();
    });

    test('an unknown mint program is refused', () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.mintKnown = false;
      final quote = await send.prepareSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );
      expect(quote.problem, contains('not one the wallet can send'));
      send.dispose();
    });

    test('decimals that changed under the balance are refused', () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.mintDecimals = 9;
      final quote = await send.prepareSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );
      expect(quote.problem, contains('decimals'));
      send.dispose();
    });

    test('pasting a token account where a wallet belongs is refused', () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.accounts[recipient] =
          (mint: usdc, owner: 'someoneElse', program: SplTokenProgram.token);
      final quote = await send.prepareSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );
      expect(quote.problem, contains('token account, not a wallet'));
      send.dispose();
    });

    test("a recipient account for another mint or owner is not used",
        () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.accounts[recipientAta(SplTokenProgram.token)] = (
        mint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1w',
        owner: recipient,
        program: SplTokenProgram.token,
      );
      final quote = await send.prepareSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );
      expect(quote.problem, contains('not usable'));
      send.dispose();
    });

    test('what the chain would reject is shown in plain words', () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.unsignedSimulationError = 'InsufficientFundsForRent';
      final quote = await send.prepareSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );
      expect(quote.problem, contains('below the minimum'));
      send.dispose();
    });

    test('Custom 18 is not mistaken for Custom 1', () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.unsignedSimulationError = <String, Object>{
        'InstructionError': <Object>[0, <String, int>{'Custom': 18}],
      };
      final quote = await send.prepareSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );
      expect(quote.problem, isNot(contains('Not enough tokens')));
      expect(quote.problem, contains('would reject'));
      send.dispose();
    });
  });

  group('sending an SPL transfer', () {
    test('signs the exact reviewed message and broadcasts once', () async {
      final (SendController send, _SplChain chain, WalletIdentityController identity, String address) =
          await setup();

      final bool ok = await send.sendSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1234567),
      );

      expect(ok, isTrue, reason: send.error);
      expect(chain.broadcasts, 1);
      expect(send.txHash, 'splsig');
      // The dry run happened first (unsigned), then once more on the signed bytes.
      expect(chain.simulationChecks, <bool>[false, true]);

      // The broadcast bytes are 1 signature + the expected message, and the
      // signature verifies under the wallet's own key.
      final Uint8List tx = chain.lastTransaction!;
      expect(tx[0], 1);
      final Uint8List signature = tx.sublist(1, 65);
      final Uint8List message = tx.sublist(65);
      final Uint8List expected = SplTokenSigner.transferMessage(
        owner: Base58.decode(address)!,
        source: Base58.decode(senderTokenAccount)!,
        recipientOwner: Base58.decode(recipient)!,
        mint: Base58.decode(usdc)!,
        program: SplTokenProgram.token,
        amount: BigInt.from(1234567),
        decimals: 6,
        createDestination: true,
        recentBlockhash: Uint8List.fromList(List<int>.generate(32, (int i) => i + 1)),
      );
      expect(message, expected);

      final keys = AddressDeriver.solanaKeyPairFromSeed(
        identity.seed!,
        account: identity.accountIndex,
      );
      expect(
        ed.verify(ed.PublicKey(keys.publicKey), message, signature),
        isTrue,
      );
      send.dispose();
    });

    test('does not create the account when it exists', () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.accounts[recipientAta(SplTokenProgram.token)] =
          (mint: usdc, owner: recipient, program: SplTokenProgram.token);

      final bool ok = await send.sendSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );
      expect(ok, isTrue);
      // A plain transfer is the shorter message.
      expect(chain.lastTransaction!.length, lessThan(300));
      send.dispose();
    });

    test('a transfer the chain would reject is never broadcast', () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.signedSimulationError = 'BlockhashNotFound';

      final bool ok = await send.sendSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );

      expect(ok, isFalse);
      expect(chain.broadcasts, 0);
      expect(send.error, contains('Nothing was sent'));
      expect(send.txHash, isNull);
      send.dispose();
    });

    test('a problem found while planning stops before anything is signed',
        () async {
      final (SendController send, _SplChain chain, _, _) = await setup();
      chain.solBalance = BigInt.from(1000);

      final bool ok = await send.sendSplToken(
        token: token,
        to: recipient,
        amount: BigInt.from(1000000),
      );

      expect(ok, isFalse);
      expect(chain.broadcasts, 0);
      expect(chain.simulationChecks, <bool>[false]);
      send.dispose();
    });

    test('a watch-only wallet cannot send tokens', () async {
      final (SendController send, _SplChain chain, WalletIdentityController identity, _) =
          await setup();
      await identity.addWatchWallet(
        name: 'Friend',
        addresses: <String, String>{'sol': recipient},
      );

      final bool ok = await send.sendSplToken(
        token: token,
        to: 'DkUCtL5y1yCbZVGJ2FTxiUpVyqpBkGsFyouXXjQU7AcJ',
        amount: BigInt.from(1000000),
      );
      expect(ok, isFalse);
      expect(send.error, contains('watch-only'));
      expect(chain.broadcasts, 0);
      send.dispose();
    });

    test('sending to yourself is refused', () async {
      final (SendController send, _SplChain chain, _, String address) =
          await setup();
      final bool ok = await send.sendSplToken(
        token: token,
        to: address,
        amount: BigInt.from(1000000),
      );
      expect(ok, isFalse);
      expect(chain.broadcasts, 0);
      send.dispose();
    });
  });
}
