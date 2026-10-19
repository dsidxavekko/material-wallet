import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../data/wallet/seed_vault.dart';
import '../../data/wallet/watch_address.dart';
import '../../state/wallet_identity_controller.dart';
import '../scan/scan_screen.dart';

/// Follows addresses without holding any key: balances, tokens and history,
/// but never a send.
///
/// A wallet takes one address per chain family; pasting an address is enough —
/// the family is recognised from the address itself.
class WatchWalletScreen extends StatefulWidget {
  const WatchWalletScreen({super.key});

  @override
  State<WatchWalletScreen> createState() => _WatchWalletScreenState();
}

class _WatchWalletScreenState extends State<WatchWalletScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  /// Family → address, in the order the user added them.
  final Map<String, WatchAddress> _added = <String, WatchAddress>{};
  String? _addressError;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _addFrom(String raw) {
    final String text = WatchAddresses.extract(raw);
    final WatchAddress? found = WatchAddresses.detect(text);
    if (found == null) {
      setState(() => _addressError = WatchAddresses.explain(text) ??
          'Enter an address to follow');
      return;
    }
    setState(() {
      _added[found.family] = found;
      _addressController.clear();
      _addressError = null;
    });
  }

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = data?.text ?? '';
    if (text.trim().isEmpty || !mounted) {
      return;
    }
    _addFrom(text);
  }

  Future<void> _scan() async {
    final String? value = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const ScanScreen(title: 'Scan an address'),
      ),
    );
    if (value != null && mounted) {
      _addFrom(value);
    }
  }

  Future<void> _save() async {
    // An address still sitting in the field counts: forgetting to press "Add"
    // should not discard what the user typed.
    if (_addressController.text.trim().isNotEmpty) {
      _addFrom(_addressController.text);
      if (_addressError != null) {
        return;
      }
    }
    if (_added.isEmpty) {
      setState(() => _addressError = 'Enter an address to follow');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<WalletIdentityController>().addWatchWallet(
            name: _nameController.text,
            addresses: <String, String>{
              for (final WatchAddress a in _added.values) a.family: a.address,
            },
          );
    } on SeedVaultException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _addressError = error.message;
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    showAppSnackBar(
      context,
      'Following ${_added.length} address${_added.length == 1 ? '' : 'es'}.',
      icon: Icons.visibility_outlined,
    );
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Watch-only wallet')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: <Widget>[
                  Text(
                    'Follow an address',
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'See the balance, tokens and history of an address you do '
                    'not hold the keys for — a cold wallet, a savings account '
                    'or a friend\'s public address. Nothing secret is stored '
                    'and this wallet can never send.',
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
                    decoration: const InputDecoration(
                      labelText: 'Name (optional)',
                      hintText: 'e.g. Cold storage',
                      prefixIcon: Icon(Icons.label_outline_rounded),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _addressController,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    minLines: 1,
                    maxLines: 3,
                    onChanged: (_) => setState(() => _addressError = null),
                    onSubmitted: _addFrom,
                    decoration: InputDecoration(
                      labelText: 'Address',
                      hintText: 'bc1…, 0x…, Solana or Aptos address',
                      errorText: _addressError,
                      prefixIcon: const Icon(Icons.visibility_outlined),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Paste',
                            icon: const Icon(Icons.content_paste_rounded),
                            onPressed: _busy ? null : _paste,
                          ),
                          IconButton(
                            tooltip: 'Scan',
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            onPressed: _busy ? null : _scan,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _addFrom(_addressController.text),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add address'),
                    ),
                  ),
                  if (_added.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    for (final WatchAddress a in _added.values)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.check_circle_outline_rounded),
                          title: Text(a.label),
                          subtitle: Text(
                            a.address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: _busy
                                ? null
                                : () => setState(() => _added.remove(a.family)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'One address per kind: an EVM address is the same on '
                      'Ethereum, Base, Polygon, Arbitrum, BNB Chain and '
                      'Sepolia.',
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.visibility_rounded),
                label: const Text('Follow'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
