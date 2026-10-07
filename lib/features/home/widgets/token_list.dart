import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/networks/chain_models.dart';
import '../../../shared/widgets/coin_avatar.dart';

/// ERC-20 holdings for the active account.
class TokenList extends StatelessWidget {
  const TokenList({
    super.key,
    required this.tokens,
    required this.currency,
    this.onTokenTap,
  });

  final List<TokenBalance> tokens;
  final AppCurrency currency;

  /// Opens the send flow for the tapped token, when provided.
  final ValueChanged<TokenBalance>? onTokenTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      child: Column(
        children: <Widget>[
          for (int i = 0; i < tokens.length; i++) ...<Widget>[
            if (i > 0)
              Divider(height: 1, indent: 16, endIndent: 16, color: scheme.outlineVariant),
            _TokenTile(
              token: tokens[i],
              currency: currency,
              text: text,
              scheme: scheme,
              onTap: onTokenTap == null
                  ? null
                  : () => onTokenTap!(tokens[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _TokenTile extends StatelessWidget {
  const _TokenTile({
    required this.token,
    required this.currency,
    required this.text,
    required this.scheme,
    this.onTap,
  });

  final TokenBalance token;
  final AppCurrency currency;
  final TextTheme text;
  final ColorScheme scheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double? value = token.usdValue;

    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          CoinAvatar(
            symbol: token.symbol,
            color: _colorFor(token.symbol),
            size: 40,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  token.symbol,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (token.name.isNotEmpty)
                  Text(
                    token.name,
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
                token.amountLabel,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (value != null)
                Text(
                  AppFormat.fiat(value, currency),
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          if (onTap != null) ...<Widget>[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return row;
    }
    return InkWell(onTap: onTap, child: row);
  }
}

/// Stable pseudo-random brand-ish colour derived from the token ticker, so the
/// same token always gets the same avatar without bundling logo assets.
Color _colorFor(String symbol) {
  final int hash = symbol.codeUnits.fold<int>(
    0,
    (int acc, int unit) => (acc * 31 + unit) & 0x7fffffff,
  );
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.52, 0.46).toColor();
}
