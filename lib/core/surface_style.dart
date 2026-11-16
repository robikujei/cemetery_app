import 'package:flutter/material.dart';

/// A static sheen: adds depth without animation or expensive backdrop filters.
class SurfaceStyle {
  static LinearGradient sheen(Color base) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: const [0, 0.46, 0.49, 1],
    colors: [
      Color.lerp(base, Colors.white, 0.22)!,
      Color.lerp(base, Colors.white, 0.08)!,
      base,
      Color.lerp(base, const Color(0xFF294C3B), 0.08)!,
    ],
  );

  static BoxDecoration panel({
    Color color = Colors.white,
    double radius = 24,
  }) => BoxDecoration(
    gradient: sheen(color),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x18335538),
        blurRadius: 24,
        offset: Offset(0, 10),
      ),
      BoxShadow(color: Color(0x0C335538), blurRadius: 3, offset: Offset(0, 2)),
    ],
  );
}
