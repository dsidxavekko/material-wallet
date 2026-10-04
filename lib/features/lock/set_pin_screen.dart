import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../data/wallet/seed_vault.dart';
import '../../shared/widgets/pin_field.dart';
import '../../state/wallet_identity_controller.dart';

/// Sets a PIN and encrypts the recovery phrase with it.
///
/// Used when creating a new wallet and when importing an existing one, so the
/// phrase is never written to disk in the clear.
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key, required this.mnemonic});

  /// The phrase that will be encrypted under the chosen PIN.
  final String mnemonic;

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  static const int _minLength = 6;

  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String? _pinError;
  String? _confirmError;
  bool _busy = false;
  bool _biometricSupported = false;
  bool _useBiometrics = false;

  @override
  void initState() {
    super.initState();
    _detectBiometrics();
  }

  /// Offers fingerprint unlock when the device supports it.
  Future<void> _detectBiometrics() async {
    final bool supported =
        await context.read<WalletIdentityController>().canUseBiometrics();
    if (!mounted || !supported) {
      return;
    }
    setState(() {
      _biometricSupported = true;
      _useBiometrics = true;
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _pinController.text.length >= _minLength &&
      _pinController.text == _confirmController.text;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: <Widget>[
                  Text(
                    'Set a PIN',
                    style: text.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your recovery phrase is encrypted with AES-256-GCM using '
                    'a key derived from this PIN, and you will need it every '
                    'time you open the wallet.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  PinField(
                    controller: _pinController,
                    label: 'PIN (min. $_minLength digits)',
                    autofocus: true,
                    enabled: !_busy,
                    errorText: _pinError,
                    onChanged: (_) => setState(() {
                      _pinError = null;
                      _confirmError = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  PinField(
                    controller: _confirmController,
                    label: 'Confirm PIN',
                    enabled: !_busy,
                    errorText: _confirmError,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) => setState(() => _confirmError = null),
                  ),
                  if (_biometricSupported) ...<Widget>[
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: SwitchListTile(
                        value: _useBiometrics,
                        onChanged: _busy
                            ? null
                            : (bool value) =>
                                setState(() => _useBiometrics = value),
                        secondary: const Icon(Icons.fingerprint_rounded),
                        title: const Text('Unlock with fingerprint'),
                        subtitle: const Text(
                          'Open the wallet with your fingerprint instead of '
                          'typing the PIN',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.warning_amber_rounded,
                          color: scheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'There is no PIN recovery. If you forget it you '
                            'will need your recovery phrase to restore the '
                            'wallet.',
                            style: text.bodySmall?.copyWith(
                              color: scheme.onErrorContainer,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.enhanced_encryption_rounded),
                label: Text(_busy ? 'Encrypting…' : 'Encrypt & continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final String pin = _pinController.text;

    if (!_isValid) {
      setState(() {
        _pinError =
            pin.length < _minLength ? 'Use at least $_minLength digits' : null;
        _confirmError =
            pin != _confirmController.text ? 'PINs do not match' : null;
      });
      return;
    }

    setState(() => _busy = true);

    try {
      await context.read<WalletIdentityController>().createWallet(
            mnemonic: widget.mnemonic,
            pin: pin,
            useBiometrics: _useBiometrics,
          );
    } on SeedVaultException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _pinError = error.message;
        });
      }
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    showAppSnackBar(
      context,
      'Wallet encrypted and stored on this device.',
      icon: Icons.verified_user_outlined,
    );
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }
}
