import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../data/networks/network_config.dart';
import '../../data/notifications/notification_service.dart';
import '../../data/wallet/seed_vault.dart';
import '../../shared/widgets/mnemonic_grid.dart';
import '../../shared/widgets/pin_confirm_dialog.dart';
import '../../shared/widgets/pin_field.dart';
import '../../state/settings_controller.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_identity_controller.dart';
import '../lock/sensitive_auth.dart';
import '../network/network_picker.dart';
import 'address_book_screen.dart';
import 'addresses_screen.dart';
import 'currency_picker.dart';
import 'token_approvals_screen.dart';

/// Application preferences, wallet management and network switching.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = context.watch<SettingsController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: <Widget>[
          const _ProfileCard(),
          const SizedBox(height: 26),
          const _SectionTitle('Network'),
          const _NetworkSection(),
          const SizedBox(height: 26),
          const _SectionTitle('Wallet'),
          const _WalletSection(),
          const SizedBox(height: 26),
          const _SectionTitle('Security'),
          const _SecuritySection(),
          const SizedBox(height: 26),
          const _SectionTitle('Appearance'),
          _ThemeModeSelector(
            value: settings.themeMode,
            onChanged: settings.setThemeMode,
          ),
          const SizedBox(height: 26),
          const _SectionTitle('Currency'),
          _CurrencySelector(
            value: settings.currency,
            onChanged: settings.setCurrency,
          ),
          const SizedBox(height: 26),
          const _SectionTitle('About'),
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
                    'Self-custodial wallet',
                    style:
                        text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    createdAt == null
                        ? 'Encrypted on this device'
                        : 'Created ${AppFormat.dayLabel(createdAt)}',
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
                        'Seed encrypted with AES-256-GCM',
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
          title: const Text('Active network'),
          subtitle: Text(
            network.isTestnet
                ? '${network.name} · Testnet'
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
            ? 'Fingerprint unlock enabled.'
            : 'Fingerprint unlock was not enabled.',
        icon: enabled
            ? Icons.fingerprint_rounded
            : Icons.error_outline_rounded,
      );
    }
  }

  Future<String?> _confirmPin() => PinConfirmDialog.show(
        context,
        title: 'Confirm your PIN',
        confirmLabel: 'Enable',
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
          title: const Text('Token approvals'),
          subtitle: const Text(
            'Review and revoke what contracts may spend your tokens',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TokenApprovalsScreen()),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint_rounded),
          value: identity.biometricsEnabled,
          onChanged: _supported == true
              ? (bool value) => _toggle(value)
              : null,
          title: const Text('Unlock with fingerprint'),
          subtitle: Text(
            _supported == false
                ? 'Not available on this device'
                : identity.biometricsEnabled
                    ? 'Opens the wallet without typing the PIN'
                    : 'Confirms your PIN once to set up',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Auto-lock'),
          subtitle: Text(_autoLockLabel(settings.autoLockSeconds)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _pickAutoLock(settings),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          value: settings.notificationsEnabled,
          onChanged: _toggleNotifications,
          title: const Text('Transfer notifications'),
          subtitle: const Text(
            'Tells you when an outgoing transfer confirms',
          ),
        ),
      ],
    );
  }

  Future<void> _toggleNotifications(bool enable) async {
    final SettingsController settings = context.read<SettingsController>();
    if (!enable) {
      settings.setNotificationsEnabled(false);
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
        'Notifications were not allowed. You can enable them in system '
        'settings.',
        icon: Icons.notifications_off_rounded,
      );
    }
  }

  String _autoLockLabel(int? seconds) {
    if (seconds == null) {
      return 'Never';
    }
    if (seconds == 0) {
      return 'Immediately';
    }
    if (seconds < 60) {
      return 'After $seconds seconds';
    }
    return 'After ${seconds ~/ 60} minute${seconds == 60 ? '' : 's'}';
  }

  Future<void> _pickAutoLock(SettingsController settings) async {
    final AutoLockDelay? chosen = await showDialog<AutoLockDelay>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Auto-lock after'),
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
                    title: Text(delay.label),
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
              leading: const Icon(Icons.qr_code_2_rounded),
              isThreeLine: true,
              title: const Text('Receive address'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    address ?? 'Wallet locked',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Derived for the active network',
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              trailing: IconButton(
                tooltip: 'Copy address',
                icon: const Icon(Icons.copy_rounded),
                onPressed: address == null
                    ? null
                    : () => _copy(context, address),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_rounded),
              title: const Text('Your addresses'),
              subtitle: const Text('All chains, with QR codes'),
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
            ListTile(
              leading: const Icon(Icons.key_rounded),
              title: const Text('Recovery phrase'),
              subtitle: Text(
                identity.account == null
                    ? 'Locked'
                    : '${identity.words.length}-word BIP-39 phrase',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: identity.account == null
                  ? null
                  : () => _revealPhrase(context),
            ),
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: const Text('Change PIN'),
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
              title: const Text('Address book'),
              subtitle: const Text('Saved recipients and labels'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AddressBookScreen(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: const Text('Lock wallet'),
              subtitle: const Text('Clear the decrypted seed from memory'),
              onTap: identity.lock,
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
              title: Text(
                'Remove wallet',
                style: text.titleMedium?.copyWith(color: scheme.error),
              ),
              subtitle: const Text('Deletes the encrypted seed'),
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
        'Address copied to clipboard',
        icon: Icons.check_circle_outline_rounded,
      );
    }
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
        title: const Text('Reveal recovery phrase?'),
        content: const Text(
          'Make sure nobody can see your screen. Anyone who reads these words '
          'can take your funds.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reveal'),
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
      reason: 'Reveal recovery phrase',
      title: 'Confirm your PIN',
      confirmLabel: 'Reveal',
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
                  'Recovery phrase',
                  style:
                      text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '${words.length} words · keep them offline.',
                  style: text.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
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
        title: const Text('Remove wallet?'),
        content: const Text(
          'Without the recovery phrase the funds are unrecoverable. Make sure '
          'you have your backup before continuing.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (!(confirmed ?? false) || !context.mounted) {
      return;
    }
    showAppSnackBar(
      context,
      'Wallet removed from this device.',
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
  static const int _minLength = 6;

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
                'Change PIN',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'The recovery phrase is re-encrypted with the new PIN.',
                style:
                    text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              PinField(
                controller: _currentController,
                label: 'Current PIN',
                autofocus: true,
                enabled: !_busy,
                errorText: _error,
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 14),
              PinField(
                controller: _nextController,
                label: 'New PIN (min. $_minLength digits)',
                enabled: !_busy,
              ),
              const SizedBox(height: 14),
              PinField(
                controller: _confirmController,
                label: 'Confirm new PIN',
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
                label: Text(_busy ? 'Re-encrypting…' : 'Save new PIN'),
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
      setState(() => _error = 'Use at least $_minLength digits');
      return;
    }
    if (next != _confirmController.text) {
      setState(() => _error = 'New PINs do not match');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await context.read<WalletIdentityController>().changePin(
            currentPin: _currentController.text,
            newPin: next,
          );
    } on SeedVaultException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not change the PIN.';
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
      const SnackBar(content: Text('PIN updated successfully.')),
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
            segments: const <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                label: Text('System'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                label: Text('Light'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                label: Text('Dark'),
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
          title: const Text('Display currency'),
          subtitle: const Text('Prices are converted from USD'),
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
              title: const Text('Version'),
              subtitle: const Text('Self-custodial · BIP-39 / BIP-84 / BIP-44'),
              trailing: const Text('1.0.0 (1)'),
              onTap: () => showAppSnackBar(
                context,
                'Material Wallet 0.1.0 — built with Flutter & Material 3.',
                icon: Icons.info_outline_rounded,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Data sources'),
              subtitle: const Text(
                'mempool.space · Blockscout · CoinGecko',
              ),
              isThreeLine: true,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Material Wallet · demo build',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
