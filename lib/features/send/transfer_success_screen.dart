import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/explorer.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/units.dart';
import '../../data/networks/network_config.dart';

/// Full-screen confirmation shown once a transfer has been accepted by the
/// node. Replaces the send form so "Done" returns straight to the wallet.
class TransferSuccessScreen extends StatelessWidget {
  const TransferSuccessScreen({
    super.key,
    required this.network,
    required this.hash,
    required this.confirmed,
    required this.recipient,
    required this.amount,
    required this.amountDecimals,
    required this.amountSymbol,
  });

  final NetworkConfig network;
  final String hash;

  /// `true` when the transaction is already mined, `false` while pending.
  final bool confirmed;

  /// The address the user typed (the recipient, not the token contract).
  final String recipient;

  final BigInt amount;
  final int amountDecimals;
  final String amountSymbol;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final ColorScheme scheme = theme.colorScheme;
    final AppSemanticColors semantic = theme.semanticColors;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Transfer'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 24),
                      _SuccessMark(color: semantic.positive),
                      const SizedBox(height: 24),
                      Text(
                        confirmed ? 'Transfer confirmed' : 'Transfer sent',
                        textAlign: TextAlign.center,
                        style: text.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        confirmed
                            ? 'The funds left your wallet and the transaction '
                                'is mined.'
                            : 'The transaction was accepted and will confirm '
                                'shortly. You can follow it on the explorer.',
                        textAlign: TextAlign.center,
                        style: text.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 26),
                      Card(
                        color: scheme.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: <Widget>[
                              _Row(
                                label: 'Amount',
                                value: Units.formatWithSymbol(
                                  amount,
                                  amountDecimals,
                                  amountSymbol,
                                  maxDecimals: 8,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _Row(
                                label: 'To',
                                value: AppFormat.shortAddress(recipient),
                              ),
                              const SizedBox(height: 14),
                              _Row(label: 'Network', value: network.name),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _HashCard(hash: hash, network: network),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    openExplorer(context, network.explorerTx(hash)),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('View on explorer'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated circle with a check, so a fresh confirmation reads as an event.
class _SuccessMark extends StatelessWidget {
  const _SuccessMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (BuildContext context, double scale, Widget? child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check_rounded, color: color, size: 54),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Text(
          label,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _HashCard extends StatelessWidget {
  const _HashCard({required this.hash, required this.network});

  final String hash;
  final NetworkConfig network;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Transaction',
                    style: text.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    hash,
                    maxLines: 2,
                    style: text.bodySmall?.copyWith(height: 1.35),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy transaction hash',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: hash));
                if (context.mounted) {
                  showAppSnackBar(
                    context,
                    'Transaction hash copied',
                    icon: Icons.copy_rounded,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
