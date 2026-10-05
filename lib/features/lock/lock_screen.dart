import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../data/wallet/seed_vault.dart';
import '../../shared/widgets/pin_field.dart';
import '../../state/wallet_identity_controller.dart';

/// Asks for the PIN and decrypts the stored recovery phrase.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final TextEditingController _pinController = TextEditingController();
  String? _error;
  bool _busy = false;

  bool _promptedBiometrics = false;

  /// Ticks once a second while a wrong-PIN penalty is active, so the
  /// "Try again in …" label counts down without user input.
  Timer? _lockoutTicker;

  @override
  void initState() {
    super.initState();
    if (context.read<WalletIdentityController>().unlockThrottled) {
      _startLockoutTicker();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Prompt for the fingerprint once biometrics is known to be enabled — the
    // controller publishes that flag a moment after startup.
    if (_promptedBiometrics) {
      return;
    }
    if (!context.read<WalletIdentityController>().biometricsEnabled) {
      return;
    }
    _promptedBiometrics = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  /// Unlocks with the fingerprint when the wallet was set up with one.
  ///
  /// Failures stay silent so the user can simply type the PIN instead.
  Future<void> _tryBiometrics() async {
    if (!mounted) {
      return;
    }
    final WalletIdentityController identity =
        context.read<WalletIdentityController>();
    if (!identity.biometricsEnabled) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    await identity.unlockWithBiometrics();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    // On failure the PIN field below is always available — nothing to do.
  }

  void _startLockoutTicker() {
    _lockoutTicker?.cancel();
    _lockoutTicker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!context.read<WalletIdentityController>().unlockThrottled) {
        timer.cancel();
        _lockoutTicker = null;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _lockoutTicker?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final WalletIdentityController identity =
        context.watch<WalletIdentityController>();
    final bool throttled = identity.unlockThrottled;
    final String? throttleHint =
        throttled ? identity.throttle.retryHint(DateTime.now()) : null;
    final bool blocked = _busy || throttled;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[scheme.primary, scheme.tertiary],
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome back',
                  style: text.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your PIN to decrypt the wallet.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                PinField(
                  controller: _pinController,
                  label: 'PIN',
                  autofocus: true,
                  enabled: !blocked,
                  errorText: throttleHint ?? _error,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _unlock(),
                  onChanged: (_) {
                    if (_error != null) {
                      setState(() => _error = null);
                    }
                  },
                ),
                if (throttleHint != null) ...<Widget>[
                  const SizedBox(height: 10),
                  _ThrottleNotice(hint: throttleHint),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: blocked ? null : _unlock,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open_rounded),
                  label: Text(_busy ? 'Decrypting…' : 'Unlock'),
                ),
                if (identity.biometricsEnabled) ...<Widget>[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _tryBiometrics,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('Unlock with fingerprint'),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _confirmReset,
                  child: const Text('Forgot PIN — remove wallet'),
                ),
                const SizedBox(height: 12),
                Text(
                  'AES-256-GCM · PBKDF2-SHA256',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _unlock() async {
    if (_pinController.text.isEmpty) {
      setState(() => _error = 'Enter your PIN');
      return;
    }

    final WalletIdentityController identity =
        context.read<WalletIdentityController>();
    if (identity.unlockThrottled) {
      // The button is disabled in that state, but guard here too in case the
      // lockout expired between the last frame and the tap.
      _startLockoutTicker();
      setState(() {});
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await identity.unlock(_pinController.text);
    } on SeedVaultException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
        if (identity.unlockThrottled) {
          _startLockoutTicker();
        }
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not unlock the wallet.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _confirmReset() async {
    final WalletIdentityController identity =
        context.read<WalletIdentityController>();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Remove this wallet?'),
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

    if (!(confirmed ?? false) || !mounted) {
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

/// Small error-toned notice shown while a wrong-PIN penalty is counting down.
class _ThrottleNotice extends StatelessWidget {
  const _ThrottleNotice({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.timer_outlined, size: 18, color: scheme.error),
        const SizedBox(width: 6),
        Text(
          hint,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.error),
        ),
      ],
    );
  }
}
