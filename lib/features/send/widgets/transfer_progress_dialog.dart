import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/send_controller.dart';

/// Blocking dialog that drives a transfer from signing to confirmation.
///
/// The [SendController] is injected by the caller, which owns its lifecycle, so
/// the dialog only reacts to [SendStage] changes and reports the outcome back
/// through the controller. Shared by the normal send flow and the cancel flow.
class TransferProgressDialog extends StatefulWidget {
  const TransferProgressDialog({
    super.key,
    required this.to,
    required this.value,
    required this.maxPriorityFeePerGas,
    required this.maxFeePerGas,
    required this.gasLimit,
    this.data,
    this.nonceOverride,
    this.tokenContract,
    this.tokenAmount,
  });

  final String to;
  final BigInt value;
  final BigInt maxPriorityFeePerGas;
  final BigInt maxFeePerGas;
  final BigInt gasLimit;

  /// Calldata for a token transfer; `null` for a native one.
  final Uint8List? data;

  /// Reuses a stuck transaction's nonce when replacing it (a cancel).
  final int? nonceOverride;

  /// Token contract whose holding is re-read before signing; `null` for a
  /// native transfer.
  final String? tokenContract;

  /// How much of that token is being moved, checked against the live holding.
  final BigInt? tokenAmount;

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
      context.read<SendController>().send(
            to: widget.to,
            value: widget.value,
            maxPriorityFeePerGas: widget.maxPriorityFeePerGas,
            maxFeePerGas: widget.maxFeePerGas,
            gasLimit: widget.gasLimit,
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
        title: Text(done ? 'Transfer submitted' : 'Sending…'),
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
                  ? 'Signing on this device…'
                  : controller.stage == SendStage.broadcast
                      ? 'Waiting for $shortTo to confirm…'
                      : controller.stage == SendStage.confirmed
                          ? 'Confirmed on-chain.'
                          : controller.error ?? 'Broadcasting…',
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
              child: const Text('Close'),
            ),
        ],
      ),
    );
  }
}
