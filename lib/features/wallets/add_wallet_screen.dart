import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../data/wallet/seed_vault.dart';
import '../../shared/widgets/pin_field.dart';
import '../../state/wallet_identity_controller.dart';
import '../lock/set_pin_screen.dart';
import '../../l10n/l10n.dart';
import '../../l10n/messages.dart';

/// The step after a phrase has been created or typed in: where it is secured.
///
/// On a device with no password yet that is [SetPinScreen] (choose one); on a
/// device that already has one it is [AddWalletScreen], which checks the
/// existing password and stores the phrase next to the others.
Widget securityStepFor(
  BuildContext context, {
  required String mnemonic,
  String passphrase = '',
}) {
  final bool hasVault = context.read<WalletIdentityController>().hasVault;
  return hasVault
      ? AddWalletScreen(mnemonic: mnemonic, passphrase: passphrase)
      : SetPinScreen(mnemonic: mnemonic, passphrase: passphrase);
}

/// Adds a recovery phrase to a vault that already exists.
///
/// The phrase is encrypted under the *same* password as the others: one unlock
/// opens every wallet, and the password asked for here proves the person at the
/// screen is the owner before the vault is rewritten.
class AddWalletScreen extends StatefulWidget {
  const AddWalletScreen({super.key, required this.mnemonic, this.passphrase = ''});

  final String mnemonic;
  final String passphrase;

  @override
  State<AddWalletScreen> createState() => _AddWalletScreenState();
}

class _AddWalletScreenState extends State<AddWalletScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_passwordController.text.isEmpty) {
      setState(() => _error = context.l10n.enterYourCurrentPassword);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<WalletIdentityController>().addSeedWallet(
            mnemonic: widget.mnemonic,
            passphrase: widget.passphrase,
            password: _passwordController.text,
            name: _nameController.text,
          );
    } on SeedVaultException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr(error.message);
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    showAppSnackBar(
      context,
      context.l10n.walletAddedAndEncryptedOn,
      icon: Icons.verified_user_outlined,
    );
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.addWallet)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: <Widget>[
                  Text(
                    context.l10n.confirmWithYourPassword,
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.thisPhraseWillBeEncrypted,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _nameController,
                    maxLength: 30,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: context.l10n.nameOptional,
                      hintText: context.l10n.eGSavings,
                      prefixIcon: Icon(Icons.label_outline_rounded),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  PinField(
                    controller: _passwordController,
                    label: context.l10n.currentPassword,
                    autofocus: true,
                    enabled: !_busy,
                    errorText: _error,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) => setState(() => _error = null),
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
                label: Text(_busy ? context.l10n.encrypting : context.l10n.addWallet),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
