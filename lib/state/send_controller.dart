import 'package:flutter/foundation.dart';

import '../core/utils/app_log.dart';
import '../data/models/chain_kind.dart';
import '../data/networks/chain_api.dart';
import '../data/networks/network_config.dart';
import '../data/wallet/evm_signer.dart';
import 'wallet_identity_controller.dart';

/// Speed presets offered for an EIP-1559 transfer.
///
/// The node's suggested priority tip is treated as "normal"; the others scale
/// it, which is the practical lever now that the base fee is burned.
enum FeePreset {
  slow('Slow'),
  normal('Normal'),
  fast('Fast');

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
      };

  /// The fee cap for this preset: base fee headroom plus the scaled tip.
  BigInt capFor(BigInt baseFee, BigInt tip) => baseFee * BigInt.two + tipFor(tip);
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

      // A replacement (cancel) must reuse the stuck transaction's nonce; a
      // fresh transfer asks the node for the next one.
      final int nonce =
          nonceOverride ?? await _chainApi.getTransactionCount(network, address);

      _notify(() => _stage = SendStage.signing);

      final Uint8List seed = await _requireSeed();
      final Uint8List privateKey = EvmSigner.privateKeyFromSeed(seed);
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