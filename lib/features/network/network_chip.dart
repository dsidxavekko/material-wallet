import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/networks/network_config.dart';
import '../../state/settings_controller.dart';
import 'network_picker.dart';

/// Pill showing the active network that opens the network picker when tapped.
class NetworkChip extends StatelessWidget {
  const NetworkChip({super.key});

  @override
  Widget build(BuildContext context) {
    final NetworkConfig network =
        context.select<SettingsController, NetworkConfig>((s) => s.network);
    final TextTheme text = Theme.of(context).textTheme;

    return Material(
      color: network.color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => showNetworkPicker(context),
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: network.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                network.name,
                style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
