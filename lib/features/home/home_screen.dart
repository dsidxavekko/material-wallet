import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/explorer.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../data/networks/chain_models.dart';
import '../../shared/widgets/quick_actions.dart';
import '../../shared/widgets/section_header.dart';
import '../../state/contacts_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/wallet_controller.dart';
import '../activity/activity_screen.dart';
import '../activity/widgets/transaction_tile.dart';
import '../network/network_chip.dart';
import '../receive/receive_screen.dart';
import '../send/replace_transfer.dart';
import '../send/send_screen.dart';
import '../settings/currency_picker.dart';
import '../settings/token_approvals_screen.dart';
import 'widgets/account_balance_card.dart';
import 'widgets/address_card.dart';
import 'widgets/state_cards.dart';
import 'widgets/token_list.dart';

/// Wallet tab: live balance, address and recent on-chain activity.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hideBalance = false;

  @override
  Widget build(BuildContext context) {
    final WalletController wallet = context.watch<WalletController>();
    final ContactsController contacts = context.watch<ContactsController>();
    final AppCurrency currency =
        context.select<SettingsController, AppCurrency>((s) => s.currency);
    final AccountSnapshot? snapshot = wallet.snapshot;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Material Wallet'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: wallet.loading ? null : wallet.refresh,
            icon: wallet.loading
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
        onRefresh: wallet.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
          children: <Widget>[
            const Align(
              alignment: Alignment.centerLeft,
              child: NetworkChip(),
            ),
            const SizedBox(height: 16),
            if (wallet.error != null) ...<Widget>[
              ErrorCard(
                message: wallet.error!,
                onRetry: wallet.refresh,
                showRetry: wallet.errorRetryable,
              ),
              const SizedBox(height: 16),
            ],
            if (snapshot != null)
              _content(snapshot, currency, wallet, contacts)
            else
              const LoadingCard(),
          ],
        ),
      ),
    );
  }

  Widget _content(
    AccountSnapshot snapshot,
    AppCurrency currency,
    WalletController wallet,
    ContactsController contacts,
  ) {
    final List<ChainTransaction> recent =
        snapshot.transactions.take(5).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AccountBalanceCard(
          snapshot: snapshot,
          currency: currency,
          hidden: _hideBalance,
          onToggleVisibility: () =>
              setState(() => _hideBalance = !_hideBalance),
          onCurrencyTap: () => _pickCurrency(context),
          onRetryPrice: wallet.refresh,
        ),
        const SizedBox(height: 20),
        if (wallet.portfolioFiat != null) ...<Widget>[
          _PortfolioCard(
            totalUsd: wallet.portfolioFiat!,
            currency: currency,
            hidden: _hideBalance,
          ),
          const SizedBox(height: 16),
        ],
        QuickActions(
          onSend: () => _push(context, const SendScreen()),
          onReceive: () => _push(context, const ReceiveScreen()),
        ),
        if (snapshot.tokens.isNotEmpty) ...<Widget>[
          const SizedBox(height: 26),
          SectionHeader(
            title: 'Tokens',
            // Approvals are the safety net for a token balance the user has
            // already lost the right to: put it where the tokens are.
            actionLabel: 'Approvals',
            onAction: () => _push(context, const TokenApprovalsScreen()),
          ),
          TokenList(
            tokens: snapshot.tokens,
            currency: currency,
            onTokenTap: (TokenBalance token) =>
                _push(context, SendScreen(token: token)),
          ),
        ],
        const SizedBox(height: 26),
        const SectionHeader(title: 'Your address'),
        AddressCard(
          address: snapshot.address,
          networkLabel: snapshot.network.name,
          onCopy: () => _copyAddress(snapshot.address),
          onExplorer: () => openExplorer(
            context,
            snapshot.network.explorerAddress(snapshot.address),
          ),
        ),
        const SizedBox(height: 26),
        SectionHeader(
          title: 'Recent activity',
          actionLabel: recent.isEmpty ? null : 'See all',
          onAction: recent.isEmpty
              ? null
              : () => _push(context, const ActivityScreen()),
        ),
        if (recent.isEmpty)
          const _NoActivity()
        else
          Card(
            child: Column(
              children: <Widget>[
                for (int i = 0; i < recent.length; i++) ...<Widget>[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  TransactionTile(
                    transaction: recent[i],
                    network: snapshot.network,
                    currency: currency,
                    price: snapshot.price,
                    counterpartyLabel: contacts.labelFor(
                      recent[i].counterparty,
                      snapshot.network.id,
                    ),
                    onExplorer: () => openExplorer(
                      context,
                      snapshot.network.explorerTx(recent[i].hash),
                    ),
                    replacements: replacementKindsFor(
                      original: recent[i],
                      network: snapshot.network,
                      tokens: snapshot.tokens,
                    ),
                    onReplace: (ReplacementKind kind) => showReplaceTransfer(
                      context,
                      network: snapshot.network,
                      nonce: recent[i].nonce!,
                      kind: kind,
                      original: recent[i],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<void> _pickCurrency(BuildContext context) async {
    final SettingsController settings = context.read<SettingsController>();
    final AppCurrency? picked =
        await showCurrencyPicker(context, current: settings.currency);
    if (picked != null) {
      settings.setCurrency(picked);
    }
  }

  Future<void> _copyAddress(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (mounted) {
      showAppSnackBar(
        context,
        'Address copied to clipboard',
        icon: Icons.check_circle_outline_rounded,
      );
    }
  }
}

/// Best-effort total value across every network the account has synced.
class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({
    required this.totalUsd,
    required this.currency,
    required this.hidden,
  });

  final double totalUsd;
  final AppCurrency currency;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Card(
      child: ListTile(
        leading: Icon(Icons.pie_chart_outline_rounded, color: scheme.primary),
        title: const Text('Total across networks'),
        subtitle: const Text('From the last synced balance of each chain'),
        trailing: Text(
          hidden ? '••••' : AppFormat.fiat(totalUsd, currency),
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _NoActivity extends StatelessWidget {
  const _NoActivity();
  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: <Widget>[
            Icon(Icons.hourglass_empty_rounded, color: scheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'No transactions on this network yet. Receive some funds to '
                'see them here.',
                style: text.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
