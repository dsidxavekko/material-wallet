import 'package:crypto_wallet/core/theme/app_theme.dart';
import 'package:crypto_wallet/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a system colour scheme (Material You) drives the whole theme', () {
    final ColorScheme system = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00A86B),
    );
    final ThemeData theme = AppTheme.light(system);

    expect(theme.colorScheme.primary, system.primary);
    expect(theme.colorScheme.surface, system.surface);
    expect(theme.navigationBarTheme.indicatorColor, system.secondaryContainer);
    expect(theme.cardTheme.color, system.surfaceContainerLow);
  });

  test('without system colours the brand seed is used, light and dark', () {
    expect(
      AppTheme.light().colorScheme.primary,
      ColorScheme.fromSeed(seedColor: AppTheme.seed).primary,
    );
    expect(
      AppTheme.dark().colorScheme.primary,
      ColorScheme.fromSeed(
        seedColor: AppTheme.seed,
        brightness: Brightness.dark,
      ).primary,
    );
    expect(AppTheme.dark().brightness, Brightness.dark);
  });

  test('gain/loss colours stay green and red whatever the system palette', () {
    final ColorScheme purple = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7B1FA2),
    );
    final AppSemanticColors semantic = AppTheme.light(purple).semanticColors;
    expect(semantic.positive, AppSemanticColors.light.positive);
    expect(semantic.negative, AppSemanticColors.light.negative);
  });
}
