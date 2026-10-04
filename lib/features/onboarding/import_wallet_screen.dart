import 'package:flutter/material.dart';

import '../../state/wallet_identity_controller.dart';
import '../lock/set_pin_screen.dart';

/// Restores an existing wallet from a BIP-39 recovery phrase.
class ImportWalletScreen extends StatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  final TextEditingController _phraseController = TextEditingController();

  @override
  void dispose() {
    _phraseController.dispose();
    super.dispose();
  }

  String get _normalized =>
      WalletIdentityController.normalize(_phraseController.text);

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
      appBar: AppBar(title: const Text('Import wallet')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: <Widget>[
                  Text(
                    'Enter your recovery phrase',
                    style: text.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Type or paste the 12 or 24 words separated by spaces. The '
                    'checksum is verified locally before anything is stored.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _phraseController,
                    minLines: 3,
                    maxLines: 5,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Recovery phrase',
                      hintText: 'word one word two word three …',
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
                              ? 'Waiting for your phrase'
                              : _isValid
                                  ? 'Valid $_wordCount-word phrase'
                                  : '$_wordCount word(s) — checksum not valid yet',
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
                child: const Text('Continue'),
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
        builder: (_) => SetPinScreen(mnemonic: _normalized),
      ),
    );
  }
}
