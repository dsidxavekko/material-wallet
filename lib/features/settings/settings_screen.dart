import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../data/networks/network_config.dart';
import '../../data/background/background_service.dart';
import '../../data/notifications/notification_service.dart';
import '../../data/wallet/seed_vault.dart';
import '../../shared/widgets/mnemonic_grid.dart';
import '../../shared/widgets/password_strength_meter.dart';
import '../../shared/widgets/pin_confirm_dialog.dart';
import '../../shared/widgets/pin_field.dart';
import '../../state/settings_controller.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_identity_controller.dart';
import '../lock/sensitive_auth.dart';
import '../network/network_picker.dart';
import '../wallets/wallets_screen.dart';
import 'address_book_screen.dart';
import 'addresses_screen.dart';
import 'currency_picker.dart';
import 'token_approvals_screen.dart';
import '../../l10n/l10n.dart';
import '../../l10n/messages.dart';

/// Application preferences, wallet management and network switching.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: <Widget>[
          const _ProfileCard(),
          const SizedBox(height: 26),
          _SectionTitle(context.l10n.network),
          const _NetworkSection(),
          const SizedBox(height: 26),
          _SectionTitle(context.l10n.wallet),
          const _WalletSection(),
          const SizedBox(height: 26),
          _SectionTitle(context.l10n.security),
          const _SecuritySection(),
          const SizedBox(height: 26),
          _SectionTitle(context.l10n.appearance),
          _ThemeModeSelector(
            value: settings.themeMode,
            onChanged: settings.setThemeMode,
          ),
          const SizedBox(height: 12),
          const _LanguageTile(),
          const SizedBox(height: 26),
          _SectionTitle(context.l10n.currency),
          _CurrencySelector(
            value: settings.currency,
            onChanged: settings.setCurrency,
          ),
          const SizedBox(height: 26),
          _SectionTitle(context.l10n.about),
          const _AboutCard(),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    final WalletIdentityController identity =
        context.watch<WalletIdentityController>();
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DateTime? createdAt = identity.createdAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 28,
              backgroundColor: scheme.primaryContainer,
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: scheme.onPrimaryContainer,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    identity.hasVault
                        ? context.l10n.selfCustodialWallet
                        : context.l10n.watchOnlyMode,
                    style:
                        text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    !identity.hasVault
                        ? context.l10n.noKeysOnThisDevice
                        : createdAt == null
                            ? context.l10n.encryptedOnThisDevice
                            : context.l10n.created(AppFormat.dayLabel(createdAt)),
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.verified_user_outlined,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        identity.hasVault
                            ? context.l10n.seedEncryptedWithAes256
                            : context.l10n.nothingSecretIsStored,
                        style: text.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _NetworkSection extends StatelessWidget {
  const _NetworkSection();

  @override
  Widget build(BuildContext context) {
    final NetworkConfig network =
        context.watch<SettingsController>().network;

    return _SettingsGroup(
      children: <Widget>[
        ListTile(
          leading: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: network.color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(
              network.symbol.length > 3
                  ? network.symbol.substring(0, 3)
                  : network.symbol,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: network.color,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          title: Text(context.l10n.activeNetwork),
          subtitle: Text(
            network.isTestnet
                ? context.l10n.testnet2(network.name)
                : network.name,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => showNetworkPicker(context),
        ),
      ],
    );
  }
}

/// Fingerprint unlock toggle. Enabling keeps the PIN in the platform keystore,
/// so it asks for the PIN once to confirm the user owns the wallet.
class _SecuritySection extends StatefulWidget {
  const _SecuritySection();

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  /// `null` while the biometric hardware is still being probed.
  bool? _supported;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    final bool supported =
        await context.read<WalletIdentityController>().canUseBiometrics();
    if (mounted) {
      setState(() => _supported = supported);
    }
  }

  Future<void> _toggle(bool enable) async {
    final WalletIdentityController identity =
        context.read<WalletIdentityController>();

    if (!enable) {
      await identity.disableBiometrics();
      return;
    }

    final String? pin = await _confirmPin();
    if (pin == null || !mounted) {
      return;
    }

    try {
      await identity.verifyPin(pin);
    } on SeedVaultException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message,
            icon: Icons.error_outline_rounded);
      }
      return;
    }

    final bool enabled = await identity.enableBiometrics(pin);
    if (mounted) {
      showAppSnackBar(
        context,
        enabled
            ? context.l10n.fingerprintUnlockEnabled
            : context.l10n.fingerprintUnlockWasNotEnabled,
        icon: enabled
            ? Icons.fingerprint_rounded
            : Icons.error_outline_rounded,
      );
    }
  }

  Future<String?> _confirmPin() => PinConfirmDialog.show(
        context,
        title: context.l10n.confirmYourPassword,
        confirmLabel: context.l10n.enable,
        icon: Icons.fingerprint_rounded,
      );

  @override
  Widget build(BuildContext context) {
    final WalletIdentityController identity =
        context.watch<WalletIdentityController>();
    final SettingsController settings = context.watch<SettingsController>();

    return _SettingsGroup(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: Text(context.l10n.tokenApprovals),
          subtitle: Text(
            context.l10n.reviewAndRevokeWhatContracts,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TokenApprovalsScreen()),
          ),
        ),
        if (identity.hasVault)
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint_rounded),
          value: identity.biometricsEnabled,
          onChanged: _supported == true
              ? (bool value) => _toggle(value)
              : null,
          title: Text(context.l10n.unlockWithFingerprint2),
          subtitle: Text(
            _supported == false
                ? context.l10n.notAvailableOnThisDevice
                : identity.biometricsEnabled
                    ? context.l10n.opensTheWalletWithoutTyping
                    : context.l10n.confirmsYourPasswordOnceTo,
          ),
        ),
        if (identity.hasVault)
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: Text(context.l10n.autoLock),
          subtitle: Text(_autoLockLabel(settings.autoLockSeconds)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _pickAutoLock(settings),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          value: settings.notificationsEnabled,
          onChanged: _toggleNotifications,
          title: Text(context.l10n.transferNotifications),
          subtitle: Text(
            context.l10n.tellsYouWhenAnOutgoing,
          ),
        ),
        if (BackgroundService.supported)
          SwitchListTile(
            secondary: const Icon(Icons.notifications_paused_outlined),
            value: settings.backgroundChecks && settings.notificationsEnabled,
            onChanged: _toggleBackground,
            title: Text(context.l10n.notifyWhenClosed),
            subtitle: Text(
              context.l10n.checksForIncomingFundsAnd,
            ),
          ),
      ],
    );
  }

  Future<void> _toggleBackground(bool enable) async {
    final SettingsController settings = context.read<SettingsController>();
    if (!enable) {
      settings.setBackgroundChecks(false);
      return;
    }
    if (!settings.notificationsEnabled) {
      final bool granted =
          await context.read<NotificationService>().initialize(request: true);
      if (!mounted) {
        return;
      }
      if (!granted) {
        showAppSnackBar(
          context,
          context.l10n.notificationsWereNotAllowedYou,
          icon: Icons.notifications_off_rounded,
        );
        return;
      }
      settings.setNotificationsEnabled(true);
    }
    settings.setBackgroundChecks(true);
  }

  Future<void> _toggleNotifications(bool enable) async {
    final SettingsController settings = context.read<SettingsController>();
    if (!enable) {
      settings.setNotificationsEnabled(false);
      // Checks while closed exist to notify; without notifications they would
      // only cost battery.
      settings.setBackgroundChecks(false);
      return;
    }

    final bool granted =
        await context.read<NotificationService>().initialize(request: true);
    if (!mounted) {
      return;
    }
    if (granted) {
      settings.setNotificationsEnabled(true);
    } else {
      showAppSnackBar(
        context,
        context.l10n.notificationsWereNotAllowedYou,
        icon: Icons.notifications_off_rounded,
      );
    }
  }

  String _autoLockLabel(int? seconds) {
    if (seconds == null) {
      return context.l10n.never;
    }
    if (seconds == 0) {
      return context.l10n.immediately;
    }
    if (seconds < 60) {
      return context.l10n.secondOtherSeconds(seconds);
    }
    return context.l10n.minuteOtherMinutes(seconds ~/ 60);
  }

  Future<void> _pickAutoLock(SettingsController settings) async {
    final AutoLockDelay? chosen = await showDialog<AutoLockDelay>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.l10n.autoLockAfter),
        children: <Widget>[
          RadioGroup<AutoLockDelay>(
            groupValue: _delayFor(settings.autoLockSeconds),
            onChanged: (AutoLockDelay? value) =>
                Navigator.of(dialogContext).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final AutoLockDelay delay in AutoLockDelay.values)
                  RadioListTile<AutoLockDelay>(
                    value: delay,
                    title: Text(tr(delay.label)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (chosen != null && mounted) {
      settings.setAutoLockDelay(chosen);
    }
  }

  AutoLockDelay _delayFor(int? seconds) {
    return AutoLockDelay.values.firstWhere(
      (AutoLockDelay delay) => delay.seconds == seconds,
      orElse: () => AutoLockDelay.minute1,
    );
  }
}

class _WalletSection extends StatelessWidget {
  const _WalletSection();

  @override
  Widget build(BuildContext context) {
    final WalletIdentityController identity =
        context.watch<WalletIdentityController>();
    final String? address =
        context.select<WalletController, String?>((s) => s.address);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      children: <Widget>[
        _SettingsGroup(
          children: <Widget>[
            ListTile(
              leading: Icon(
                identity.isWatchOnly
                    ? Icons.visibility_outlined
                    : Icons.account_balance_wallet_outlined,
              ),
              title: Text(context.l10n.wallets),
              subtitle: Text(
                context.l10n.walletOnThisDeviceOther(identity.activeWallet?.name ?? '—', identity.wallets.length),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const WalletsScreen()),
              ),
            ),
            if (!identity.isWatchOnly)
              ListTile(
                leading: const Icon(Icons.switch_account_rounded),
                title: Text(context.l10n.activeAccount),
                subtitle: Text(
                  context.l10n.ofLabel(context.watch<SettingsController>().accountName(identity.accountIndex, walletId: identity.activeWalletId), identity.accountIndex + 1, identity.accountCount),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _pickAccount(context, identity),
              ),
            ListTile(
              leading: const Icon(Icons.qr_code_2_rounded),
              isThreeLine: true,
              title: Text(
                identity.isWatchOnly ? context.l10n.followedAddress : context.l10n.receiveAddress,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    address ??
                        (identity.isWatchOnly ? context.l10n.noAddress : context.l10n.walletLocked),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address == null && identity.isWatchOnly
                        ? context.l10n.thisWalletFollowsNoAddress
                        : identity.isWatchOnly
                            ? context.l10n.watchOnlyCannotSend
                            : context.l10n.derivedForTheActiveNetwork,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              trailing: IconButton(
                tooltip: context.l10n.copyAddress,
                icon: const Icon(Icons.copy_rounded),
                onPressed: address == null
                    ? null
                    : () => _copy(context, address),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_rounded),
              title: Text(context.l10n.yourAddresses),
              subtitle: Text(context.l10n.allChainsWithQrCodes),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AddressesScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SettingsGroup(
          children: <Widget>[
            if (!identity.isWatchOnly)
              ListTile(
                leading: const Icon(Icons.key_rounded),
                title: Text(context.l10n.recoveryPhrase),
                subtitle: Text(
                  identity.account == null
                      ? context.l10n.locked
                      : context.l10n.wordBip39Phrase(identity.words.length),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: identity.account == null
                    ? null
                    : () => _revealPhrase(context),
              ),
            if (identity.hasVault)
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: Text(context.l10n.changePassword),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => const _ChangePinSheet(),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.contacts_rounded),
              title: Text(context.l10n.addressBook),
              subtitle: Text(context.l10n.savedRecipientsAndLabels),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AddressBookScreen(),
                ),
              ),
            ),
            if (identity.hasVault)
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: Text(context.l10n.lockWallet),
                subtitle: Text(context.l10n.clearTheDecryptedSeedFrom),
                onTap: identity.lock,
              ),
            if (identity.hasVault)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
                title: Text(
                  context.l10n.eraseRecoveryPhrases,
                  style: text.titleMedium?.copyWith(color: scheme.error),
                ),
                subtitle: Text(
                  context.l10n.deletesEveryEncryptedSeedAnd,
                ),
                onTap: () => _removeWallet(context),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (context.mounted) {
      showAppSnackBar(
        context,
        context.l10n.addressCopiedToClipboard,
        icon: Icons.check_circle_outline_rounded,
      );
    }
  }

  /// Dialog that switches between the derived accounts and can add a new one.
  ///
  /// Accounts are BIP-44 indexes of the same seed — no extra secret is stored,
  /// and switching only re-derives the addresses and reloads the balances.
  Future<void> _pickAccount(
    BuildContext context,
    WalletIdentityController identity,
  ) async {
    const int addNew = -1;
    final int? chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.l10n.activeAccount),
        children: <Widget>[
          RadioGroup<int>(
            groupValue: identity.accountIndex,
            onChanged: (int? value) => Navigator.of(dialogContext).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < identity.accountCount; i++)
                  RadioListTile<int>(
                    value: i,
                    title: Text(
                      context.read<SettingsController>().accountName(
                            i,
                            walletId: identity.activeWalletId,
                          ),
                    ),
                    subtitle: i == 0 ? Text(context.l10n.defaultLabel) : null,
                    secondary: IconButton(
                      tooltip: context.l10n.rename,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final SettingsController settings =
                            context.read<SettingsController>();
                        final String? name = await _askAccountName(
                          dialogContext,
                          settings.hasCustomAccountName(
                            i,
                            walletId: identity.activeWalletId,
                          )
                              ? settings.accountName(
                                  i,
                                  walletId: identity.activeWalletId,
                                )
                              : '',
                        );
                        if (name != null) {
                          settings.renameAccount(
                            i,
                            name,
                            walletId: identity.activeWalletId,
                          );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: Text(context.l10n.addAccount),
            subtitle: Text(context.l10n.aFreshSetOfAddresses),
            onTap: () => Navigator.of(dialogContext).pop(addNew),
          ),
        ],
      ),
    );

    if (chosen == null || !context.mounted) {
      return;
    }
    if (chosen == addNew) {
      await identity.addAccount();
      return;
    }
    await identity.selectAccount(chosen);
  }

  /// Asks for a name for an account; an empty answer restores the default.
  Future<String?> _askAccountName(BuildContext context, String current) async {
    final TextEditingController controller =
        TextEditingController(text: current);
    final String? name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.accountName),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: context.l10n.eGSavingsEmptyDefault,
          ),
          onSubmitted: (String v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    return name;
  }

  Future<void> _revealPhrase(BuildContext context) async {
    final WalletIdentityController identity =
        context.read<WalletIdentityController>();
    final List<String> words = identity.words;
    if (words.isEmpty) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.key_rounded),
        title: Text(context.l10n.revealRecoveryPhrase),
        content: Text(
          context.l10n.makeSureNobodyCanSee,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.reveal),
          ),
        ],
      ),
    );

    if (!(confirmed ?? false) || !context.mounted) {
      return;
    }

    // The recovery phrase is the keys to the wallet: require re-auth even
    // though the app is already unlocked, so an unattended phone cannot be used
    // to walk off with it. This is the one place the PIN is still allowed as a
    // fallback — a user who enabled biometrics and can no longer read their
    // fingerprint must not be locked out of their own funds.
    if (!await authorizeSensitiveAction(
      context,
      reason: context.l10n.revealRecoveryPhrase2,
      title: context.l10n.confirmYourPassword,
      confirmLabel: context.l10n.reveal,
      icon: Icons.key_rounded,
      allowPinFallback: true,
    )) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final TextTheme text = Theme.of(sheetContext).textTheme;
        final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.l10n.recoveryPhrase,
                  style:
                      text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.wordKeepItOfflineOther(words.length),
                  style: text.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (identity.account?.hasPassphrase ?? false) ...<Widget>[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.info_outline_rounded,
                          color: scheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.l10n.thisWalletAlsoUsesA,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onTertiaryContainer,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                MnemonicGrid(words: words),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _removeWallet(BuildContext context) async {
    final WalletIdentityController identity =
        context.read<WalletIdentityController>();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text(context.l10n.eraseEveryRecoveryPhrase),
        content: Text(
          context.l10n.thisDeletesAllRecoveryPhrases,
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
    showAppSnackBar(
      context,
      context.l10n.recoveryPhrasesErasedFromThis,
      icon: Icons.delete_outline_rounded,
    );
    await identity.removeWallet();
  }
}

/// Sheet that re-encrypts the seed under a new PIN.
class _ChangePinSheet extends StatefulWidget {
  const _ChangePinSheet();

  @override
  State<_ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends State<_ChangePinSheet> {
  static const int _minLength = kMinPasswordLength;

  final TextEditingController _currentController = TextEditingController();
  final TextEditingController _nextController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _currentController.dispose();
    _nextController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.changePassword,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.theRecoveryPhraseIsRe,
                style:
                    text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              PinField(
                controller: _currentController,
                label: context.l10n.currentPassword,
                autofocus: true,
                enabled: !_busy,
                errorText: _error,
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 14),
              PinField(
                controller: _nextController,
                label: context.l10n.newPasswordMinCharacters(_minLength),
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              PasswordStrengthMeter(password: _nextController.text),
              const SizedBox(height: 14),
              PinField(
                controller: _confirmController,
                label: context.l10n.confirmNewPassword,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.password_rounded),
                label: Text(_busy ? context.l10n.reEncrypting : context.l10n.saveNewPassword),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final String next = _nextController.text;

    if (next.length < _minLength) {
      setState(() => _error = context.l10n.useAtLeastCharacters(_minLength));
      return;
    }
    if (next != _confirmController.text) {
      setState(() => _error = context.l10n.newPasswordsDoNotMatch);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final bool hadFingerprint =
        context.read<WalletIdentityController>().biometricsEnabled;
    bool fingerprintKept = false;
    try {
      fingerprintKept = await context.read<WalletIdentityController>().changePin(
            currentPin: _currentController.text,
            newPin: next,
          );
    } on SeedVaultException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr(error.message);
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.l10n.couldNotChangeThePassword;
        });
      }
      return;
    }

    if (!mounted) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          hadFingerprint && !fingerprintKept
              ? context.l10n.passwordUpdatedFingerprintUnlockWas
              : context.l10n.passwordUpdatedSuccessfully,
        ),
      ),
    );
  }
}

/// Picks the app language: follow the system, English or Ukrainian.
class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();
    final String current = switch (settings.locale?.languageCode) {
      'en' => context.l10n.languageEnglish,
      'uk' => context.l10n.languageUkrainian,
      _ => context.l10n.languageSystem,
    };
    return Card(
      child: ListTile(
        leading: const Icon(Icons.translate_rounded),
        title: Text(context.l10n.language),
        subtitle: Text(current),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          final String? code = await showDialog<String>(
            context: context,
            builder: (BuildContext dialogContext) => SimpleDialog(
              title: Text(dialogContext.l10n.chooseLanguage),
              children: <Widget>[
                RadioGroup<String>(
                  groupValue: settings.locale?.languageCode ?? 'system',
                  onChanged: (String? value) =>
                      Navigator.of(dialogContext).pop(value),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      RadioListTile<String>(
                        value: 'system',
                        title: Text(dialogContext.l10n.languageSystem),
                      ),
                      RadioListTile<String>(
                        value: 'en',
                        title: Text(dialogContext.l10n.languageEnglish),
                      ),
                      RadioListTile<String>(
                        value: 'uk',
                        title: Text(dialogContext.l10n.languageUkrainian),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
          if (code != null) {
            settings.setLocale(code == 'system' ? null : Locale(code));
          }
        },
      ),
    );
  }
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                label: Text(context.l10n.system),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                label: Text(context.l10n.light),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                label: Text(context.l10n.dark),
              ),
            ],
            selected: <ThemeMode>{value},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ),
      ),
    );
  }
}

class _CurrencySelector extends StatelessWidget {
  const _CurrencySelector({required this.value, required this.onChanged});

  final AppCurrency value;
  final ValueChanged<AppCurrency> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return _SettingsGroup(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: Text(context.l10n.displayCurrency),
          subtitle: Text(context.l10n.pricesAreConvertedFromUsd),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                value.code,
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          onTap: () => _pick(context),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final AppCurrency? picked =
        await showCurrencyPicker(context, current: value);
    if (picked != null) {
      onChanged(picked);
    }
  }
}

/// Application version and build number, kept in sync with `pubspec.yaml`.
const String appVersion = '0.5.0';
const String appBuildNumber = '6';

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Column(
      children: <Widget>[
        _SettingsGroup(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(context.l10n.version),
              subtitle: Text(context.l10n.selfCustodialBip39Bip),
              trailing: const Text('$appVersion ($appBuildNumber)'),
              onTap: () => showAppSnackBar(
                context,
                context.l10n.materialWalletBuiltWithFlutter(appVersion),
                icon: Icons.info_outline_rounded,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(context.l10n.dataSources),
              subtitle: Text(
                context.l10n.mempoolSpaceBlockscoutCoingeckoPublicnode,
              ),
              isThreeLine: true,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          context.l10n.materialWalletDemoBuild,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
