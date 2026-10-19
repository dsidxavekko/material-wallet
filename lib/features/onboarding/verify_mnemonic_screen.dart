import 'dart:math';

import 'package:flutter/material.dart';

import '../wallets/add_wallet_screen.dart';
import '../../l10n/l10n.dart';

/// Asks the user to re-type a few **randomly chosen** words to prove the
/// recovery phrase was backed up.
///
/// Both the number of checks (3–5) and the positions are drawn from
/// [Random.secure], so no fixed set of word numbers ever repeats. Only after
/// the check passes does the flow continue to setting a PIN, which encrypts
/// and stores the wallet.
class VerifyMnemonicScreen extends StatefulWidget {
  const VerifyMnemonicScreen({super.key, required this.mnemonic});

  final String mnemonic;

  @override
  State<VerifyMnemonicScreen> createState() => _VerifyMnemonicScreenState();
}

class _VerifyMnemonicScreenState extends State<VerifyMnemonicScreen> {
  static const int _minChecks = 3;
  static const int _maxChecks = 5;

  late final List<String> _words = widget.mnemonic.split(' ');
  late final List<int> _indices = _pickIndices();
  late final List<TextEditingController> _controllers =
      List<TextEditingController>.generate(
    _indices.length,
    (_) => TextEditingController(),
  );

  /// Draws a fresh, unpredictable set of word positions for this attempt.
  List<int> _pickIndices() {
    final Random random = Random.secure();
    final int checks =
        _minChecks + random.nextInt(_maxChecks - _minChecks + 1);

    final Set<int> picked = <int>{};
    while (picked.length < checks) {
      picked.add(random.nextInt(_words.length));
    }
    return picked.toList()..sort();
  }

  bool get _isValid {
    for (int i = 0; i < _indices.length; i++) {
      final String entered = _controllers[i].text.trim().toLowerCase();
      if (entered != _words[_indices[i]]) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.verifyBackup)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: <Widget>[
                  Text(
                    context.l10n.confirmYourRecoveryPhrase,
                    style: text.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.typeTheWordsBelowExactly,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  for (int i = 0; i < _indices.length; i++) ...<Widget>[
                    TextField(
                      controller: _controllers[i],
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: context.l10n.word(_indices[i] + 1),
                        hintText: context.l10n.typeTheWord,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
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
        builder: (_) => securityStepFor(context, mnemonic: widget.mnemonic),
      ),
    );
  }
}
