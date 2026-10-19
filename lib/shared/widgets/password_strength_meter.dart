import 'package:flutter/material.dart';

import '../../core/utils/password_strength.dart';

/// A thin bar and a short label that reads how strong the typed password is.
/// Advisory only; see [assessPassword].
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) {
      return const SizedBox.shrink();
    }
    final PasswordAssessment a = assessPassword(password);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final (String label, double value, Color color) = switch (a.strength) {
      PasswordStrength.weak => ('Weak', 0.25, scheme.error),
      PasswordStrength.fair => ('Fair', 0.5, scheme.tertiary),
      PasswordStrength.good => ('Good', 0.75, scheme.primary),
      PasswordStrength.strong => ('Strong', 1.0, scheme.primary),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            a.hint == null ? label : '$label — ${a.hint}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
