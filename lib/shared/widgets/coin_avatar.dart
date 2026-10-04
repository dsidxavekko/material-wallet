import 'package:flutter/material.dart';

/// Round token badge filled with the coin's brand gradient.
///
/// Uses the ticker symbol instead of a bitmap logo so no image assets are
/// required and every coin has a consistent look.
class CoinAvatar extends StatelessWidget {
  const CoinAvatar({
    super.key,
    required this.symbol,
    required this.color,
    this.size = 44,
  });

  final String symbol;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.lerp(color, Colors.white, 0.28)!,
            color,
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            symbol,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.36,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
