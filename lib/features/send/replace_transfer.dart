import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../core/utils/units.dart';
import '../../data/models/chain_kind.dart';
import '../../data/networks/chain_models.dart';
import '../../data/networks/network_config.dart';
import '../../state/send_controller.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_identity_controller.dart';
import '../lock/sensitive_auth.dart';
import 'bitcoin_speed_up.dart';
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
  if (network.chain == ChainKind.bitcoin) {
    return showBitcoinSpeedUp(context, network: network, original: original);
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
      title: Text(cancelling ? 'Cancel this transfer?' : 'Speed this transfer up?'),
      content: Text(
        cancelling
            ? 'This sends 0 ${network.symbol} to yourself and reuses the '
                'pending transaction\'s nonce, so it can never confirm. It '
                'only works while the transaction is still pending.'
            : calldata != null
                ? 'This re-sends the identical token transfer to '
                    '${original.counterparty} with a higher fee, reusing the '
                    'pending transaction\'s nonce and calldata. Exactly one '
                    'of the two will confirm.'
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
      await controller.prepare(to: recipient, value: outgoing, data: calldata);
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
/// On EVM both need a known nonce on a chain the wallet can sign for. A speed-up is
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
  // Bitcoin's RBF rebuilds the transaction from its own inputs rather than a
  // nonce: a speed-up (never a cancel) is offered only when the transaction
  // signalled BIP-125, since the network rejects a replacement otherwise.
  if (network.chain == ChainKind.bitcoin) {
    return network.canSign && original.replaceable == true
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
