import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../core/utils/units.dart';
import '../../data/networks/chain_models.dart';
import '../../data/networks/network_config.dart';
import '../../data/wallet/bitcoin_signer.dart';
import '../../state/send_controller.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_identity_controller.dart';
import '../lock/sensitive_auth.dart';
import 'widgets/transfer_progress_dialog.dart';

/// Replaces a stuck outgoing Bitcoin transfer with the same payment at a higher
/// fee (BIP-125).
///
/// The replacement spends the same inputs and pays the same recipients; the
/// extra fee is taken from the wallet's own change. When that is impossible —
/// the original never signalled RBF, it has no change, the change is too small —
/// the user gets the reason instead of a transaction the network would reject.
Future<void> showBitcoinSpeedUp(
  BuildContext context, {
  required NetworkConfig network,
  required ChainTransaction original,
}) async {
  final WalletIdentityController identity = context
      .read<WalletIdentityController>();
  final String? ownAddress = identity.addressFor(network);
  if (ownAddress == null) {
    return;
  }

  final SendController controller = SendController(
    identity: identity,
    network: network,
    address: ownAddress,
  );

  // The plan is read from the live mempool entry, so it takes a moment.
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Checking the pending transfer…')),
            ],
          ),
        ),
      ),
    ),
  );
  final ({BitcoinPlan? plan, String? refusal}) prepared = await controller
      .prepareBitcoinReplacement(txid: original.hash);
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  final BitcoinPlan? plan = prepared.plan;
  if (plan == null || !context.mounted) {
    controller.dispose();
    if (context.mounted) {
      showAppSnackBar(
        context,
        prepared.refusal ?? 'Could not prepare a faster copy.',
        icon: Icons.error_outline_rounded,
      );
    }
    return;
  }

  String coins(BigInt sats) =>
      Units.formatWithSymbol(sats, network.decimals, network.symbol);

  final BigInt extra = plan.fee - plan.originalFee!;
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.rocket_launch_rounded),
      title: const Text('Speed this transfer up?'),
      content: Text(
        'This re-sends the same payment with a higher fee, taken from your '
        'change. Exactly one of the two can confirm.\n\n'
        'Fee now: ${coins(plan.originalFee!)}\n'
        'New fee: ${coins(plan.fee)} (~${plan.feeRate} sat/vB)\n'
        'Extra cost: ${coins(extra)}',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Speed up'),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false) || !context.mounted) {
    controller.dispose();
    return;
  }

  final bool authorized = await authorizeSensitiveAction(
    context,
    reason: 'Confirm speed up',
    title: 'Confirm speed up',
    confirmLabel: 'Speed up',
    icon: Icons.rocket_launch_rounded,
  );
  if (!authorized || !context.mounted) {
    controller.dispose();
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ChangeNotifierProvider<SendController>.value(
      value: controller,
      child: TransferProgressDialog(
        to: original.counterparty,
        value: plan.amount,
        bitcoinPlan: plan,
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
        'Faster replacement submitted.',
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
