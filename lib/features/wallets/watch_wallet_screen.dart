import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/crypto/ens.dart';
import '../../core/utils/feedback.dart';
import '../../data/networks/chain_api.dart';
import '../../data/wallet/seed_vault.dart';
import '../../data/wallet/wallet_entry.dart';
import '../../data/wallet/watch_address.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_identity_controller.dart';
import '../scan/scan_screen.dart';
import '../../l10n/l10n.dart';
import '../../l10n/messages.dart';

/// Follows addresses without holding any key: balances, tokens and history,
/// but never a send.
///
/// A wallet takes one address per chain family; pasting an address is enough —
/// the family is recognised from the address itself, and an ENS name
/// (`name.eth`) is resolved to the EVM address it points to.
///
/// Given an [editing] wallet it changes that wallet's name and addresses
/// instead of creating a new one.
class WatchWalletScreen extends StatefulWidget {
  const WatchWalletScreen({super.key, this.editing});

  final WalletEntry? editing;

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

  /// ENS names that were resolved, by the address they gave (shown in the list).
  final Map<String, String> _ensNames = <String, String>{};

  @override
  void initState() {
    super.initState();
    final WalletEntry? editing = widget.editing;
    if (editing != null) {
      _nameController.text = editing.name;
      for (final MapEntry<String, String> e in editing.watched.entries) {
        _added[e.key] = WatchAddress(
          family: e.key,
          label: WatchAddresses.labels[e.key] ?? e.key,
          address: e.value,
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _addFrom(String raw) async {
    final String text = WatchAddresses.extract(raw);
    if (Ens.looksLikeName(text)) {
      await _addEns(text);
      return;
    }
    final WatchAddress? found = WatchAddresses.detect(text);
    if (found == null) {
      setState(() => _addressError = (WatchAddresses.explain(text) == null ? null : tr(WatchAddresses.explain(text)!)) ??
          context.l10n.enterAnAddressToFollow);
      return;
    }
    setState(() {
      _added[found.family] = found;
      _addressController.clear();
      _addressError = null;
    });
  }

  /// Resolves `name.eth` to the address it points to *now*. Only that address is
  /// kept, so the wallet keeps following it even if the name is repointed.
  Future<void> _addEns(String input) async {
    final AppLocalizations l10n = context.l10n;
    final String? name = Ens.normalize(input);
    if (name == null) {
      setState(() => _addressError =
          context.l10n.thisNameHasCharactersThe);
      return;
    }
    setState(() {
      _busy = true;
      _addressError = null;
    });
    String? address;
    String? failure;
    try {
      address = await context.read<WalletController>().resolveEns(name);
    } on ChainApiException catch (error) {
      failure = tr(error.message);
    } catch (_) {
      failure = l10n.couldNotLookTheName;
    }
    if (!mounted) {
      return;
    }
    final WatchAddress? found =
        address == null ? null : WatchAddresses.detect(address);
    setState(() {
      _busy = false;
      if (found == null) {
        _addressError = failure ?? l10n.pointsToNoAddress(name);
        return;
      }
      _added[found.family] = found;
      _ensNames[found.address] = name;
      _addressController.clear();
    });
  }

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = data?.text ?? '';
    if (text.trim().isEmpty || !mounted) {
      return;
    }
    await _addFrom(text);
  }

  Future<void> _scan() async {
    final String? value = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ScanScreen(title: context.l10n.scanAnAddress),
      ),
    );
    if (value != null && mounted) {
      await _addFrom(value);
    }
  }

  Future<void> _save() async {
    // An address still sitting in the field counts: forgetting to press "Add"
    // should not discard what the user typed.
    if (_addressController.text.trim().isNotEmpty) {
      await _addFrom(_addressController.text);
      if (_addressError != null || !mounted) {
        return;
      }
    }
    if (_added.isEmpty) {
      setState(() => _addressError = context.l10n.enterAnAddressToFollow);
      return;
    }
    setState(() => _busy = true);
    final Map<String, String> addresses = <String, String>{
      for (final WatchAddress a in _added.values) a.family: a.address,
    };
    final WalletEntry? editing = widget.editing;
    try {
      if (editing == null) {
        await context.read<WalletIdentityController>().addWatchWallet(
              name: _nameController.text,
              addresses: addresses,
            );
      } else {
        await context.read<WalletIdentityController>().updateWatchWallet(
              id: editing.id,
              name: _nameController.text,
              addresses: addresses,
            );
      }
    } on SeedVaultException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _addressError = tr(error.message);
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    showAppSnackBar(
      context,
      editing == null
          ? context.l10n.addressOtherAddresses(_added.length)
          : context.l10n.walletUpdated,
      icon: Icons.visibility_outlined,
    );
    if (editing == null) {
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null
            ? context.l10n.watchOnlyWallet
            : context.l10n.editWatchOnlyWallet),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: <Widget>[
                  Text(
                    context.l10n.followAnAddress,
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.seeTheBalanceTokensAnd,
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
                      hintText: context.l10n.eGColdStorage,
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
                    onSubmitted: (String v) => _addFrom(v),
                    decoration: InputDecoration(
                      labelText: context.l10n.address,
                      hintText: context.l10n.bc10xNameEthSolana,
                      errorText: _addressError,
                      prefixIcon: const Icon(Icons.visibility_outlined),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: context.l10n.paste,
                            icon: const Icon(Icons.content_paste_rounded),
                            onPressed: _busy ? null : _paste,
                          ),
                          IconButton(
                            tooltip: context.l10n.scan,
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
                      label: Text(context.l10n.addAddress),
                    ),
                  ),
                  if (_added.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    for (final WatchAddress a in _added.values)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.check_circle_outline_rounded),
                          title: Text(tr(a.label)),
                          subtitle: Text(
                            _ensNames[a.address] == null
                                ? a.address
                                : '${_ensNames[a.address]} → ${a.address}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: context.l10n.remove3,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: _busy
                                ? null
                                : () => setState(() => _added.remove(a.family)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.oneAddressPerKindAn,
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
                label: Text(widget.editing == null ? context.l10n.follow : context.l10n.save),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
