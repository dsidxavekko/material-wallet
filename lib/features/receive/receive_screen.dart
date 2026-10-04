import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/utils/explorer.dart';
import '../../core/utils/feedback.dart';
import '../../data/networks/network_config.dart';
import '../../shared/widgets/empty_state.dart';
import '../../state/settings_controller.dart';
import '../../state/wallet_controller.dart';

/// Shows the wallet's **real** receive address for the active network, both as
/// text and as a scannable QR code.
class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final WalletController wallet = context.watch<WalletController>();
    final NetworkConfig network =
        context.select<SettingsController, NetworkConfig>((s) => s.network);
    final String? address = wallet.address;
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (address == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Receive')),
        body: const EmptyState(
          icon: Icons.key_off_rounded,
          title: 'No wallet found',
          message: 'Unlock your wallet to generate a receive address.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Card(
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
                network.isTestnet
                    ? '${network.group} · Testnet'
                    : network.group,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(child: _QrCard(data: address)),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Scan to receive ${network.symbol}',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Only send ${network.symbol} on ${network.name} to this address.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 26),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Your address',
                    style: text.labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    address,
                    style: text.bodyMedium
                        ?.copyWith(height: 1.45, letterSpacing: 0.2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _copy(context, address),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy address'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => openExplorer(
              context,
              network.explorerAddress(address),
            ),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('View on explorer'),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Address copied to clipboard',
        icon: Icons.check_circle_outline_rounded,
      );
    }
  }
}

/// White card hosting the QR code so it stays scannable in dark mode.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: QrImageView(
        data: data,
        version: QrVersions.auto,
        size: 208,
        gapless: true,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      ),
    );
  }
}
