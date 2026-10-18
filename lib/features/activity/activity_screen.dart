import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/app_log.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/explorer.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/units.dart';
import '../../data/networks/chain_models.dart';
import '../../shared/widgets/empty_state.dart';
import '../../state/contacts_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/tx_notes_controller.dart';
import '../../state/wallet_controller.dart';
import '../home/widgets/state_cards.dart';
import '../send/replace_transfer.dart';
import 'activity_search.dart';
import 'widgets/note_dialog.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WalletController wallet = context.watch<WalletController>();
    final ContactsController contacts = context.watch<ContactsController>();
    final TxNotesController notes = context.watch<TxNotesController>();
    final AppCurrency currency =
        context.select<SettingsController, AppCurrency>((s) => s.currency);
    final bool hidden =
        context.select<SettingsController, bool>((s) => s.hideBalance);
    final AccountSnapshot? snapshot = wallet.snapshot;

    final List<ChainTransaction> all =
        snapshot?.transactions ?? const <ChainTransaction>[];
    final List<ChainTransaction> byDirection = switch (_filter) {
      ActivityFilter.all => all,
      ActivityFilter.sent =>
        all.where((t) => !t.isIncoming).toList(growable: false),
      ActivityFilter.received =>
        all.where((t) => t.isIncoming).toList(growable: false),
    };
    final List<ChainTransaction> filtered = snapshot == null || _query.isEmpty
        ? byDirection
        : byDirection
            .where(
              (ChainTransaction tx) => matchesActivityQuery(
                tx,
                _query,
                network: snapshot.network,
                counterpartyLabel: contacts.labelFor(
                  tx.displayCounterparty,
                  snapshot.network.id,
                ),
                note: notes.noteFor(snapshot.network.id, tx.hash),
              ),
            )
            .toList(growable: false);
    final List<Object> items = _groupedByDay(filtered);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: <Widget>[
          IconButton(
            tooltip: hidden ? 'Show amounts' : 'Hide amounts',
            onPressed: () =>
                context.read<SettingsController>().setHideBalance(!hidden),
            icon: Icon(
              hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Export CSV',
            onPressed: snapshot == null || snapshot.transactions.isEmpty
                ? null
                : () => _exportCsv(context, snapshot, notes),
            icon: const Icon(Icons.file_download_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
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
                child: _FlowSummary(
                  snapshot: snapshot,
                  currency: currency,
                  hidden: hidden,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onChanged: (String value) =>
                      setState(() => _query = value.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search address, label, hash, note or token',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    isDense: true,
                  ),
                ),
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
                EmptyState(
                  icon: _query.isEmpty
                      ? Icons.receipt_long_outlined
                      : Icons.search_off_rounded,
                  title:
                      _query.isEmpty ? 'No transactions yet' : 'No matches',
                  message: _query.isEmpty
                      ? 'On-chain activity for this network shows up here.'
                      : wallet.canLoadMoreActivity
                          ? 'Search covers the activity loaded so far. Load '
                              'more to look further back.'
                          : 'Nothing in this network\'s activity matches '
                              '"$_query".',
                )
              else
                for (final Object item in items)
                  if (item is ChainTransaction)
                    TransactionTile(
                      transaction: item,
                      network: snapshot.network,
                      currency: currency,
                      price: snapshot.price,
                      tokenUsdRate: snapshot.tokenUsdRateFor(item),
                      hidden: hidden,
                      note: notes.noteFor(snapshot.network.id, item.hash),
                      onEditNote: () => editTxNote(
                        context,
                        networkId: snapshot.network.id,
                        hash: item.hash,
                      ),
                      counterpartyLabel: contacts.labelFor(
                        item.displayCounterparty,
                        snapshot.network.id,
                      ),
                      onExplorer: () => openExplorer(
                        context,
                        snapshot.network.explorerTx(item.hash),
                      ),
                      replacements: _replacementsFor(item, snapshot),
                      onReplace: (ReplacementKind kind) => showReplaceTransfer(
                        context,
                        network: snapshot.network,
                        nonce: item.nonce,
                        kind: kind,
                        original: item,
                      ),
                    )
                  else if (item is String)
                    _DayHeader(label: item),
              if (wallet.canLoadMoreActivity)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Center(
                    child: wallet.loadingMoreActivity
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : OutlinedButton.icon(
                            onPressed: () => _loadMore(context, wallet),
                            icon: const Icon(Icons.history_rounded),
                            label: const Text('Load more'),
                          ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Loads an older page, telling the user when the network refuses.
  Future<void> _loadMore(BuildContext context, WalletController wallet) async {
    final String? error = await wallet.loadMoreActivity();
    if (error != null && context.mounted) {
      showAppSnackBar(
        context,
        error,
        icon: Icons.cloud_off_rounded,
      );
    }
  }

  /// The replace actions offered for a still-pending outgoing transfer.
  List<ReplacementKind> _replacementsFor(
    ChainTransaction tx,
    AccountSnapshot snapshot,
  ) =>
      replacementKindsFor(
        original: tx,
        network: snapshot.network,
        tokens: snapshot.tokens,
      );

  /// Shares the loaded activity as a CSV file.
  ///
  /// The OS share sheet is the export: it covers "save to Drive", "send to
  /// myself" and the rest without this app owning a file picker or a
  /// Downloads-folder permission.
  Future<void> _exportCsv(
    BuildContext context,
    AccountSnapshot snapshot,
    TxNotesController notes,
  ) async {
    final String csv = buildActivityCsv(
      snapshot,
      noteFor: (ChainTransaction tx) => notes.noteFor(snapshot.network.id, tx.hash),
    );
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              utf8.encode(csv),
              mimeType: 'text/csv',
              name: 'material-wallet-activity.csv',
            ),
          ],
          fileNameOverrides: const <String>['material-wallet-activity.csv'],
          subject: 'Material Wallet activity',
        ),
      );
    } catch (error, stackTrace) {
      AppLog.warning('Could not share the activity export', error, stackTrace);
      if (context.mounted) {
        showAppSnackBar(
          context,
          'Could not export the activity.',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  /// Flattens the feed into day headers and transactions.
  List<Object> _groupedByDay(List<ChainTransaction> entries) {    final List<Object> items = <Object>[];
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
  const _FlowSummary({
    required this.snapshot,
    required this.currency,
    required this.hidden,
  });

  final AccountSnapshot snapshot;
  final AppCurrency currency;
  final bool hidden;

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
                value: hidden ? '••••' : _label(inflow),
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
                value: hidden ? '••••' : _label(outflow),
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
