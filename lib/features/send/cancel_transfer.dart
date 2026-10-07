import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../data/networks/network_config.dart';
import '../../data/wallet/seed_vault.dart';
import '../../shared/widgets/pin_confirm_dialog.dart';
import '../../state/send_controller.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_identity_controller.dart';
import 'widgets/transfer_progress_dialog.dart';

/// Replaces a stuck outgoing transaction with a zero-value transfer to the
/// wallet's own address that reuses the same [nonce].
///
/// A node only keeps one transaction per nonce, so once the replacement is
/// mined the original can never execute. Uses the fastest fee preset so the
/// replacement outbids the transaction it is replacing.
///
// ponytail: bumps the tip but does not compare against the stuck tx's own fee
// (the history API does not expose it), so a transaction already priced above
// the current fast preset will not be replaced.
Future<void> showCancelTransfer(
  BuildContext context, {
  required NetworkConfig network,
  required String address,
  required int nonce,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.cancel_rounded),
      title: const Text('Cancel this transfer?'),
      content: Text(
        'This sends 0 ${network.symbol} to yourself and reuses the pending '
        'transaction\'s nonce, so it can never confirm. It only works while '
        'the transaction is still pending.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Cancel transfer'),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false) || !context.mounted) {
    return;
  }

  final WalletIdentityController identity =
      context.read<WalletIdentityController>();
  final String? pin = await PinConfirmDialog.show(
    context,
    title: 'Confirm cancel',
    confirmLabel: 'Cancel transfer',
    icon: Icons.cancel_rounded,
  );
  if (pin == null || !context.mounted) {
    return;
  }
  try {
    await identity.verifyPin(pin);
  } on SeedVaultException catch (error) {
    if (context.mounted) {
      showAppSnackBar(context, error.message, icon: Icons.lock_outline_rounded);
    }
    return;
  }
  if (!context.mounted) {
    return;
  }

  final SendController controller = SendController(
    identity: identity,
    network: network,
    address: address,
  );

  final ({BigInt baseFee, BigInt maxPriorityFeePerGas, BigInt gasLimit})? quote =
      await controller.prepare(to: address, value: BigInt.zero);
  if (quote == null) {
    controller.dispose();
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Could not reach ${network.name} to price the cancel.',
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
        to: address,
        value: BigInt.zero,
        nonceOverride: nonce,
        maxPriorityFeePerGas:
            FeePreset.fast.tipFor(quote.maxPriorityFeePerGas),
        maxFeePerGas:
            FeePreset.fast.capFor(quote.baseFee, quote.maxPriorityFeePerGas),
        gasLimit: quote.gasLimit,
      ),
    ),
  );

  final bool cancelled = controller.txHash != null;
  final String? error = controller.error;
  controller.dispose();

  if (!context.mounted) {
    return;
  }

  if (cancelled) {
    await context.read<WalletController>().refresh();
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Replacement submitted — the original can no longer confirm.',
        icon: Icons.check_circle_outline_rounded,
      );
    }
  } else {
    showAppSnackBar(
      context,
      error ?? 'The cancel could not be sent. Nothing changed.',
      icon: Icons.error_outline_rounded,
    );
  }
}
