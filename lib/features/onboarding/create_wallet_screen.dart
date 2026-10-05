import 'package:flutter/material.dart';

import '../../core/utils/clipboard.dart';
import '../../core/utils/feedback.dart';
import '../../shared/widgets/mnemonic_grid.dart';
import '../../state/wallet_identity_controller.dart';
import 'verify_mnemonic_screen.dart';

/// Generates and reveals a brand new BIP-39 recovery phrase.
class CreateWalletScreen extends StatefulWidget {
  const CreateWalletScreen({super.key});

  @override
  State<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends State<CreateWalletScreen> {
  late final String _mnemonic = WalletIdentityController.generateMnemonic();
  late final List<String> _words = _mnemonic.split(' ');
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Your recovery phrase')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: <Widget>[
                  Text(
                    'Write these ${_words.length} words down',
                    style: text.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'They are the only way to restore your wallet. Store them '
                    'offline — anyone who reads them can take your funds.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  MnemonicGrid(words: _words),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: _copyPhrase,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy phrase'),
                  ),
                  const SizedBox(height: 18),
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
                            'Never share this phrase. Material Wallet will never '
                            'ask you for it.',
                            style: text.bodySmall?.copyWith(
                              color: scheme.onErrorContainer,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _confirmed,
                    onChanged: (bool? value) =>
                        setState(() => _confirmed = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'I have written down my recovery phrase',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton(
                onPressed: _confirmed ? _continue : null,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyPhrase() async {
    await copySensitiveText(_mnemonic);
    if (mounted) {
      showAppSnackBar(
        context,
        'Recovery phrase copied — cleared automatically',
        icon: Icons.copy_rounded,
      );
    }
  }

  void _continue() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VerifyMnemonicScreen(mnemonic: _mnemonic),
      ),
    );
  }
}
