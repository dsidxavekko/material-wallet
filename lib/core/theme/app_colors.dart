import 'package:flutter/material.dart';

/// Semantic colors that are not part of the Material [ColorScheme].
///
/// Registered through [ThemeData.extensions] so they resolve automatically for
/// both the light and dark themes, and can be read with
/// `Theme.of(context).semanticColors`.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.positive,
    required this.positiveContainer,
    required this.onPositiveContainer,
    required this.negative,
    required this.negativeContainer,
    required this.onNegativeContainer,
  });

  /// Used for upward market movement (green).
  final Color positive;
  final Color positiveContainer;
  final Color onPositiveContainer;

  /// Used for downward market movement (red).
  final Color negative;
  final Color negativeContainer;
  final Color onNegativeContainer;

  static const AppSemanticColors light = AppSemanticColors(
    positive: Color(0xFF0F9D58),
    positiveContainer: Color(0xFFD3F3E0),
    onPositiveContainer: Color(0xFF04361F),
    negative: Color(0xFFD93025),
    negativeContainer: Color(0xFFFDE6E4),
    onNegativeContainer: Color(0xFF410E0B),
  );

  static const AppSemanticColors dark = AppSemanticColors(
    positive: Color(0xFF6BDCA4),
    positiveContainer: Color(0xFF0F452C),
    onPositiveContainer: Color(0xFFB6F1CE),
    negative: Color(0xFFFF8F86),
    negativeContainer: Color(0xFF5C1A16),
    onNegativeContainer: Color(0xFFFFDAD6),
  );

  @override
  AppSemanticColors copyWith({
    Color? positive,
    Color? positiveContainer,
    Color? onPositiveContainer,
    Color? negative,
    Color? negativeContainer,
    Color? onNegativeContainer,
  }) {
    return AppSemanticColors(
      positive: positive ?? this.positive,
      positiveContainer: positiveContainer ?? this.positiveContainer,
      onPositiveContainer: onPositiveContainer ?? this.onPositiveContainer,
      negative: negative ?? this.negative,
      negativeContainer: negativeContainer ?? this.negativeContainer,
      onNegativeContainer: onNegativeContainer ?? this.onNegativeContainer,
    );
  }

  @override
  AppSemanticColors lerp(
    ThemeExtension<AppSemanticColors>? other,
    double t,
  ) {
    if (other is! AppSemanticColors) {
      return this;
    }
    return AppSemanticColors(
      positive: Color.lerp(positive, other.positive, t)!,
      positiveContainer:
          Color.lerp(positiveContainer, other.positiveContainer, t)!,
      onPositiveContainer:
          Color.lerp(onPositiveContainer, other.onPositiveContainer, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      negativeContainer:
          Color.lerp(negativeContainer, other.negativeContainer, t)!,
      onNegativeContainer:
          Color.lerp(onNegativeContainer, other.onNegativeContainer, t)!,
    );
  }
}

/// Convenience accessor for the semantic color extension.
extension SemanticColorsX on ThemeData {
  AppSemanticColors get semanticColors =>
      extension<AppSemanticColors>() ?? AppSemanticColors.light;
}
