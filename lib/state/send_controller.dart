import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/utils/app_log.dart';
import '../core/utils/units.dart';
import '../data/models/chain_kind.dart';
import '../data/networks/chain_api.dart';
import '../data/networks/chain_models.dart';
import '../data/networks/network_config.dart';
import '../core/crypto/base58.dart';
import '../data/wallet/address_deriver.dart';
import '../data/wallet/aptos_signer.dart';
import '../data/wallet/bitcoin_signer.dart';
import '../data/wallet/evm_signer.dart';
import '../data/wallet/solana_signer.dart';
import 'wallet_identity_controller.dart';

/// Speed presets offered for an EIP-1559 transfer.
///
/// The node's suggested priority tip is treated as "normal"; the others scale
/// it, which is the practical lever now that the base fee is burned. [custom]
/// carries no built-in fee — the UI supplies the entered values.
enum FeePreset {
  slow('Slow'),
  normal('Normal'),
  fast('Fast'),
  custom('Custom');

  const FeePreset(this.label);

  final String label;

  /// The priority tip for this preset given a network-suggested [tip].
  BigInt tipFor(BigInt tip) => switch (this) {
        // Half the tip, but never zero — a zero tip is ignored by miners.
        FeePreset.slow => tip ~/ BigInt.two < BigInt.one
            ? BigInt.one
            : tip ~/ BigInt.two,
        FeePreset.normal => tip,
        FeePreset.fast => tip * BigInt.two,
        // Unused: the UI builds the custom fee from the user's own input.
        FeePreset.custom => tip,
      };

  /// The fee cap for this preset: base fee headroom plus the scaled tip.
  BigInt capFor(BigInt baseFee, BigInt tip) =>
      baseFee * BigInt.two + tipFor(tip);

  /// The satoshis-per-vbyte this preset selects from the network's published
  /// [tiers]: Slow confirms within an hour, Normal within half an hour, Fast
  /// targets the next block.
  ///
  /// The tip/handling of EIP-1559 does not apply here; only the target does.
  int satPerVbFor(BitcoinFeeTiers tiers) => switch (this) {
        FeePreset.slow => tiers.hourFee,
        FeePreset.normal => tiers.halfHourFee,
        FeePreset.fast => tiers.fastestFee,
        // Unused: the UI builds the custom rate from the user's own input.
        FeePreset.custom => tiers.halfHourFee,
      };
}

/// Where a transfer is in its lifecycle.
enum SendStage {
  /// Nothing has happened yet.
  idle,

  /// Fetching the nonce and estimating gas.
  preparing,

  /// Signing on-device with the seed held in memory.
  signing,

  /// Handing the signed transaction to the node.
  broadcasting,

  /// The node accepted it; the hash is known.
  broadcast,

  /// The transaction was mined.
  confirmed,

  /// Mined but reverted.
  failed,
}

/// Drives one outgoing transfer: fee estimation, signing, broadcast, confirmation.
///
/// Signing needs the decrypted seed, which [WalletIdentityController] only
/// holds while the wallet is unlocked. The signing key is derived on demand and
/// zeroed as soon as the signature exists, so the raw private key never outlives
/// the call.
class SendController extends ChangeNotifier {
  SendController({
    required this.identity,
    required this.network,
    required this.address,
    ChainApi? chainApi,
  }) : _chainApi = chainApi ?? ChainApi();

  final WalletIdentityController identity;
  final NetworkConfig network;
  final String address;
  final ChainApi _chainApi;

  SendStage _stage = SendStage.idle;
  String? _txHash;
  String? _error;
  bool _disposed = false;

  SendStage get stage => _stage;

  /// Transaction hash once the node has accepted it.
  String? get txHash => _txHash;

  /// Human readable reason the last attempt failed, or `null`.
  String? get error => _error;

  bool get busy =>
      _stage == SendStage.preparing ||
      _stage == SendStage.signing ||
      _stage == SendStage.broadcasting;

  /// Prepares a transfer of [value] wei to [to] for the current wallet account.
  ///
  /// When [tokenContract] is set the value is that token's holding rather than
  /// the chain's native currency, and the same live re-read covers both.
  ///
  /// Returns `true` when the transfer went out. A false return means [error] is
  /// set and nothing was broadcast — the UI must not claim otherwise.
  Future<bool> send({
    required String to,
    required BigInt value,
    required BigInt maxPriorityFeePerGas,
    required BigInt maxFeePerGas,
    required BigInt gasLimit,
    Uint8List? data,
    int? nonceOverride,
    String? tokenContract,
    BigInt? tokenAmount,
  }) async {
    if (network.chain != ChainKind.evm || !network.canSign) {
      return _fail('${network.name} does not support sending yet.');
    }

    try {
      _notify(() => _stage = SendStage.preparing);

      // The balance shown on screen may be stale: a send is only safe if the
      // account still covers amount + fee at the moment of signing. One fetch
      // here protects every caller, not just the send screen. For a token
      // transfer [value] is zero, so this only covers the native gas.
      final BigInt liveBalance = await _chainApi.fetchBalance(network, address);
      if (value + maxFeePerGas * gasLimit > liveBalance) {
        return _fail(
          'Your balance dropped since the last refresh. Nothing was sent.',
        );
      }

      // …and a token holding can be spent just as silently, so it gets the same
      // treatment. Checking it here rather than in the send screen means every
      // token transfer is covered, including the ones the UI never rendered.
      // [value] is zero for a token transfer (it moves no native currency), so
      // the amount being moved is [tokenAmount].
      final String? token = tokenContract;
      if (token != null) {
        final BigInt liveTokens = await _chainApi.fetchTokenBalance(
          network: network,
          token: token,
          owner: address,
        );
        if ((tokenAmount ?? BigInt.zero) > liveTokens) {
          return _fail(
            'Your token balance dropped since the last refresh. '
            'Nothing was sent.',
          );
        }
      }

      // A replacement (cancel) must reuse the stuck transaction's nonce; a
      // fresh transfer asks the node for the next one.
      final int nonce =
          nonceOverride ?? await _chainApi.getTransactionCount(network, address);

      _notify(() => _stage = SendStage.signing);

      final Uint8List seed = await _requireSeed();
      final Uint8List privateKey = EvmSigner.privateKeyFromSeed(
        seed,
        account: identity.accountIndex,
      );
      final String raw;
      try {
        raw = EvmSigner.signEip1559Transfer(
          privateKey: privateKey,
          nonce: nonce,
          maxPriorityFeePerGas: maxPriorityFeePerGas,
          maxFeePerGas: maxFeePerGas,
          gasLimit: gasLimit,
          to: to,
          value: value,
          chainId: network.chainId!,
          data: data,
        );
      } finally {
        // The signing key is never needed past this point.
        privateKey.fillRange(0, privateKey.length, 0);
      }

      _notify(() => _stage = SendStage.broadcasting);
      final String hash = await _chainApi.sendRawTransaction(network, raw);

      _notify(() {
        _txHash = hash;
        _stage = SendStage.broadcast;
      });

      final bool? ok = await _chainApi.waitForReceipt(network, hash);
      _notify(() {
        _stage = ok == null
            ? SendStage.broadcast
            : ok
                ? SendStage.confirmed
                : SendStage.failed;
      });
      return ok != false;
    } on ChainApiException catch (error, stackTrace) {
      AppLog.warning('Transfer failed on ${network.name}', error, stackTrace);
      return _fail(error.message);
    } on EvmSigningException catch (error, stackTrace) {
      AppLog.warning('Signing failed', error, stackTrace);
      return _fail(error.message);
    } catch (error, stackTrace) {
      AppLog.error('Unexpected transfer failure', error, stackTrace);
      return _fail('Something went wrong while sending. Nothing was sent.');
    }
  }

  /// Fetches live EIP-1559 fee parameters (base fee and suggested tip) plus a
  /// gas estimate for the transfer.
  ///
  /// Returns `null` on failure, so the UI can refuse to send rather than sign
  /// with a made-up fee.
  Future<({BigInt baseFee, BigInt maxPriorityFeePerGas, BigInt gasLimit})?>
      prepare({
    required String to,
    required BigInt value,
    Uint8List? data,
  }) async {
    if (!network.canSign) {
      return null;
    }
    try {
      final ({BigInt baseFee, BigInt maxPriorityFeePerGas}) fees =
          await _chainApi.fetchFeeData(network);
      final BigInt gasLimit = await _chainApi.estimateTransferGas(
        network: network,
        from: address,
        to: to,
        value: value,
        data: data,
      );
      return (
        baseFee: fees.baseFee,
        maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
        gasLimit: gasLimit,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _chainApi.dispose();
    super.dispose();
  }

  // --- Bitcoin transfer -----------------------------------------------------

  /// The network's ready-made confirmation tiers, or `null` when unavailable.
  Future<BitcoinFeeTiers?> recommendedBitcoinFeeTiers() async {
    if (network.chain != ChainKind.bitcoin) {
      return null;
    }
    try {
      return await _chainApi.fetchBitcoinFeeTiers(network);
    } catch (error) {
      AppLog.warning('Bitcoin fee tiers unavailable', error);
      return null;
    }
  }

  /// Plans a Bitcoin transfer of [amount] satoshis to [to]: the fee rate, the
  /// utxos to spend and the change output.
  ///
  /// [feeRate] defaults to the network recommendation. Returns `null` on any
  /// failure or when the funds are short, so the UI can refuse rather than sign
  /// an underfunded transaction.
  Future<BitcoinPlan?> prepareBitcoin({
    required String to,
    required BigInt amount,
    int? feeRate,
  }) async {
    if (network.chain != ChainKind.bitcoin || !network.canSign) {
      return null;
    }
    try {
      final int rate = feeRate ?? await _chainApi.fetchBitcoinFeeRate(network);
      final List<BitcoinUtxo> utxos =
          await _chainApi.fetchBitcoinUtxos(network, address);
      return BitcoinSigner.plan(
        utxos: utxos,
        amount: amount,
        recipientScript: BitcoinSigner.scriptPubKeyForAddress(to, hrp: network.hrp),
        changeScript:
            BitcoinSigner.scriptPubKeyForAddress(address, hrp: network.hrp),
        feeRate: rate,
      );
    } catch (error, stackTrace) {
      AppLog.warning('Could not prepare a Bitcoin transfer', error, stackTrace);
      return null;
    }
  }

  /// The most that can be sent in one transaction at [feeRate], or `null`.
  Future<BigInt?> maxBitcoinAmount({required int feeRate}) async {
    try {
      final List<BitcoinUtxo> utxos =
          await _chainApi.fetchBitcoinUtxos(network, address);
      return BitcoinSigner.maxSpendable(utxos: utxos, feeRate: feeRate);
    } catch (error, stackTrace) {
      AppLog.warning('Could not read the Bitcoin balance', error, stackTrace);
      return null;
    }
  }

  /// Signs [plan] on-device and broadcasts it.
  ///
  /// Re-reads the utxo set first: a coin spent since the transfer was reviewed
  /// would invalidate the signature, so its disappearance is checked and the
  /// send refused rather than broadcast and rejected.
  Future<bool> sendBitcoin({required BitcoinPlan plan}) async {
    if (network.chain != ChainKind.bitcoin || !network.canSign) {
      return _fail('${network.name} does not support sending yet.');
    }

    try {
      _notify(() => _stage = SendStage.preparing);

      final Set<String> live = <String>{
        for (final BitcoinUtxo utxo
            in await _chainApi.fetchBitcoinUtxos(network, address))
          utxo.outpoint,
      };
      for (final BitcoinUtxo input in plan.inputs) {
        if (!live.contains(input.outpoint)) {
          return _fail(
            'Your balance changed since the last refresh. Nothing was sent.',
          );
        }
      }

      _notify(() => _stage = SendStage.signing);

      final Uint8List seed = await _requireSeed();
      final ({Uint8List privateKey, Uint8List publicKey}) keys =
          AddressDeriver.bitcoinKeyPairFromSeed(
        seed,
        account: identity.accountIndex,
      );
      final String raw;
      try {
        raw = BitcoinSigner.signP2wpkh(
          privateKey: keys.privateKey,
          publicKey: keys.publicKey,
          utxos: plan.inputs,
          outputs: plan.outputs,
        );
      } finally {
        // The signing key is never needed past this point.
        keys.privateKey.fillRange(0, keys.privateKey.length, 0);
      }

      _notify(() => _stage = SendStage.broadcasting);
      final String hash =
          await _chainApi.broadcastBitcoinTransaction(network, raw);

      _notify(() {
        _txHash = hash;
        _stage = SendStage.broadcast;
      });

      final bool? ok =
          await _chainApi.waitForBitcoinConfirmation(network, hash);
      _notify(() {
        _stage = ok == null
            ? SendStage.broadcast
            : ok
                ? SendStage.confirmed
                : SendStage.failed;
      });
      return ok != false;
    } on ChainApiException catch (error, stackTrace) {
      AppLog.warning('Bitcoin transfer failed on ${network.name}', error, stackTrace);
      return _fail(error.message);
    } on BitcoinSigningException catch (error, stackTrace) {
      AppLog.warning('Bitcoin signing failed', error, stackTrace);
      return _fail(error.message);
    } on EvmSigningException catch (error) {
      // `_requireSeed` reuses this type to flag a locked wallet.
      return _fail(error.message);
    } catch (error, stackTrace) {
      AppLog.error('Unexpected Bitcoin transfer failure', error, stackTrace);
      return _fail('Something went wrong while sending. Nothing was sent.');
    }
  }

  /// Plans a replace-by-fee version of the pending Bitcoin transfer
  /// [txid]: the same payment, a larger fee taken from the change.
  ///
  /// The reason a replacement is impossible comes back as text, because the
  /// user needs to know *why* a stuck transfer cannot be rescued.
  Future<({BitcoinPlan? plan, BigInt? oldFee, String? reason})>
      prepareBitcoinSpeedUp(String txid) async {
    if (network.chain != ChainKind.bitcoin || !network.canSign) {
      return (
        plan: null,
        oldFee: null,
        reason: '${network.name} does not support sending yet.',
      );
    }
    try {
      final BitcoinPriorTx? original =
          await _chainApi.fetchBitcoinTransaction(network, txid);
      if (original == null) {
        return (
          plan: null,
          oldFee: null,
          reason: 'The network no longer knows this transfer.',
        );
      }
      final BitcoinFeeTiers tiers =
          await _chainApi.fetchBitcoinFeeTiers(network);
      final BitcoinPlan plan = BitcoinSigner.planReplacement(
        original: original,
        ownAddress: address,
        targetFeeRate: tiers.fastestFee,
      );
      BigInt oldFee = BigInt.zero;
      for (final BitcoinPriorInput i in original.inputs) {
        oldFee += i.utxo.value;
      }
      for (final BitcoinPriorOutput o in original.outputs) {
        oldFee -= o.output.value;
      }
      return (plan: plan, oldFee: oldFee, reason: null);
    } on BitcoinSigningException catch (error) {
      return (plan: null, oldFee: null, reason: error.message);
    } on ChainApiException catch (error) {
      return (plan: null, oldFee: null, reason: error.message);
    } catch (error, stackTrace) {
      AppLog.warning('Could not plan a Bitcoin speed-up', error, stackTrace);
      return (
        plan: null,
        oldFee: null,
        reason: 'Could not prepare a faster version. Nothing was changed.',
      );
    }
  }

  /// Signs and broadcasts [plan] as a replacement of the pending transfer
  /// [originalTxid].
  ///
  /// Re-reads the original first: a transfer that confirmed in the meantime
  /// needs no replacement (and a second payment would just be rejected), and
  /// inputs that no longer match mean the plan was built from stale data. Both
  /// refuse rather than sign.
  Future<bool> sendBitcoinReplacement({
    required String originalTxid,
    required BitcoinPlan plan,
  }) async {
    if (network.chain != ChainKind.bitcoin || !network.canSign) {
      return _fail('${network.name} does not support sending yet.');
    }

    try {
      _notify(() => _stage = SendStage.preparing);

      final BitcoinPriorTx? live =
          await _chainApi.fetchBitcoinTransaction(network, originalTxid);
      if (live == null) {
        return _fail(
          'The network no longer knows the original transfer. Nothing was sent.',
        );
      }
      if (live.confirmed) {
        return _fail(
          'The original transfer has just confirmed. Nothing was sent.',
        );
      }
      final Set<String> liveInputs = <String>{
        for (final BitcoinPriorInput i in live.inputs) i.utxo.outpoint,
      };
      final Set<String> planned = <String>{
        for (final BitcoinUtxo i in plan.inputs) i.outpoint,
      };
      if (liveInputs.length != planned.length ||
          !liveInputs.containsAll(planned)) {
        return _fail(
          'The original transfer changed since it was reviewed. Nothing was sent.',
        );
      }

      _notify(() => _stage = SendStage.signing);

      final Uint8List seed = await _requireSeed();
      final ({Uint8List privateKey, Uint8List publicKey}) keys =
          AddressDeriver.bitcoinKeyPairFromSeed(
        seed,
        account: identity.accountIndex,
      );
      final String raw;
      try {
        raw = BitcoinSigner.signP2wpkh(
          privateKey: keys.privateKey,
          publicKey: keys.publicKey,
          utxos: plan.inputs,
          outputs: plan.outputs,
        );
      } finally {
        keys.privateKey.fillRange(0, keys.privateKey.length, 0);
      }

      _notify(() => _stage = SendStage.broadcasting);
      final String hash =
          await _chainApi.broadcastBitcoinTransaction(network, raw);

      _notify(() {
        _txHash = hash;
        _stage = SendStage.broadcast;
      });

      final bool? ok =
          await _chainApi.waitForBitcoinConfirmation(network, hash);
      _notify(() {
        _stage = ok == null
            ? SendStage.broadcast
            : ok
                ? SendStage.confirmed
                : SendStage.failed;
      });
      return ok != false;
    } on ChainApiException catch (error, stackTrace) {
      AppLog.warning('Bitcoin replacement failed', error, stackTrace);
      return _fail(error.message);
    } on BitcoinSigningException catch (error, stackTrace) {
      AppLog.warning('Bitcoin signing failed', error, stackTrace);
      return _fail(error.message);
    } on EvmSigningException catch (error) {
      return _fail(error.message);
    } catch (error, stackTrace) {
      AppLog.error('Unexpected Bitcoin replacement failure', error, stackTrace);
      return _fail('Something went wrong while sending. Nothing was sent.');
    }
  }

  // --- Solana and Aptos: native coin transfers -------------------------------

  /// Prices a native transfer of [amount] (smallest units) to [to] on Solana or
  /// Aptos against the **live** chain: the exact fee, plus a plain-language
  /// [problem] when the transfer would be refused or would leave an account in
  /// a state the chain forbids.
  ///
  /// `fee` is `null` only when nothing could be priced; the UI then blocks
  /// sending instead of guessing.
  Future<({BigInt? fee, String? problem})> prepareNative({
    required String to,
    required BigInt amount,
  }) async {
    try {
      return switch (network.chain) {
        ChainKind.solana => await _planSolana(to: to, amount: amount),
        ChainKind.aptos => await _planAptos(to: to, amount: amount),
        _ => (fee: null, problem: '${network.name} does not support sending.'),
      };
    } on _NativeRefusal catch (refusal) {
      return (fee: null, problem: refusal.message);
    } on ChainApiException catch (error) {
      return (fee: null, problem: error.message);
    } on SolanaSigningException catch (error) {
      return (fee: null, problem: error.message);
    } on AptosSigningException catch (error) {
      return (fee: null, problem: error.message);
    } on EvmSigningException catch (error) {
      return (fee: null, problem: error.message);
    } catch (error, stackTrace) {
      AppLog.warning('Could not price a ${network.symbol} transfer', error, stackTrace);
      return (fee: null, problem: 'Could not price this transfer.');
    }
  }

  /// Signs and broadcasts a native transfer on Solana or Aptos.
  ///
  /// Everything the signature depends on is read again here — balance, the
  /// recipient's rent state, the blockhash or sequence number — so a stale
  /// review can never be signed. Returns `true` when the transfer went out and
  /// was not rejected; a `false` return means [error] is set.
  Future<bool> sendNative({required String to, required BigInt amount}) async {
    if (!network.canSign ||
        (network.chain != ChainKind.solana && network.chain != ChainKind.aptos)) {
      return _fail('${network.name} does not support sending yet.');
    }
    try {
      _notify(() => _stage = SendStage.preparing);
      final (String, bool?) result = network.chain == ChainKind.solana
          ? await _sendSolana(to: to, amount: amount)
          : await _sendAptos(to: to, amount: amount);
      final bool? ok = result.$2;
      _notify(() {
        _stage = ok == null
            ? SendStage.broadcast
            : ok
                ? SendStage.confirmed
                : SendStage.failed;
      });
      return ok != false;
    } on _NativeRefusal catch (refusal) {
      return _fail(refusal.message);
    } on ChainApiException catch (error, stackTrace) {
      AppLog.warning('Transfer failed on ${network.name}', error, stackTrace);
      return _fail(error.message);
    } on SolanaSigningException catch (error) {
      return _fail(error.message);
    } on AptosSigningException catch (error) {
      return _fail(error.message);
    } on EvmSigningException catch (error) {
      // `_requireSeed` reuses this type to flag a locked wallet.
      return _fail(error.message);
    } catch (error, stackTrace) {
      AppLog.error('Unexpected transfer failure', error, stackTrace);
      return _fail('Something went wrong while sending. Nothing was sent.');
    }
  }

  // Solana

  Uint8List _solanaKey(String base58, String what) {
    final Uint8List? bytes = Base58.decode(base58);
    if (bytes == null || bytes.length != 32) {
      throw SolanaSigningException('Invalid Solana $what.');
    }
    return bytes;
  }

  /// The refusal text for a transfer the chain would reject or that would
  /// strand an account under the rent minimum, or `null` when it is fine.
  ///
  /// A System account must hold nothing or at least the rent-exempt minimum:
  /// a first payment to a brand-new address has to cover it, and the sender
  /// may not leave a remainder in between.
  String? _solanaProblem({
    required BigInt amount,
    required BigInt fee,
    required BigInt senderBalance,
    required BigInt recipientBalance,
    required BigInt rentMinimum,
  }) {
    String sol(BigInt v) => Units.formatWithSymbol(v, 9, 'SOL', maxDecimals: 9);
    if (amount + fee > senderBalance) {
      return 'Not enough SOL for the amount and the network fee.';
    }
    if (recipientBalance + amount < rentMinimum) {
      return 'The recipient account is new: it needs at least ${sol(rentMinimum)} '
          'to exist. Send ${sol(rentMinimum - recipientBalance)} or more.';
    }
    final BigInt remainder = senderBalance - amount - fee;
    if (remainder > BigInt.zero && remainder < rentMinimum) {
      return 'This would leave ${sol(remainder)} in your account, below the '
          '${sol(rentMinimum)} an account must keep. Send everything or less.';
    }
    return null;
  }

  Future<({BigInt? fee, String? problem})> _planSolana({
    required String to,
    required BigInt amount,
  }) async {
    final Uint8List from = _solanaKey(address, 'address');
    final Uint8List recipient = _solanaKey(to, 'recipient');
    final Uint8List blockhash = await _chainApi.fetchSolanaBlockhash(network);
    final Uint8List message = SolanaSigner.transferMessage(
      from: from,
      to: recipient,
      lamports: amount,
      recentBlockhash: blockhash,
    );
    final BigInt fee = await _chainApi.fetchSolanaMessageFee(network, message) ??
        BigInt.from(5000);
    final List<BigInt> live = await Future.wait(<Future<BigInt>>[
      _chainApi.fetchBalance(network, address),
      _chainApi.fetchBalance(network, to),
      _chainApi.fetchSolanaRentExemptMinimum(network),
    ]);
    return (
      fee: fee,
      problem: _solanaProblem(
        amount: amount,
        fee: fee,
        senderBalance: live[0],
        recipientBalance: live[1],
        rentMinimum: live[2],
      ),
    );
  }

  Future<(String, bool?)> _sendSolana({
    required String to,
    required BigInt amount,
  }) async {
    final Uint8List from = _solanaKey(address, 'address');
    final Uint8List recipient = _solanaKey(to, 'recipient');

    // Fresh blockhash first: the transaction dies ~150 slots after it.
    final Uint8List blockhash = await _chainApi.fetchSolanaBlockhash(network);
    final Uint8List message = SolanaSigner.transferMessage(
      from: from,
      to: recipient,
      lamports: amount,
      recentBlockhash: blockhash,
    );
    final BigInt fee = await _chainApi.fetchSolanaMessageFee(network, message) ??
        BigInt.from(5000);
    final List<BigInt> live = await Future.wait(<Future<BigInt>>[
      _chainApi.fetchBalance(network, address),
      _chainApi.fetchBalance(network, to),
      _chainApi.fetchSolanaRentExemptMinimum(network),
    ]);
    final String? problem = _solanaProblem(
      amount: amount,
      fee: fee,
      senderBalance: live[0],
      recipientBalance: live[1],
      rentMinimum: live[2],
    );
    if (problem != null) {
      throw _NativeRefusal('$problem Nothing was sent.');
    }

    _notify(() => _stage = SendStage.signing);
    final Uint8List seed = await _requireSeed();
    final ({Uint8List privateSeed, Uint8List publicKey}) keys =
        AddressDeriver.solanaKeyPairFromSeed(seed, account: identity.accountIndex);
    final Uint8List transaction;
    try {
      if (!_bytesEqual(keys.publicKey, from)) {
        throw const _NativeRefusal(
          'The wallet key does not match this account. Nothing was sent.',
        );
      }
      transaction = SolanaSigner.signTransaction(
        privateSeed: keys.privateSeed,
        message: message,
      );
    } finally {
      keys.privateSeed.fillRange(0, keys.privateSeed.length, 0);
    }

    _notify(() => _stage = SendStage.broadcasting);
    final String signature =
        await _chainApi.sendSolanaTransaction(network, transaction);
    _notify(() {
      _txHash = signature;
      _stage = SendStage.broadcast;
    });
    final bool? ok =
        await _chainApi.waitForSolanaConfirmation(network, signature);
    return (signature, ok);
  }

  // Aptos

  /// ponytail: a flat 2× margin over the simulated gas, not a tuned figure; a
  /// transfer that needs more would run out of gas. The floor is the node's
  /// intrinsic minimum plus margin ([AptosSigner.maxGasFloor]), not an
  /// execution estimate.
  ///
  /// Units of gas a simulation says a transfer uses, with room to spare.
  static int _aptosMaxGas(int gasUsed) {
    final int padded = gasUsed * 2;
    return padded < AptosSigner.maxGasFloor ? AptosSigner.maxGasFloor : padded;
  }

  Future<
      ({
        Uint8List rawTransaction,
        int gasUsed,
        int maxGas,
        int gasPrice,
        Uint8List publicKey,
        Uint8List privateSeed,
      })> _aptosBuild({
    required String to,
    required BigInt amount,
    required bool keepKey,
  }) async {
    final Uint8List sender = AptosSigner.addressBytes(address);
    final Uint8List recipient = AptosSigner.addressBytes(to);
    if (_bytesEqual(sender, recipient)) {
      throw const AptosSigningException('Sending to your own address does nothing.');
    }

    final int? sequence =
        await _chainApi.fetchAptosSequenceNumber(network, address);
    if (sequence == null) {
      throw const _NativeRefusal(
        'This Aptos account has not been funded yet, so it cannot send.',
      );
    }
    final ({int chainId, int ledgerTimeSecs}) ledger =
        await _chainApi.fetchAptosLedger(network);
    final int gasPrice = await _chainApi.fetchAptosGasUnitPrice(network);
    final int expiry = ledger.ledgerTimeSecs + 600;

    final Uint8List seed = await _requireSeed();
    final ({Uint8List privateSeed, Uint8List publicKey}) keys =
        AddressDeriver.aptosKeyPairFromSeed(seed, account: identity.accountIndex);
    try {
      // Dry run first: the exact gas, and a refusal before anything is signed.
      Uint8List raw = AptosSigner.rawTransfer(
        sender: sender,
        sequenceNumber: sequence,
        to: recipient,
        amount: amount,
        maxGasAmount: 100000,
        gasUnitPrice: gasPrice,
        expirationTimestampSecs: expiry,
        chainId: ledger.chainId,
      );
      final ({bool success, String vmStatus, int gasUsed}) simulation =
          await _chainApi.simulateAptos(
        network,
        AptosSigner.simulationTransaction(
          rawTransaction: raw,
          publicKey: keys.publicKey,
        ),
      );
      if (!simulation.success) {
        throw _NativeRefusal(
          'The network would reject this transfer (${simulation.vmStatus}). '
          'Nothing was sent.',
        );
      }
      final int maxGas = _aptosMaxGas(simulation.gasUsed);
      raw = AptosSigner.rawTransfer(
        sender: sender,
        sequenceNumber: sequence,
        to: recipient,
        amount: amount,
        maxGasAmount: maxGas,
        gasUnitPrice: gasPrice,
        expirationTimestampSecs: expiry,
        chainId: ledger.chainId,
      );
      return (
        rawTransaction: raw,
        gasUsed: simulation.gasUsed,
        maxGas: maxGas,
        gasPrice: gasPrice,
        publicKey: keys.publicKey,
        privateSeed: keepKey ? keys.privateSeed : Uint8List(0),
      );
    } finally {
      if (!keepKey) {
        keys.privateSeed.fillRange(0, keys.privateSeed.length, 0);
      }
    }
  }

  Future<({BigInt? fee, String? problem})> _planAptos({
    required String to,
    required BigInt amount,
  }) async {
    final built = await _aptosBuild(to: to, amount: amount, keepKey: false);
    final BigInt fee = BigInt.from(built.gasUsed) * BigInt.from(built.gasPrice);
    final BigInt reserve = BigInt.from(built.maxGas) * BigInt.from(built.gasPrice);
    final BigInt balance = await _chainApi.fetchBalance(network, address);
    String apt(BigInt v) => Units.formatWithSymbol(v, 8, 'APT', maxDecimals: 8);
    String? problem;
    if (amount + fee > balance) {
      problem = 'Not enough APT for the amount and the network fee.';
    } else if (balance < reserve) {
      problem = 'Aptos needs ${apt(reserve)} available to cover the gas limit '
          'before it runs the transfer.';
    }
    return (fee: fee, problem: problem);
  }

  Future<(String, bool?)> _sendAptos({
    required String to,
    required BigInt amount,
  }) async {
    final built = await _aptosBuild(to: to, amount: amount, keepKey: true);
    final Uint8List privateSeed = built.privateSeed;
    final Uint8List signed;
    try {
      final BigInt fee = BigInt.from(built.gasUsed) * BigInt.from(built.gasPrice);
      final BigInt reserve =
          BigInt.from(built.maxGas) * BigInt.from(built.gasPrice);
      final BigInt balance = await _chainApi.fetchBalance(network, address);
      if (amount + fee > balance || balance < reserve) {
        throw const _NativeRefusal(
          'Your balance dropped since the last refresh. Nothing was sent.',
        );
      }
      _notify(() => _stage = SendStage.signing);
      signed = AptosSigner.sign(
        privateSeed: privateSeed,
        rawTransaction: built.rawTransaction,
      );
    } finally {
      privateSeed.fillRange(0, privateSeed.length, 0);
    }

    _notify(() => _stage = SendStage.broadcasting);
    final String hash = await _chainApi.submitAptos(network, signed);
    _notify(() {
      _txHash = hash;
      _stage = SendStage.broadcast;
    });
    final bool? ok = await _chainApi.waitForAptosTransaction(network, hash);
    return (hash, ok);
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  Future<Uint8List> _requireSeed() async {
    if (!identity.unlocked) {
      throw const EvmSigningException(
        'Unlock the wallet before sending.',
      );
    }
    final Uint8List? seed = identity.seed;
    if (seed == null) {
      throw const EvmSigningException(
        'Unlock the wallet before sending.',
      );
    }
    // Copied so zeroing the local copy cannot clobber the wallet's own seed.
    return Uint8List.fromList(seed);
  }

  bool _fail(String message) {
    _notify(() {
      _error = message;
      _stage = SendStage.failed;
    });
    return false;
  }

  void _notify(VoidCallback change) {
    if (_disposed) {
      return;
    }
    change();
    notifyListeners();
  }
}

/// A refusal raised mid-send with the exact text to show; nothing was sent.
class _NativeRefusal implements Exception {
  const _NativeRefusal(this.message);

  final String message;
}
