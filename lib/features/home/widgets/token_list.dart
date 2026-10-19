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
    this.onTokenLongPress,
    this.isDimmed,
    this.hidden = false,
  });

  final List<TokenBalance> tokens;
  final AppCurrency currency;

  /// Opens the send flow for the tapped token, when provided.
  final ValueChanged<TokenBalance>? onTokenTap;

  /// Long-press on a row, for the hide / unhide action.
  final ValueChanged<TokenBalance>? onTokenLongPress;

  /// Rows the user hid, drawn faded while they are being shown.
  final bool Function(TokenBalance token)? isDimmed;

  /// Privacy mode: balances render as dots.
  final bool hidden;

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
              hidden: hidden,
              text: text,
              scheme: scheme,
              dimmed: isDimmed?.call(tokens[i]) ?? false,
              onTap: onTokenTap == null
                  ? null
                  : () => onTokenTap!(tokens[i]),
              onLongPress: onTokenLongPress == null
                  ? null
                  : () => onTokenLongPress!(tokens[i]),
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
    required this.hidden,
    required this.text,
    required this.scheme,
    this.dimmed = false,
    this.onTap,
    this.onLongPress,
  });

  final TokenBalance token;
  final AppCurrency currency;
  final bool hidden;
  final TextTheme text;
  final ColorScheme scheme;
  final bool dimmed;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

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
                hidden ? '••••' : token.amountLabel,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (value != null)
                Text(
                  hidden ? '••••' : AppFormat.fiat(value, currency),
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

    final Widget shown = dimmed ? Opacity(opacity: 0.45, child: row) : row;
    if (onTap == null && onLongPress == null) {
      return shown;
    }
    return InkWell(onTap: onTap, onLongPress: onLongPress, child: shown);
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
