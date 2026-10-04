import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';

/// Colored pill that renders a signed 24h percentage change.
class ChangeBadge extends StatelessWidget {
  const ChangeBadge({super.key, required this.change, this.dense = false});

  /// Percentage change, e.g. `-1.24`.
  final double change;

  /// Compact variant used inside dense list tiles.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppSemanticColors semantic = Theme.of(context).semanticColors;
    final bool up = change >= 0;
    final Color foreground =
        up ? semantic.onPositiveContainer : semantic.onNegativeContainer;
    final Color background =
        up ? semantic.positiveContainer : semantic.negativeContainer;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: dense ? 14 : 16,
            color: foreground,
          ),
          const SizedBox(width: 4),
          Text(
            AppFormat.percent(change),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
