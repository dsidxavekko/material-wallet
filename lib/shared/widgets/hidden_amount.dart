import 'package:flutter/material.dart';

/// Renders a formatted value, replacing it with dots while [hidden] is true.
///
/// Used to blur out the portfolio balance when privacy mode is enabled.
class HiddenAmount extends StatelessWidget {
  const HiddenAmount({
    super.key,
    required this.text,
    required this.hidden,
    this.style,
    this.dotCount = 6,
  });

  final String text;
  final bool hidden;
  final TextStyle? style;
  final int dotCount;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Text(
        hidden ? '•' * dotCount : text,
        key: ValueKey<bool>(hidden),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
