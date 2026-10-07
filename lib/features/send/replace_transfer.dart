import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../core/utils/units.dart';
import '../../data/networks/chain_models.dart';
import '../../data/networks/network_config.dart';
import '../../state/send_controller.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_identity_controller.dart';
import '../lock/sensitive_auth.dart';
import 'widgets/transfer_progress_dialog.dart';

/// What a stuck pending transaction should be replaced with.
enum ReplacementKind {
  /// A zero-value transfer to the wallet's own address. The original can never
  /// confirm, so the funds stay put.
  cancel,

  /// The same transfer again, priced higher so it outbids the original in the
  /// mempool and the payment actually lands.
  speedUp,
}

/// Replaces a stuck outgoing EVM transaction with one that reuses its [nonce].
///
/// A node keeps only one transaction per nonce, so once the replacement is
/// mined the original can never execute — which makes this the only way to
/// rescue a transfer that got stuck.
///
/// A [ReplacementKind.speedUp] replacement must carry the *same* `to`, value and
/// calldata as the original: EIP-1559 replacement rules reject a payload that
/// differs, and anything the user never intended to send must never ride along
/// on a fee bump. [ReplacementKind.cancel] sends nothing of the user's own
/// funds, so it needs no payload and works for every transfer.
///
/// ponytail: the replacement is priced from the fast preset rather than from
/// the stuck transaction's own fee cap, which the history API does not expose.
/// A transaction already priced above the current fast preset is therefore not
/// replaced — the node rejects it as underpriced.
Future<void> showReplaceTransfer(
  BuildContext context, {
  required NetworkConfig network,
  required int nonce,
  required ReplacementKind kind,
  required ChainTransaction original,
}) async {
  final bool cancelling = kind == ReplacementKind.cancel;
  final WalletIdentityController identity =
      context.read<WalletIdentityController>();
  final String? ownAddress = identity.addressFor(network);
  if (ownAddress == null) {
    return;
  }

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        cancelling ? Icons.cancel_rounded : Icons.rocket_launch_rounded,
      ),
      title: Text(cancelling ? 'Cancel this transfer?' : 'Speed this transfer up?'),
      content: Text(
        cancelling
            ? 'This sends 0 ${network.symbol} to yourself and reuses the '
                'pending transaction\'s nonce, so it can never confirm. It '
                'only works while the transaction is still pending.'
            : 'This sends '
                '${Units.formatWithSymbol(original.amount.abs(), network.decimals, network.symbol)} '
                'to ${original.counterparty} again with a higher fee, reusing '
                'the pending transaction\'s nonce. Exactly one of the two will '
                'confirm.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(cancelling ? 'Cancel transfer' : 'Speed up'),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false) || !context.mounted) {
    return;
  }

  final bool authorized = await authorizeSensitiveAction(
    context,
    reason: cancelling ? 'Confirm cancel' : 'Confirm speed up',
    title: cancelling ? 'Confirm cancel' : 'Confirm speed up',
    confirmLabel: cancelling ? 'Cancel transfer' : 'Speed up',
    icon: cancelling ? Icons.cancel_rounded : Icons.rocket_launch_rounded,
  );
  if (!authorized || !context.mounted) {
    return;
  }

  final SendController controller = SendController(
    identity: identity,
    network: network,
    address: ownAddress,
  );

  // The activity entry records the signed amount net of the fee, so the value
  // that actually left the account is the total minus what the sender paid.
  final BigInt outgoing =
      cancelling ? BigInt.zero : original.amount.abs() - original.fee;
  final String recipient = cancelling ? ownAddress : original.counterparty;

  final ({BigInt baseFee, BigInt maxPriorityFeePerGas, BigInt gasLimit})? quote =
      await controller.prepare(to: recipient, value: outgoing);
  if (quote == null) {
    controller.dispose();
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Could not reach ${network.name} to price the replacement.',
        icon: Icons.cloud_off_rounded,
      );
    }
    return;
  }

  if (!context.mounted) {
    controller.dispose();
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ChangeNotifierProvider<SendController>.value(
      value: controller,
      child: TransferProgressDialog(
        to: recipient,
        value: outgoing,
        nonceOverride: nonce,
        maxPriorityFeePerGas:
            FeePreset.fast.tipFor(quote.maxPriorityFeePerGas),
        maxFeePerGas:
            FeePreset.fast.capFor(quote.baseFee, quote.maxPriorityFeePerGas),
        gasLimit: quote.gasLimit,
      ),
    ),
  );

  final bool replaced = controller.txHash != null;
  final String? error = controller.error;
  controller.dispose();

  if (!context.mounted) {
    return;
  }

  if (replaced) {
    await context.read<WalletController>().refresh();
    if (context.mounted) {
      showAppSnackBar(
        context,
        cancelling
            ? 'Replacement submitted — the original can no longer confirm.'
            : 'Faster replacement submitted.',
        icon: Icons.check_circle_outline_rounded,
      );
    }
  } else {
    showAppSnackBar(
      context,
      error ?? 'The replacement could not be sent. Nothing changed.',
      icon: Icons.error_outline_rounded,
    );
  }
}

/// The replacements offered for [original] on [network].
///
/// Both need a known nonce on a chain the wallet can sign for. A speed-up is
/// only offered for a plain native transfer: the calldata of a token transfer
/// is not recoverable from the history API, and a replacement that changes the
/// payload is rejected anyway.
List<ReplacementKind> replacementKindsFor({
  required ChainTransaction original,
  required NetworkConfig network,
  required List<TokenBalance> tokens,
}) {
  if (original.isIncoming || original.confirmed || original.failed) {
    return const <ReplacementKind>[];
  }
  final int? nonce = original.nonce;
  if (nonce == null || !network.canSign) {
    return const <ReplacementKind>[];
  }

  final bool isTokenTransfer = tokens.any(
    (TokenBalance token) =>
        token.contractAddress.toLowerCase() == original.counterparty.toLowerCase(),
  );

  return <ReplacementKind>[
    if (!isTokenTransfer) ReplacementKind.speedUp,
    ReplacementKind.cancel,
  ];
}
