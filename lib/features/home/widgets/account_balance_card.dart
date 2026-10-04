import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/networks/chain_models.dart';
import '../../../shared/widgets/hidden_amount.dart';
import '../../../shared/widgets/sparkline.dart';

/// Hero card showing the live balance of the selected network.
class AccountBalanceCard extends StatelessWidget {
  const AccountBalanceCard({
    super.key,
    required this.snapshot,
    required this.currency,
    required this.hidden,
    required this.onToggleVisibility,
    required this.onCurrencyTap,
    required this.onRetryPrice,
  });

  final AccountSnapshot snapshot;
  final AppCurrency currency;
  final bool hidden;
  final VoidCallback onToggleVisibility;

  /// Opens the display-currency picker (tapping the currency chip).
  final VoidCallback onCurrencyTap;

  /// Re-fetches the market price after a failed price lookup.
  final VoidCallback onRetryPrice;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final CoinPrice? price = snapshot.price;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[scheme.primary, scheme.tertiary],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  snapshot.network.name,
                  style: text.labelLarge?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _CurrencyChip(code: currency.code, onTap: onCurrencyTap),
              const SizedBox(width: 2),
              IconButton(
                onPressed: onToggleVisibility,
                visualDensity: VisualDensity.compact,
                tooltip: hidden ? 'Show balance' : 'Hide balance',
                icon: Icon(
                  hidden
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: scheme.onPrimary,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: HiddenAmount(
                  text: snapshot.nativeLabel,
                  hidden: hidden,
                  style: text.displaySmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                snapshot.network.symbol,
                style: text.titleMedium?.copyWith(
                  color: scheme.onPrimary.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (price != null)
            _FiatRow(
              price: price,
              fiatBalance: snapshot.fiatBalance!,
              currency: currency,
              symbol: snapshot.network.symbol,
              hidden: hidden,
            )
          else if (snapshot.network.isTestnet)
            Text(
              'Testnet — no market price',
              style: text.bodySmall?.copyWith(
                color: scheme.onPrimary.withValues(alpha: 0.8),
              ),
            )
          else
            _PriceUnavailable(onRetry: onRetryPrice),
          if (snapshot.chart.length > 1) ...<Widget>[
            const SizedBox(height: 14),
            Sparkline(
              values: snapshot.chart,
              color: scheme.onPrimary,
              height: 46,
              strokeWidth: 2,
              filled: false,
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact currency selector shown on the hero card, so switching fiat
/// currency is one tap away (like Google Wallet) instead of buried in
/// settings.
class _CurrencyChip extends StatelessWidget {
  const _CurrencyChip({required this.code, required this.onTap});

  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
        decoration: BoxDecoration(
          color: scheme.onPrimary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              code,
              style: text.labelMedium?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: scheme.onPrimary,
            ),
          ],
        ),
      ),
    );
  }
}

class _FiatRow extends StatelessWidget {
  const _FiatRow({
    required this.price,
    required this.fiatBalance,
    required this.currency,
    required this.symbol,
    required this.hidden,
  });

  final CoinPrice price;
  final double fiatBalance;
  final AppCurrency currency;
  final String symbol;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final bool up = price.change24h >= 0;

    return Row(
      children: <Widget>[
        HiddenAmount(
          text: AppFormat.fiat(fiatBalance, currency),
          hidden: hidden,
          style: text.titleMedium?.copyWith(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.onPrimary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                up
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 14,
                color: scheme.onPrimary,
              ),
              const SizedBox(width: 3),
              Text(
                AppFormat.percent(price.change24h),
                style: text.labelMedium?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Text(
          '1 $symbol = ${AppFormat.fiat(price.usd, currency)}',
          style: text.bodySmall?.copyWith(
            color: scheme.onPrimary.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

/// Shown on a mainnet hero card when the price could not be loaded.
///
/// Unlike a testnet (which simply has no market), this is a temporary failure,
/// so we offer a one-tap retry instead of leaving the user stuck.
class _PriceUnavailable extends StatelessWidget {
  const _PriceUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Color foreground = scheme.onPrimary.withValues(alpha: 0.9);

    return Row(
      children: <Widget>[
        Icon(Icons.cloud_off_rounded, size: 16, color: foreground),
        const SizedBox(width: 8),
        Text(
          'Price temporarily unavailable',
          style: text.bodySmall?.copyWith(color: foreground),
        ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            foregroundColor: scheme.onPrimary,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}
