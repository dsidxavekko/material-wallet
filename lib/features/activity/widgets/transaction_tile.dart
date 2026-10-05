import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/units.dart';
import '../../../data/networks/chain_models.dart';
import '../../../data/networks/network_config.dart';

/// Activity feed row for a single on-chain transaction.
///
/// Tapping the row (or the link icon) opens the transaction in the network's
/// block explorer.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.network,
    required this.currency,
    this.price,
    this.onExplorer,
    this.counterpartyLabel,
  });

  final ChainTransaction transaction;
  final NetworkConfig network;
  final AppCurrency currency;
  final CoinPrice? price;
  final VoidCallback? onExplorer;

  /// Address-book label for the counterparty, when one is saved.
  final String? counterpartyLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppSemanticColors semantic = theme.semanticColors;
    final TextTheme text = theme.textTheme;

    final Color accent = switch (true) {
      _ when transaction.failed => scheme.error,
      _ when transaction.isIncoming => semantic.positive,
      _ => scheme.primary,
    };

    final String? fiat = price == null
        ? null
        : AppFormat.fiat(
            Units.toDouble(transaction.amount.abs(), network.decimals) *
                price!.usd,
            currency,
          );

    return InkWell(
      onTap: onExplorer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                transaction.isIncoming
                    ? Icons.south_west_rounded
                    : Icons.north_east_rounded,
                color: accent,
                size: 21,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          '${transaction.isIncoming ? 'Received' : 'Sent'} '
                          '${network.symbol}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (!transaction.confirmed || transaction.failed) ...[
                        const SizedBox(width: 8),
                        _StatusChip(
                          label: transaction.failed ? 'Failed' : 'Pending',
                          failed: transaction.failed,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${AppFormat.relativeTime(transaction.timestamp)} · '
                    '${counterpartyLabel ?? AppFormat.shortAddress(transaction.counterparty, head: 6, tail: 4)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  transaction.amountLabel(network),
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: transaction.amount.isNegative
                        ? scheme.onSurface
                        : semantic.positive,
                  ),
                ),
                if (fiat != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    fiat,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
            const SizedBox(width: 2),
            IconButton(
              tooltip: 'View on explorer',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              color: scheme.onSurfaceVariant,
              onPressed: onExplorer,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.failed});

  final String label;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color background =
        failed ? scheme.errorContainer : scheme.tertiaryContainer;
    final Color foreground =
        failed ? scheme.onErrorContainer : scheme.onTertiaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
