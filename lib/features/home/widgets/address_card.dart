import 'package:flutter/material.dart';

/// Card showing the full receive address with copy and explorer actions.
class AddressCard extends StatelessWidget {
  const AddressCard({
    super.key,
    required this.address,
    required this.networkLabel,
    required this.onCopy,
    required this.onExplorer,
  });

  final String address;
  final String networkLabel;
  final VoidCallback onCopy;
  final VoidCallback onExplorer;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.link_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your address · $networkLabel',
                    style: text.labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              address,
              style: text.bodyMedium?.copyWith(height: 1.45, letterSpacing: 0.2),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onExplorer,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Explorer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
