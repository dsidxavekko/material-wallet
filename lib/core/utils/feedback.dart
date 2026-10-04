import 'package:flutter/material.dart';

/// Shows a floating snack bar with an optional leading icon.
///
/// Centralised so every screen produces consistent feedback and any currently
/// visible snack bar is replaced instead of queued.
void showAppSnackBar(BuildContext context, String message, {IconData? icon}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final Color onSurface = Theme.of(context).colorScheme.onInverseSurface;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, color: onSurface, size: 20),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(message)),
        ],
      ),
      duration: const Duration(seconds: 3),
    ),
  );
}
