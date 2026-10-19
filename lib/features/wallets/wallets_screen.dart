import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../data/wallet/seed_vault.dart';
import '../../data/wallet/wallet_entry.dart';
import '../../data/wallet/watch_address.dart';
import '../../shared/widgets/pin_confirm_dialog.dart';
import '../../state/wallet_identity_controller.dart';
import '../onboarding/create_wallet_screen.dart';
import '../onboarding/import_wallet_screen.dart';
import 'watch_wallet_screen.dart';
import '../../l10n/l10n.dart';
import '../../l10n/messages.dart';

/// Every wallet on the device: recovery phrases (one vault, one password) and
/// watch-only wallets (public addresses, no key). Tapping one switches to it.
class WalletsScreen extends StatelessWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final WalletIdentityController identity =
        context.watch<WalletIdentityController>();
    final List<WalletEntry> wallets = identity.wallets;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.wallets)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          for (final WalletEntry wallet in wallets)
            Card(
              child: ListTile(
                selected: wallet.id == identity.activeWalletId,
                leading: Icon(
                  wallet.isWatchOnly
                      ? Icons.visibility_outlined
                      : Icons.account_balance_wallet_rounded,
                ),
                title: Text(wallet.name),
                subtitle: Text(_subtitle(context, wallet)),
                trailing: wallet.id == identity.activeWalletId
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.check_circle_rounded, color: scheme.primary),
                          _menu(context, identity, wallet),
                        ],
                      )
                    : _menu(context, identity, wallet),
                onTap: () => identity.selectWallet(wallet.id),
              ),
            ),
          const SizedBox(height: 18),
          Text(
            context.l10n.addAWallet,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.add_circle_outline_rounded),
                  title: Text(context.l10n.createANewWallet),
                  subtitle: Text(context.l10n.aFreshRecoveryPhrase),
                  onTap: () => _open(context, const CreateWalletScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: Text(context.l10n.importARecoveryPhrase),
                  subtitle: Text(context.l10n.another12Or24Word),
                  onTap: () => _open(context, const ImportWalletScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_outlined),
                  title: Text(context.l10n.watchAnAddress),
                  subtitle: Text(context.l10n.followABalanceWithoutThe),
                  onTap: () => _open(context, const WatchWalletScreen()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _subtitle(BuildContext context, WalletEntry wallet) {
    if (!wallet.isWatchOnly) {
      return context.l10n.recoveryPhrase;
    }
    final List<String> kinds = <String>[
      for (final String family in wallet.watched.keys)
        tr(WatchAddresses.labels[family] ?? family),
    ];
    return context.l10n.watchOnly(kinds.join(', '));
  }

  static void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Widget _menu(
    BuildContext context,
    WalletIdentityController identity,
    WalletEntry wallet,
  ) {
    return PopupMenuButton<String>(
      tooltip: context.l10n.walletOptions,
      onSelected: (String action) {
        if (action == 'rename') {
          _rename(context, identity, wallet);
        } else if (action == 'edit') {
          _open(context, WatchWalletScreen(editing: wallet));
        } else {
          _remove(context, identity, wallet);
        }
      },
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'rename', child: Text(context.l10n.rename)),
        if (wallet.isWatchOnly)
          PopupMenuItem<String>(
            value: 'edit',
            child: Text(context.l10n.editAddresses),
          ),
        PopupMenuItem<String>(value: 'remove', child: Text(context.l10n.remove)),
      ],
    );
  }

  Future<void> _rename(
    BuildContext context,
    WalletIdentityController identity,
    WalletEntry wallet,
  ) async {
    final TextEditingController controller =
        TextEditingController(text: wallet.name);
    final String? name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.walletName),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: context.l10n.eGSavings),
          onSubmitted: (String v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) {
      await identity.renameWallet(wallet.id, name);
    }
  }

  Future<void> _remove(
    BuildContext context,
    WalletIdentityController identity,
    WalletEntry wallet,
  ) async {
    final bool watch = wallet.isWatchOnly;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text(context.l10n.remove2(wallet.name)),
        content: Text(
          watch
              ? context.l10n.theFollowedAddressesAreForgotten
              : context.l10n.withoutItsRecoveryPhraseThe,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) {
      return;
    }
    if (watch) {
      await identity.removeWatchWallet(wallet.id);
      return;
    }

    // A recovery phrase goes only with the password: the vault is rewritten.
    final String? password = await PinConfirmDialog.show(
      context,
      title: context.l10n.confirmYourPassword,
      confirmLabel: context.l10n.remove,
      icon: Icons.delete_outline_rounded,
    );
    if (password == null || !context.mounted) {
      return;
    }
    try {
      await identity.removeSeedWallet(wallet.id, password);
    } on SeedVaultException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, error.message, icon: Icons.error_outline_rounded);
      }
    }
  }
}
