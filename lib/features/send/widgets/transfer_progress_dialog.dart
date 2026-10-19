import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/networks/chain_models.dart';
import '../../../data/wallet/bitcoin_signer.dart';
import '../../../state/send_controller.dart';
import '../../../l10n/l10n.dart';
import '../../../l10n/messages.dart';

/// Blocking dialog that drives a transfer from signing to confirmation.
///
/// The [SendController] is injected by the caller, which owns its lifecycle, so
/// the dialog only reacts to [SendStage] changes and reports the outcome back
/// through the controller. Shared by the normal send flow, the cancel flow and
/// the Bitcoin flow.
class TransferProgressDialog extends StatefulWidget {
  const TransferProgressDialog({
    super.key,
    required this.to,
    required this.value,
    this.maxPriorityFeePerGas,
    this.maxFeePerGas,
    this.gasLimit,
    this.data,
    this.nonceOverride,
    this.tokenContract,
    this.tokenAmount,
    this.bitcoinPlan,
    this.replacesTxid,
    this.nativeAmount,
    this.splToken,
  }) : assert(
          bitcoinPlan != null ||
              nativeAmount != null ||
              (maxPriorityFeePerGas != null &&
                  maxFeePerGas != null &&
                  gasLimit != null),
          'An EVM transfer needs maxPriorityFeePerGas, maxFeePerGas and '
          'gasLimit; a Bitcoin transfer needs bitcoinPlan; a Solana or Aptos '
          'transfer needs nativeAmount.',
        );

  final String to;
  final BigInt value;

  /// EIP-1559 fee parameters; required for an EVM transfer and absent for a
  /// Bitcoin one.
  final BigInt? maxPriorityFeePerGas;
  final BigInt? maxFeePerGas;
  final BigInt? gasLimit;

  /// Calldata for a token transfer; `null` for a native one.
  final Uint8List? data;

  /// Reuses a stuck transaction's nonce when replacing it (a cancel).
  final int? nonceOverride;

  /// Token contract whose holding is re-read before signing; `null` for a
  /// native transfer.
  final String? tokenContract;

  /// How much of that token is being moved, checked against the live holding.
  final BigInt? tokenAmount;

  /// When set, the transfer is a Bitcoin send of this plan instead of an EVM
  /// transaction.
  final BitcoinPlan? bitcoinPlan;

  /// With [bitcoinPlan]: the pending transfer this one replaces (RBF).
  final String? replacesTxid;

  /// A Solana or Aptos transfer of this many smallest units to [to]; the fee
  /// and the rest are read from the chain at signing time.
  final BigInt? nativeAmount;

  /// With [nativeAmount] on Solana or Aptos: the token being sent instead of
  /// the chain's coin (the amount is in that token's smallest unit).
  final TokenBalance? splToken;

  @override
  State<TransferProgressDialog> createState() => _TransferProgressDialogState();
}

class _TransferProgressDialogState extends State<TransferProgressDialog> {
  @override
  void initState() {
    super.initState();
    // Kick off after the first frame so the dialog is visible while the signing
    // work happens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final SendController controller = context.read<SendController>();
      final BigInt? nativeAmount = widget.nativeAmount;
      if (nativeAmount != null) {
        controller.sendNative(
          to: widget.to,
          amount: nativeAmount,
          token: widget.splToken,
        );
        return;
      }
      final BitcoinPlan? plan = widget.bitcoinPlan;
      if (plan != null) {
        final String? replaces = widget.replacesTxid;
        if (replaces != null) {
          controller.sendBitcoinReplacement(originalTxid: replaces, plan: plan);
        } else {
          controller.sendBitcoin(plan: plan);
        }
        return;
      }
      controller.send(
        to: widget.to,
        value: widget.value,
        maxPriorityFeePerGas: widget.maxPriorityFeePerGas!,
        maxFeePerGas: widget.maxFeePerGas!,
        gasLimit: widget.gasLimit!,
        data: widget.data,
        nonceOverride: widget.nonceOverride,
        tokenContract: widget.tokenContract,
        tokenAmount: widget.tokenAmount,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final SendController controller = context.watch<SendController>();
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool done = controller.stage == SendStage.confirmed ||
        controller.stage == SendStage.failed ||
        controller.stage == SendStage.broadcast;
    final String shortTo = widget.to.length > 14
        ? '${widget.to.substring(0, 10)}…'
        : widget.to;

    return PopScope(
      canPop: done,
      child: AlertDialog(
        title: Text(done ? context.l10n.transferSubmitted : context.l10n.sending),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!done) ...<Widget>[
              const LinearProgressIndicator(),
              const SizedBox(height: 18),
            ],
            Text(
              controller.stage == SendStage.broadcasting ||
                      controller.stage == SendStage.signing
                  ? context.l10n.signingOnThisDevice
                  : controller.stage == SendStage.broadcast
                      ? context.l10n.waitingForToConfirm(shortTo)
                      : controller.stage == SendStage.confirmed
                          ? context.l10n.confirmedOnChain
                          : tr(controller.error ?? context.l10n.broadcasting),
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (controller.txHash != null) ...[
              const SizedBox(height: 12),
              Text(
                'Tx ${controller.txHash!.length > 18 ? '${controller.txHash!.substring(0, 18)}…' : controller.txHash}',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          if (done)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.close),
            ),
        ],
      ),
    );
  }
}
