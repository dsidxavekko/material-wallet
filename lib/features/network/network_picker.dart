import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/networks/network_config.dart';
import '../../state/settings_controller.dart';

/// Opens the network picker and applies the chosen network.
Future<void> showNetworkPicker(BuildContext context) async {
  final SettingsController settings = context.read<SettingsController>();
  final NetworkConfig current = settings.network;

  final NetworkConfig? picked = await showModalBottomSheet<NetworkConfig>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final TextTheme text = Theme.of(sheetContext).textTheme;
      final ColorScheme scheme = Theme.of(sheetContext).colorScheme;

      Widget section(String title, List<NetworkConfig> networks) {
        if (networks.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                title.toUpperCase(),
                style: text.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            for (final NetworkConfig network in networks)
              _NetworkTile(
                network: network,
                selected: network.id == current.id,
                onTap: () => Navigator.of(sheetContext).pop(network),
              ),
          ],
        );
      }

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'Network',
                  style: text.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              section('Mainnets', NetworkCatalog.mainnets),
              section('Testnets', NetworkCatalog.testnets),
            ],
          ),
        ),
      );
    },
  );

  if (picked != null) {
    settings.setNetwork(picked);
  }
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({
    required this.network,
    required this.selected,
    required this.onTap,
  });

  final NetworkConfig network;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
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
        network.isTestnet ? '${network.group} · Testnet' : network.group,
        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: scheme.primary)
          : null,
    );
  }
}
