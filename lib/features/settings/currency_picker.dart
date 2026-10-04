import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';

/// Shows the fiat-currency picker and returns the chosen currency.
///
/// Shared by the settings screen and the balance card so the selector behaves
/// identically wherever the user taps it.
Future<AppCurrency?> showCurrencyPicker(
  BuildContext context, {
  required AppCurrency current,
}) {
  return showModalBottomSheet<AppCurrency>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final TextTheme text = Theme.of(sheetContext).textTheme;
      final ColorScheme scheme = Theme.of(sheetContext).colorScheme;

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Display currency',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final AppCurrency currency in AppCurrency.values)
              ListTile(
                leading: Icon(
                  currency == current
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: currency == current
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                title: Text(currency.label),
                subtitle: Text(
                  '1 USD ≈ ${currency.usdRate.toStringAsFixed(2)} ${currency.code}',
                ),
                onTap: () => Navigator.of(sheetContext).pop(currency),
              ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}
