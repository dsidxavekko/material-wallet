import 'package:flutter/material.dart';

import '../../state/wallet_identity_controller.dart';
import '../wallets/add_wallet_screen.dart';
import '../../l10n/l10n.dart';

/// Restores an existing wallet from a BIP-39 recovery phrase.
class ImportWalletScreen extends StatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  final TextEditingController _phraseController = TextEditingController();
  final TextEditingController _passphraseController = TextEditingController();

  @override
  void dispose() {
    _phraseController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  String get _normalized =>
      WalletIdentityController.normalize(_phraseController.text);

  /// BIP-39 passphrases are case-sensitive and whitespace-significant, so only
  /// the line breaks a paste can carry are stripped — never trimmed further.
  String get _passphrase =>
      _passphraseController.text.replaceAll(RegExp(r'[\r\n]+'), ' ');

  int get _wordCount =>
      _normalized.isEmpty ? 0 : _normalized.split(' ').length;

  bool get _isValid =>
      _normalized.isNotEmpty &&
      WalletIdentityController.isValidMnemonic(_normalized);

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.importWallet)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: <Widget>[
                  Text(
                    context.l10n.enterYourRecoveryPhrase,
                    style: text.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.typeOrPasteThe12,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _PassphraseNotice(),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _phraseController,
                    minLines: 3,
                    maxLines: 5,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: context.l10n.recoveryPhrase,
                      hintText: context.l10n.wordOneWordTwoWord,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _passphraseController,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: context.l10n.passphrase25thWordOptional,
                      hintText: context.l10n.leaveEmptyIfYouNever,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Icon(
                        _isValid
                            ? Icons.verified_rounded
                            : Icons.info_outline_rounded,
                        size: 16,
                        color: _isValid
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _wordCount == 0
                              ? context.l10n.waitingForYourPhrase
                              : _isValid
                                  ? context.l10n.validWordPhrase(_wordCount)
                                  : context.l10n.wordSChecksumNotValid(_wordCount),
                          style: text.bodySmall?.copyWith(
                            color: _isValid
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton(
                onPressed: _isValid ? _continue : null,
                child: Text(context.l10n.continueLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _continue() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => securityStepFor(
          context,
          mnemonic: _normalized,
          passphrase: _passphrase,
        ),
      ),
    );
  }
}

/// Explains what the optional 25th word does.
///
/// BIP-39 lets a phrase carry a passphrase that never appears in the phrase
/// itself. Getting it wrong does not raise an error — it silently derives a
/// *different* set of addresses, so every balance reads as zero and the user
/// has no way to tell why. Saying so here is the difference between "this app
/// is broken" and "I typed the wrong passphrase".
class _PassphraseNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, color: scheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.ifYourPhraseWasCreated,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
