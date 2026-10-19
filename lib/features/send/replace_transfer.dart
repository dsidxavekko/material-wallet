import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../core/utils/units.dart';
import '../../data/models/chain_kind.dart';
import '../../data/networks/chain_models.dart';
import '../../data/networks/network_config.dart';
import '../../data/wallet/bitcoin_signer.dart';
import '../../state/send_controller.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_identity_controller.dart';
import '../lock/sensitive_auth.dart';
import 'widgets/transfer_progress_dialog.dart';
import '../../l10n/l10n.dart';
import '../../l10n/messages.dart';

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
/// The replacement is priced from the stuck transaction's own fee cap (plus
/// the 10% a node demands) when Blockscout exposes it, so a transaction
/// already priced above the current fast preset can still be rescued.
Future<void> showReplaceTransfer(
  BuildContext context, {
  required NetworkConfig network,
  required int? nonce,
  required ReplacementKind kind,
  required ChainTransaction original,
}) async {
  if (!context.read<WalletIdentityController>().canSign) {
    showAppSnackBar(
      context,
      context.l10n.aWatchOnlyWalletCannot2,
      icon: Icons.visibility_outlined,
    );
    return;
  }
  if (network.chain == ChainKind.bitcoin) {
    return _showBitcoinSpeedUp(context, network: network, original: original);
  }
  if (nonce == null) {
    return;
  }
  final bool cancelling = kind == ReplacementKind.cancel;
  final WalletIdentityController identity =
      context.read<WalletIdentityController>();
  final String? ownAddress = identity.addressFor(network);
  if (ownAddress == null) {
    return;
  }

  // A speed-up of a token transfer reuses the original's calldata byte for
  // byte; a native transfer (and the cancel) carries none.
  final Uint8List? calldata = cancelling ? null : speedUpCalldata(original);

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        cancelling ? Icons.cancel_rounded : Icons.rocket_launch_rounded,
      ),
      title: Text(cancelling ? context.l10n.cancelThisTransfer : context.l10n.speedThisTransferUp),
      content: Text(
        cancelling
            ? context.l10n.thisSends0ToYourself(network.symbol)
            : calldata != null
                ? context.l10n.thisReSendsTheIdentical(original.counterparty)
                : context.l10n.thisSendsToAgainWith(Units.formatWithSymbol(original.amount.abs(), network.decimals, network.symbol), original.counterparty),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(context.l10n.keepIt),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(cancelling ? context.l10n.cancelTransfer : context.l10n.speedUp),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false) || !context.mounted) {
    return;
  }

  final bool authorized = await authorizeSensitiveAction(
    context,
    reason: cancelling ? context.l10n.confirmCancel : context.l10n.confirmSpeedUp,
    title: cancelling ? context.l10n.confirmCancel : context.l10n.confirmSpeedUp,
    confirmLabel: cancelling ? context.l10n.cancelTransfer : context.l10n.speedUp,
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
      await controller.prepare(to: recipient, value: outgoing, data: calldata);
  if (quote == null) {
    controller.dispose();
    if (context.mounted) {
      showAppSnackBar(
        context,
        context.l10n.couldNotReachToPrice2(network.name),
        icon: Icons.cloud_off_rounded,
      );
    }
    return;
  }

  if (!context.mounted) {
    controller.dispose();
    return;
  }

  final ({BigInt maxFeePerGas, BigInt maxPriorityFeePerGas}) fee =
      replacementFeeFor(original: original, quote: quote);

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ChangeNotifierProvider<SendController>.value(
      value: controller,
      child: TransferProgressDialog(
        to: recipient,
        value: outgoing,
        nonceOverride: nonce,
        maxPriorityFeePerGas: fee.maxPriorityFeePerGas,
        maxFeePerGas: fee.maxFeePerGas,
        gasLimit: quote.gasLimit,
        data: calldata,
      ),
    ),
  );

  final bool replaced = controller.txHash != null;
  final String? error =
      controller.error == null ? null : tr(controller.error!);
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
            ? context.l10n.replacementSubmittedTheOriginalCan
            : context.l10n.fasterReplacementSubmitted,
        icon: Icons.check_circle_outline_rounded,
      );
    }
  } else {
    showAppSnackBar(
      context,
      error ?? context.l10n.theReplacementCouldNotBe,
      icon: Icons.error_outline_rounded,
    );
  }
}

/// Speeds a pending Bitcoin transfer up with replace-by-fee.
///
/// Rebuilds the same payment from the same coins with a larger fee taken out
/// of the change (BIP-125). The review step shows the old and the new fee, and
/// a transfer that cannot be replaced says why instead of failing quietly.
Future<void> _showBitcoinSpeedUp(
  BuildContext context, {
  required NetworkConfig network,
  required ChainTransaction original,
}) async {
  final WalletIdentityController identity =
      context.read<WalletIdentityController>();
  final String? ownAddress = identity.addressFor(network);
  if (ownAddress == null) {
    return;
  }

  final SendController controller = SendController(
    identity: identity,
    network: network,
    address: ownAddress,
  );

  final ({BitcoinPlan? plan, BigInt? oldFee, String? reason}) prepared =
      await controller.prepareBitcoinSpeedUp(original.hash);
  final BitcoinPlan? plan = prepared.plan;
  if (plan == null || !context.mounted) {
    controller.dispose();
    if (context.mounted) {
      showAppSnackBar(
        context,
        tr(prepared.reason ?? context.l10n.thisTransferCannotBeSped),
        icon: Icons.error_outline_rounded,
      );
    }
    return;
  }

  String sats(BigInt value) =>
      Units.formatWithSymbol(value, network.decimals, network.symbol);

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.rocket_launch_rounded),
      title: Text(context.l10n.speedThisTransferUp),
      content: Text(
        context.l10n.theSamePaymentIsSent(sats(prepared.oldFee ?? BigInt.zero), sats(plan.fee), plan.feeRate),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(context.l10n.keepIt),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(context.l10n.speedUp),
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
    reason: context.l10n.confirmSpeedUp,
    title: context.l10n.confirmSpeedUp,
    confirmLabel: context.l10n.speedUp,
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
        replacesTxid: original.hash,
      ),
    ),
  );

  final bool replaced = controller.txHash != null;
  final String? error =
      controller.error == null ? null : tr(controller.error!);
  controller.dispose();

  if (!context.mounted) {
    return;
  }
  if (replaced) {
    await context.read<WalletController>().refresh();
    if (context.mounted) {
      showAppSnackBar(
        context,
        context.l10n.fasterReplacementSubmitted,
        icon: Icons.check_circle_outline_rounded,
      );
    }
  } else {
    showAppSnackBar(
      context,
      error ?? context.l10n.theReplacementCouldNotBe,
      icon: Icons.error_outline_rounded,
    );
  }
}

/// The replacements offered for [original] on [network].
///
/// Both need a known nonce on a chain the wallet can sign for. A speed-up is
/// offered for a plain native transfer always, and for a token transfer or
/// approval only when the API exposed the original's calldata — a replacement
/// that cannot reproduce the payload byte for byte is rejected by the node
/// anyway.
List<ReplacementKind> replacementKindsFor({
  required ChainTransaction original,
  required NetworkConfig network,
  required List<TokenBalance> tokens,
}) {
  if (original.isIncoming || original.confirmed || original.failed) {
    return const <ReplacementKind>[];
  }
  // Bitcoin replaces by rebuilding the same transfer with a larger fee (RBF).
  // Only speed-up exists there: a cancel would need a fresh coin to pay itself.
  // The planner explains on tap why a transfer that did not signal RBF cannot
  // be replaced.
  if (network.chain == ChainKind.bitcoin) {
    return network.canSign
        ? const <ReplacementKind>[ReplacementKind.speedUp]
        : const <ReplacementKind>[];
  }
  final int? nonce = original.nonce;
  // A nonce-based replacement is an EVM-only mechanic and Solana has no nonces
  // here, so a `canSign` chain would still get a dead action offered.
  if (nonce == null ||
      network.chain != ChainKind.evm ||
      !network.canSign) {
    return const <ReplacementKind>[];
  }

  final bool isTokenTransfer = tokens.any(
    (TokenBalance token) =>
        token.contractAddress.toLowerCase() == original.counterparty.toLowerCase(),
  );

  return <ReplacementKind>[
    if (!isTokenTransfer || speedUpCalldata(original) != null)
      ReplacementKind.speedUp,
    ReplacementKind.cancel,
  ];
}

/// The fees a replacement must carry.
///
/// A node applies the geth replacement rule: the new transaction's fee cap and
/// tip must each be at least 10% above the *original's own* values, not above
/// whatever the current fast preset happens to be. When the history API
/// exposed the original's caps (Blockscout v2 does) the larger of the two
/// candidates wins; without them the fast preset is the best that can be
/// offered.
///
/// Pure so the ≥110% invariant is testable without a network.
({BigInt maxFeePerGas, BigInt maxPriorityFeePerGas}) replacementFeeFor({
  required ChainTransaction original,
  required ({BigInt baseFee, BigInt maxPriorityFeePerGas, BigInt gasLimit})
      quote,
}) {
  final BigInt fastCap =
      FeePreset.fast.capFor(quote.baseFee, quote.maxPriorityFeePerGas);
  final BigInt fastTip =
      FeePreset.fast.tipFor(quote.maxPriorityFeePerGas);

  final BigInt bumpedCap = _bump(original.maxFeePerGas);
  final BigInt bumpedTip = _bump(original.maxPriorityFeePerGas);

  return (
    maxFeePerGas: bumpedCap > fastCap ? bumpedCap : fastCap,
    maxPriorityFeePerGas: bumpedTip > fastTip ? bumpedTip : fastTip,
  );
}

/// [value] raised by the geth replacement percentage (10%), or zero when the
/// original value is unknown — the caller falls back to its own preset then.
BigInt _bump(BigInt? value) => value == null
    ? BigInt.zero
    : value * BigInt.from(11) ~/ BigInt.from(10) + BigInt.one;

/// The original's calldata as signing bytes, or `null` when it carried none
/// (a plain native transfer, cancel, or an API that does not expose
/// `raw_input`).
Uint8List? speedUpCalldata(ChainTransaction original) {
  final String? raw = original.rawInput;
  if (raw == null || raw.length <= 2) {
    return null;
  }
  try {
    return Uint8List.fromList(hex.decode(raw.substring(2)));
  } on FormatException {
    return null;
  }
}
