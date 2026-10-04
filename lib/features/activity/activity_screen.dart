import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/explorer.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/units.dart';
import '../../data/networks/chain_models.dart';
import '../../shared/widgets/empty_state.dart';
import '../../state/settings_controller.dart';
import '../../state/wallet_controller.dart';
import '../home/widgets/state_cards.dart';
import 'widgets/transaction_tile.dart';

/// Filters available in the activity feed.
enum ActivityFilter {
  all('All'),
  sent('Sent'),
  received('Received');

  const ActivityFilter(this.label);

  final String label;
}

/// Live transaction history for the active network, grouped by day.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  ActivityFilter _filter = ActivityFilter.all;

  @override
  Widget build(BuildContext context) {
    final WalletController wallet = context.watch<WalletController>();
    final AppCurrency currency =
        context.select<SettingsController, AppCurrency>((s) => s.currency);
    final AccountSnapshot? snapshot = wallet.snapshot;

    final List<ChainTransaction> all =
        snapshot?.transactions ?? const <ChainTransaction>[];
    final List<ChainTransaction> filtered = switch (_filter) {
      ActivityFilter.all => all,
      ActivityFilter.sent =>
        all.where((t) => !t.isIncoming).toList(growable: false),
      ActivityFilter.received =>
        all.where((t) => t.isIncoming).toList(growable: false),
    };
    final List<Object> items = _groupedByDay(filtered);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: RefreshIndicator(
        onRefresh: wallet.refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: <Widget>[
            if (wallet.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: ErrorCard(
                  message: wallet.error!,
                  onRetry: wallet.refresh,
                ),
              ),
            if (snapshot == null)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: LoadingCard(),
              )
            else ...<Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: _FlowSummary(snapshot: snapshot, currency: currency),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ActivityFilter.values
                        .map(
                          (filter) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(filter.label),
                              selected: _filter == filter,
                              onSelected: (_) =>
                                  setState(() => _filter = filter),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
              if (items.isEmpty)
                const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  message: 'On-chain activity for this network shows up here.',
                )
              else
                for (final Object item in items)
                  if (item is ChainTransaction)
                    TransactionTile(
                      transaction: item,
                      network: snapshot.network,
                      currency: currency,
                      price: snapshot.price,
                      onExplorer: () => openExplorer(
                        context,
                        snapshot.network.explorerTx(item.hash),
                      ),
                    )
                  else if (item is String)
                    _DayHeader(label: item),
            ],
          ],
        ),
      ),
    );
  }

  /// Flattens the feed into day headers and transactions.
  List<Object> _groupedByDay(List<ChainTransaction> entries) {
    final List<Object> items = <Object>[];
    String? currentLabel;
    for (final ChainTransaction entry in entries) {
      final String label = AppFormat.dayLabel(entry.timestamp);
      if (label != currentLabel) {
        items.add(label);
        currentLabel = label;
      }
      items.add(entry);
    }
    return items;
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

/// Totals for the transactions currently loaded from the API.
class _FlowSummary extends StatelessWidget {
  const _FlowSummary({required this.snapshot, required this.currency});

  final AccountSnapshot snapshot;
  final AppCurrency currency;

  @override
  Widget build(BuildContext context) {
    BigInt inflow = BigInt.zero;
    BigInt outflow = BigInt.zero;

    for (final ChainTransaction tx in snapshot.transactions) {
      if (tx.failed) {
        continue;
      }
      if (tx.amount.isNegative) {
        outflow += tx.amount.abs();
      } else {
        inflow += tx.amount;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _SummaryColumn(
                label: 'Money in',
                value: _label(inflow),
                icon: Icons.south_west_rounded,
              ),
            ),
            Container(
              width: 1,
              height: 44,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: _SummaryColumn(
                label: 'Money out',
                value: _label(outflow),
                icon: Icons.north_east_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fiat value when a market price is available, native units otherwise.
  String _label(BigInt raw) {
    final CoinPrice? price = snapshot.price;
    if (price == null) {
      return Units.formatWithSymbol(
        raw,
        snapshot.network.decimals,
        snapshot.network.symbol,
        maxDecimals: 6,
      );
    }
    return AppFormat.fiat(
      Units.toDouble(raw, snapshot.network.decimals) * price.usd,
      currency,
    );
  }
}

class _SummaryColumn extends StatelessWidget {
  const _SummaryColumn({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
