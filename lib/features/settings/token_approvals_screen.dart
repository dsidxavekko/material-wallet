import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/app_log.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../data/networks/chain_api.dart';
import '../../data/networks/chain_models.dart';
import '../../data/networks/network_config.dart';
import '../../data/wallet/evm_signer.dart';
import '../../shared/widgets/empty_state.dart';
import '../../state/send_controller.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_identity_controller.dart';
import '../lock/sensitive_auth.dart';
import '../send/widgets/transfer_progress_dialog.dart';

/// ERC-20 approvals this wallet has granted, with a way to revoke each one.
///
/// An approval is standing permission: once a contract holds it, it can move
/// tokens out at any moment without asking again, and no amount of waiting
/// makes it expire. After signing an `approve` on a malicious site the only
/// remedy is to overwrite the allowance with zero — which is what this screen
/// is for.
class TokenApprovalsScreen extends StatefulWidget {
  const TokenApprovalsScreen({super.key, this.chainApi});

  /// Injectable so tests do not reach the network.
  final ChainApi? chainApi;

  @override
  State<TokenApprovalsScreen> createState() => _TokenApprovalsScreenState();
}

class _TokenApprovalsScreenState extends State<TokenApprovalsScreen> {
  late final ChainApi _api = widget.chainApi ?? ChainApi();

  List<TokenApproval>? _approvals;
  String? _error;
  String? _busySpender;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final WalletController wallet = context.read<WalletController>();
    final String? address = wallet.address;
    if (address == null) {
      return;
    }

    setState(() {
      _approvals = null;
      _error = null;
    });

    try {
      final List<TokenApproval> approvals =
          await _api.fetchTokenApprovals(wallet.network, address);
      if (mounted) {
        setState(() => _approvals = approvals);
      }
    } catch (error, stackTrace) {
      // The API already degrades to an empty list; this only catches the
      // unexpected, and must not leave the screen spinning forever.
      AppLog.warning('Could not load token approvals', error, stackTrace);
      if (mounted) {
        setState(() => _error = 'Could not load your approvals.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<TokenApproval>? approvals = _approvals;

    return Scaffold(
      appBar: AppBar(title: const Text('Token approvals')),
      body: switch ((_error, approvals)) {
        (final String error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Approvals unavailable',
            message: '$error Pull down to try again.',
          ),
        (_, null) => const Center(child: CircularProgressIndicator()),
        (_, final List<TokenApproval> list) when list.isEmpty => const EmptyState(
            icon: Icons.verified_user_outlined,
            title: 'No active approvals',
            message:
                'No contract on this network is allowed to spend your tokens. '
                'A scam site that asked for approval would show up here.',
          ),
        (_, final List<TokenApproval> list) => RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) =>
                  _ApprovalCard(
                approval: list[index],
                busy: _busySpender == list[index].spender,
                onRevoke: () => _revoke(list[index]),
              ),
            ),
          ),
      },
    );
  }

  /// Confirms, signs and broadcasts `approve(spender, 0)` for [approval].
  Future<void> _revoke(TokenApproval approval) async {
    final WalletController wallet = context.read<WalletController>();
    final NetworkConfig network = wallet.network;
    final String? address = context.read<WalletIdentityController>().addressFor(network);
    if (address == null) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.block_rounded),
        title: Text('Revoke ${approval.symbol} approval?'),
        content: Text(
          'This sets the allowance for '
          '${AppFormat.shortAddress(approval.spender)} to zero, so it can no '
          'longer move your ${approval.symbol}. Contracts that need the '
          'approval will stop working until you grant it again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) {
      return;
    }

    final bool authorized = await authorizeSensitiveAction(
      context,
      reason: 'Revoke approval',
      title: 'Confirm revoke',
      confirmLabel: 'Revoke',
      icon: Icons.block_rounded,
    );
    if (!authorized || !mounted) {
      return;
    }

    final SendController controller = SendController(
      identity: context.read<WalletIdentityController>(),
      network: network,
      address: address,
    );

    // Gas for a revoke is bounded by the token contract, and an estimate that
    // fails falls back to 21,000 — which would be too low and get the
    // transaction rejected, so ask for a real figure and refuse without one.
    final ({BigInt baseFee, BigInt maxPriorityFeePerGas, BigInt gasLimit})? quote =
        await controller.prepare(
      to: approval.tokenAddress,
      value: BigInt.zero,
      data: EvmSigner.erc20ApproveData(
        spender: approval.spender,
        amount: BigInt.zero,
      ),
    );
    if (quote == null) {
      controller.dispose();
      if (mounted) {
        showAppSnackBar(
          context,
          'Could not reach ${network.name} to price the revoke.',
          icon: Icons.cloud_off_rounded,
        );
      }
      return;
    }
    if (!mounted) {
      controller.dispose();
      return;
    }

    setState(() => _busySpender = approval.spender);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangeNotifierProvider<SendController>.value(
        value: controller,
        child: TransferProgressDialog(
          to: approval.tokenAddress,
          value: BigInt.zero,
          data: EvmSigner.erc20ApproveData(
            spender: approval.spender,
            amount: BigInt.zero,
          ),
          maxPriorityFeePerGas: quote.maxPriorityFeePerGas,
          // `prepare` returns the base fee and the tip separately; the cap is
          // what the wallet actually commits to, so build it the same way the
          // send flow does for its Normal preset.
          maxFeePerGas:
              FeePreset.normal.capFor(quote.baseFee, quote.maxPriorityFeePerGas),
          gasLimit: quote.gasLimit,
        ),
      ),
    );

    final bool revoked = controller.txHash != null;
    final String? error = controller.error;
    controller.dispose();
    if (!mounted) {
      return;
    }
    setState(() => _busySpender = null);

    if (!revoked) {
      showAppSnackBar(
        context,
        error ?? 'The revoke could not be sent. Nothing changed.',
        icon: Icons.error_outline_rounded,
      );
      return;
    }

    await wallet.refresh();
    if (!mounted) {
      return;
    }
    showAppSnackBar(
      context,
      'Revoke submitted.',
      icon: Icons.check_circle_outline_rounded,
    );
  }
}

/// One approval row: the token, the spender it was granted to, and the action.
class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.approval,
    required this.busy,
    required this.onRevoke,
  });

  final TokenApproval approval;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    approval.symbol,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  approval.amountLabel,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: approval.isUnlimited ? scheme.error : scheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Approved for ${AppFormat.shortAddress(approval.spender)}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (approval.isUnlimited) ...[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded,
                      size: 15, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Unlimited — this contract can move all of it at any time.',
                      style: text.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : onRevoke,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.block_rounded, size: 18),
                label: const Text('Revoke'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
