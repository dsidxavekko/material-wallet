import 'package:flutter/material.dart';

/// Row of the two wallet operations available in this app.
///
/// Both buttons are wide pills that fill the available width, with the icon and
/// label side by side.
class QuickActions extends StatelessWidget {
  const QuickActions({
    super.key,
    required this.onSend,
    required this.onReceive,
  });

  final VoidCallback onSend;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _QuickAction(
          icon: Icons.north_east_rounded,
          label: 'Send',
          emphasized: true,
          onTap: onSend,
        ),
        const SizedBox(width: 14),
        _QuickAction(
          icon: Icons.south_west_rounded,
          label: 'Receive',
          onTap: onReceive,
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color background =
        emphasized ? scheme.primary : scheme.surfaceContainerHighest;
    final Color foreground =
        emphasized ? scheme.onPrimary : scheme.onSurfaceVariant;

    return Expanded(
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 66,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: foreground, size: 24),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

