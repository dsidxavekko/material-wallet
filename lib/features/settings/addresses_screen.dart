import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../data/networks/network_config.dart';
import '../../shared/widgets/qr_card.dart';
import '../../state/wallet_identity_controller.dart';

/// Every receive address the wallet derives, one per supported network.
///
/// Lets the user check — and show the QR for — any chain without first
/// switching the whole app to that network.
class AddressesScreen extends StatelessWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final WalletIdentityController identity =
        context.watch<WalletIdentityController>();
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Your addresses')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Card(
            color: scheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Icon(Icons.verified_user_outlined,
                      color: scheme.onTertiaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Before receiving large amounts, check these addresses '
                      'against your recovery phrase on a second, trusted '
                      'device.',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final NetworkConfig network in NetworkCatalog.all) ...<Widget>[
            const SizedBox(height: 18),
            _SectionTitle(network.group),
            _AddressTile(
              network: network,
              address: identity.addressFor(network),
            ),
          ],
        ],
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
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({required this.network, required this.address});

  final NetworkConfig network;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String value = address ?? 'Locked';
    final bool hasAddress = address != null;

    return Card(
      child: ListTile(
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: network.color.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Text(
            network.symbol.length > 3
                ? network.symbol.substring(0, 3)
                : network.symbol,
            style: text.labelSmall?.copyWith(
              color: network.color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Text(
          network.name,
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          hasAddress ? AppFormat.shortAddress(value, head: 10, tail: 8) : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        trailing: IconButton(
          tooltip: 'Copy address',
          icon: const Icon(Icons.copy_rounded),
          onPressed: hasAddress ? () => _copy(context, value) : null,
        ),
        onTap: hasAddress
            ? () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => _QrSheet(network: network, address: value),
                )
            : null,
      ),
    );
  }

  Future<void> _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Address copied to clipboard',
        icon: Icons.check_circle_outline_rounded,
      );
    }
  }
}

class _QrSheet extends StatelessWidget {
  const _QrSheet({required this.network, required this.address});

  final NetworkConfig network;
  final String address;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              network.name,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            QrCard(data: address, size: 220),
            const SizedBox(height: 16),
            SelectableText(
              address,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 8),
            Text(
              'Only send ${network.symbol} on ${network.name} here.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
