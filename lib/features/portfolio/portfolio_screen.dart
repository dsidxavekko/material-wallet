import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/units.dart';
import '../../data/networks/network_config.dart';
import '../../state/hidden_tokens_controller.dart';
import '../../state/portfolio_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/wallet_identity_controller.dart';
import '../home/widgets/state_cards.dart';

/// The account's holdings on every mainnet in one list, largest first.
///
/// Replaces visiting each network in turn to add up a total. Tapping a row
/// switches the wallet to that network.
class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final WalletIdentityController identity =
        context.read<WalletIdentityController>();
    return ChangeNotifierProvider<PortfolioController>(
      create: (_) => PortfolioController(
        addressFor: identity.addressFor,
        isTokenHidden: context.read<HiddenTokensController>().isHidden,
      )..load(),
      child: const _PortfolioView(),
    );
  }
}

class _PortfolioView extends StatelessWidget {
  const _PortfolioView();

  @override
  Widget build(BuildContext context) {
    final PortfolioController portfolio = context.watch<PortfolioController>();
    final SettingsController settings = context.watch<SettingsController>();
    final AppCurrency currency = settings.currency;
    final bool hidden = settings.hideBalances;
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final double? total = portfolio.totalUsd;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed:
                portfolio.loading ? null : () => portfolio.load(force: true),
            icon: portfolio.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => portfolio.load(force: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Total across networks',
                      style: text.labelLarge
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      total == null
                          ? (portfolio.loading ? 'Loading…' : '—')
                          : hidden
                              ? '••••'
                              : AppFormat.fiat(total, currency),
                      style: text.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (portfolio.incomplete) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        'Some networks could not be read, so this total may '
                        'be too low.',
                        style: text.bodySmall?.copyWith(color: scheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (portfolio.entries.isEmpty && portfolio.loading)
              const LoadingCard()
            else
              for (final PortfolioEntry entry in portfolio.entries)
                _EntryTile(entry: entry, currency: currency, hidden: hidden),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.currency,
    required this.hidden,
  });

  final PortfolioEntry entry;
  final AppCurrency currency;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final NetworkConfig network = entry.network;
    final double? value = entry.totalUsd;

    final String subtitle;
    if (entry.failed) {
      subtitle = entry.error ?? 'Unavailable';
    } else {
      final String native = hidden
          ? '••••'
          : Units.formatWithSymbol(
              entry.balance!,
              network.decimals,
              network.symbol,
              maxDecimals: 6,
            );
      final int tokenCount = entry.visibleTokens.length;
      subtitle = tokenCount == 0
          ? native
          : '$native · $tokenCount token${tokenCount == 1 ? '' : 's'}';
    }

    return Card(
      child: ListTile(
        onTap: () {
          context.read<SettingsController>().setNetwork(network);
          Navigator.of(context).pop();
        },
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: network.color.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Text(
            network.symbol.length > 3
                ? network.symbol.substring(0, 3)
                : network.symbol,
            style: text.labelSmall?.copyWith(
              color: network.color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Text(
          network.name,
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: entry.failed ? TextStyle(color: scheme.error) : null,
        ),
        trailing: entry.failed
            ? Icon(Icons.error_outline_rounded, color: scheme.error)
            : Text(
                value == null
                    ? '—'
                    : hidden
                        ? '••••'
                        : AppFormat.fiat(value, currency),
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}
